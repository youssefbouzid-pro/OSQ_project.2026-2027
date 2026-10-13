"""Session handler: the HTTP API described in ``docs/16-api-and-data-model.md``.

One Lambda behind API Gateway HTTP API routes every request. Routes,
the authorization matrix, and the flag redaction rule are all taken
verbatim from docs/16.
"""

import json
import logging
import uuid
from datetime import timedelta

from common import activity as events
from common import auth
from common import catalog as cat
from common import states
from common.activity import iso, utc_now
from common.config import Config
from common.errors import ApiError, bad_request, conflict, forbidden, not_found
from common.http import error_response, parse_event, response
from common.repository import Repository

LOG = logging.getLogger(__name__)
LOG.setLevel(logging.INFO)

ROLE_STUDENT = auth.ROLE_STUDENT
ROLE_ADMIN = auth.ROLE_ADMIN
ROLE_AUDITOR = auth.ROLE_AUDITOR


class Api:
    """Request router. Side effects are injected so tests can fake AWS."""

    def __init__(self, repo, config, start_lab=None, stop_lab=None):
        self.repo = repo
        self.config = config
        self._start_lab = start_lab
        self._stop_lab = stop_lab
        self.routes = {
            "GET /me": self.handle_me,
            "GET /labs": self.handle_labs,
            "GET /labs/{labId}": self.handle_lab,
            "POST /labs/start": self.handle_start,
            "GET /sessions": self.handle_sessions,
            "GET /sessions/{sessionId}": self.handle_session,
            "POST /sessions/{sessionId}/destroy": self.handle_destroy,
            "POST /sessions/{sessionId}/flags": self.handle_flag,
            "GET /activity": self.handle_activity,
        }

    # -- dispatch ------------------------------------------------------

    def handle(self, event):
        try:
            request = parse_event(event)
        except ValueError as exc:
            return error_response(400, {"error": "BAD_REQUEST", "message": str(exc)})

        handler = self.routes.get(request.route)
        if handler is None:
            return error_response(
                404, {"error": "NOT_FOUND", "message": "No such endpoint."}
            )

        try:
            user = auth.authenticate(self.repo, request.authorization)
            return handler(request, user)
        except ApiError as exc:
            return error_response(exc.status, exc.body)
        except ValueError as exc:
            return error_response(400, {"error": "BAD_REQUEST", "message": str(exc)})
        except Exception:  # noqa: BLE001 - never leak internals to the client
            LOG.exception("Unhandled error on %s", request.route)
            return error_response(
                500, {"error": "INTERNAL", "message": "Unexpected server error."}
            )

    # -- serialization -------------------------------------------------

    def session_view(self, session):
        """Serialize a session using exactly the docs/16 attribute names."""
        return {
            "sessionId": session.get("sessionId"),
            "userId": session.get("userId"),
            "labId": session.get("labId"),
            "state": session.get("state"),
            "createdAt": session.get("createdAt"),
            "expiresAt": session.get("expiresAt"),
            "endedAt": session.get("endedAt"),
            "instanceId": session.get("instanceId"),
            "tailscaleHostname": session.get("tailscaleHostname"),
            "flags": session.get("flags") or {},
            "terminationReason": session.get("terminationReason"),
        }

    def _require_active(self, session):
        if not states.is_active(session.get("state")):
            raise conflict("This session has already ended.")
        return session

    def _load_session(self, request, user):
        session_id = request.path_params.get("sessionId")
        session = self.repo.get_session(session_id) if session_id else None
        if session is None:
            raise not_found("Session not found.")

        if user.get("role") == ROLE_STUDENT and session.get("userId") != user.get(
            "userId"
        ):
            # Do not reveal that the session exists.
            raise not_found("Session not found.")
        return session

    # -- handlers ------------------------------------------------------

    def handle_me(self, request, user):
        # tokenHash must never leave the server.
        return response(
            200,
            {
                "userId": user.get("userId"),
                "email": user.get("email"),
                "role": user.get("role"),
                "maxConcurrentLabs": user.get("maxConcurrentLabs"),
                "isActive": user.get("isActive", False),
            },
        )

    def handle_labs(self, request, user):
        # docs/16: auditor sees the catalog but not the task content.
        include_tasks = user.get("role") != ROLE_AUDITOR
        labs = sorted(self.repo.list_labs(), key=lambda l: l.get("labId", ""))
        return response(
            200, {"labs": [cat.public_lab(l, include_tasks) for l in labs]}
        )

    def handle_lab(self, request, user):
        lab = self.repo.get_lab(request.path_params.get("labId"))
        if lab is None:
            raise not_found("Lab not found.")
        include_tasks = user.get("role") != ROLE_AUDITOR
        return response(200, cat.public_lab(lab, include_tasks))

    def handle_start(self, request, user):
        auth.require_roles(user, ROLE_STUDENT, ROLE_ADMIN)

        payload = request.json()
        lab_id = cat.require_string(payload, "labId")
        lab = self.repo.get_lab(lab_id)
        if lab is None:
            raise not_found("Lab not found.")

        self._check_quota(user)

        created = utc_now()
        ttl_minutes = int(lab.get("ttlMinutes") or self.config.ttl_minutes)
        session = {
            "sessionId": "lab-" + uuid.uuid4().hex[:8],
            "userId": user.get("userId"),
            "labId": lab_id,
            "state": states.REQUESTED,
            "createdAt": iso(created),
            "expiresAt": iso(created + timedelta(minutes=ttl_minutes)),
            "flags": {},
        }
        self.repo.put_session(session)

        events.record(
            self.repo,
            events.LAB_REQUESTED,
            "{} requested: {} ({})".format(
                session["sessionId"], lab.get("name", lab_id), lab.get("level", "")
            ),
            user=user,
            session_id=session["sessionId"],
        )

        self._dispatch_start(session, user)
        return response(201, self.session_view(session))

    def handle_sessions(self, request, user):
        role = user.get("role")
        if role == ROLE_STUDENT:
            sessions = self.repo.list_sessions_for_user(user.get("userId"))
        else:
            # admin: all; auditor: read-only copy of all
            sessions = self.repo.list_sessions(limit=200)
        return response(200, {"sessions": [self.session_view(s) for s in sessions]})

    def handle_session(self, request, user):
        session = self._load_session(request, user)
        return response(200, self.session_view(session))

    def handle_destroy(self, request, user):
        role = user.get("role")
        if role == ROLE_AUDITOR:
            raise forbidden("Auditors cannot modify sessions.")

        session = self._load_session(request, user)
        if session.get("state") == states.TERMINATED:
            raise conflict("Session already terminated.")

        reason = states.TERMINATING
        now = iso(utc_now())
        session = self.repo.update_session(
            session["sessionId"],
            state=reason,
            endedAt=now,
            terminationReason="admin" if role == ROLE_ADMIN else "user",
        )

        events.record(
            self.repo,
            events.LAB_TERMINATED_BY_ADMIN
            if role == ROLE_ADMIN
            else events.LAB_TERMINATED_BY_USER,
            "{} ended by {}".format(session["sessionId"], role),
            user=user,
            session_id=session["sessionId"],
        )

        self._dispatch_stop(session, user)
        return response(200, self.session_view(session))

    def handle_flag(self, request, user):
        auth.require_roles(user, ROLE_STUDENT, ROLE_ADMIN)

        session = self._load_session(request, user)
        self._require_active(session)

        payload = request.json()
        task_id = cat.require_string(payload, "taskId")
        submitted = payload.get("flag", "")

        lab = self.repo.get_lab(session.get("labId"))
        if lab is None:
            raise not_found("Lab not found.")
        task = cat.resolve_task(lab, task_id)

        events.record(
            self.repo,
            events.FLAG_SUBMITTED,
            "{} submitted flag for {}".format(session["sessionId"], task_id),
            user=user,
            session_id=session["sessionId"],
        )

        correct = cat.matches_flag(task, submitted)
        flags = dict(session.get("flags") or {})
        flags[task_id] = correct
        self.repo.update_session(session["sessionId"], flags=flags)

        events.record(
            self.repo,
            events.FLAG_ACCEPTED if correct else events.FLAG_REJECTED,
            "{} flag for {} was {}".format(
                session["sessionId"], task_id, "accepted" if correct else "rejected"
            ),
            user=user,
            session_id=session["sessionId"],
        )

        # Only the outcome is returned; expectedFlag never is.
        return response(200, {"correct": correct, "taskId": task_id})

    def handle_activity(self, request, user):
        auth.require_roles(user, ROLE_ADMIN, ROLE_AUDITOR)
        limit = int(request.query.get("limit", "100") or "100")
        limit = max(1, min(limit, 500))
        return response(200, {"events": self.repo.list_events(limit=limit)})

    # -- helpers -------------------------------------------------------

    def _check_quota(self, user):
        maximum = user.get("maxConcurrentLabs")
        active = self.repo.count_active_for_user(user.get("userId"))
        if maximum is not None and active >= int(maximum):
            raise conflict(
                "Quota reached ({} of {} active labs). End a session before "
                "starting another.".format(active, maximum)
            )

        platform = self.repo.count_active_platform()
        if platform >= self.config.max_active_labs_platform:
            raise conflict(
                "Platform limit reached ({} active labs). Try again after one "
                "expires.".format(platform)
            )

    def _dispatch_start(self, session, user):
        if self._start_lab is None:
            raise ApiError(500, "Provisioning is not configured.", "NOT_CONFIGURED")
        self._start_lab(session, user)

    def _dispatch_stop(self, session, user):
        if self._stop_lab is None:
            raise ApiError(500, "Provisioning is not configured.", "NOT_CONFIGURED")
        self._stop_lab(session, user)


# ---------------------------------------------------------------------------
# Production wiring
# ---------------------------------------------------------------------------

_CLIENTS = {}


def _boto_client(name):
    import boto3

    if name not in _CLIENTS:
        _CLIENTS[name] = boto3.client(name)
    return _CLIENTS[name]


def make_start_lab(config):
    """Invoke the lab orchestrator asynchronously."""

    def start(session, user):
        if not config.orchestrator_function:
            raise ApiError(
                500, "Provisioning is not configured.", "NOT_CONFIGURED"
            )
        _boto_client("lambda").invoke(
            FunctionName=config.orchestrator_function,
            InvocationType="Event",
            Payload=json.dumps({"session": session, "requestedBy": user.get("userId")}),
        )

    return start


def make_stop_lab(config):
    """Invoke the lab terminator asynchronously."""

    def stop(session, user):
        if not config.terminator_function and not config.orchestrator_function:
            raise ApiError(500, "Provisioning is not configured.", "NOT_CONFIGURED")
        _boto_client("lambda").invoke(
            FunctionName=config.terminator_function or config.orchestrator_function,
            InvocationType="Event",
            Payload=json.dumps({"action": "terminate", "session": session}),
        )

    return stop


def build_api(repo=None, config=None, start_lab=None, stop_lab=None):
    config = config or Config.from_env()
    if repo is None:
        import boto3

        resource = boto3.resource("dynamodb")
        repo = Repository(
            users=resource.Table(config.users_table),
            labs=resource.Table(config.labs_table),
            sessions=resource.Table(config.sessions_table),
            activity=resource.Table(config.activity_table),
        )
    return Api(
        repo=repo,
        config=config,
        start_lab=start_lab if start_lab is not None else make_start_lab(config),
        stop_lab=stop_lab if stop_lab is not None else make_stop_lab(config),
    )


def lambda_handler(event, context):  # pragma: no cover - exercised in AWS
    return build_api().handle(event)
