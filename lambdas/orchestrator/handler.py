"""Lab orchestrator.

Invoked asynchronously by the session handler when a learner starts a
lab, and again (with ``action=terminate``) when a session is ended.

Implements docs/15 steps 4 to 8 and 10 to 12:

    retrieve approved AMI -> launch tagged instance -> Tailscale
    enrollment -> READY, and terminate -> TERMINATED on the way out.
"""

import logging
import time

from common import activity as events
from common import lab_ops
from common import states
from common.activity import iso, utc_now
from common.config import Config
from common.repository import Repository

LOG = logging.getLogger(__name__)
LOG.setLevel(logging.INFO)

POLL_INTERVAL_SECONDS = 10


class Orchestrator:
    def __init__(self, repo, config, ec2=None, ssm=None, sleep=time.sleep):
        self.repo = repo
        self.config = config
        self._ec2 = ec2
        self._ssm = ssm
        self._sleep = sleep

    @property
    def ec2(self):
        if self._ec2 is None:
            import boto3

            self._ec2 = boto3.client("ec2", region_name=self.config.region)
        return self._ec2

    @property
    def ssm(self):
        if self._ssm is None:
            import boto3

            self._ssm = boto3.client("ssm", region_name=self.config.region)
        return self._ssm

    # -- AMI resolution ------------------------------------------------

    def resolve_ami(self, lab):
        """Read the approved AMI id from SSM Parameter Store."""
        parameter = lab.get("amiParameter") or "{}/linux".format(
            self.config.ami_parameter_prefix
        )
        # Parameters are SecureString (terraform/modules/lab), so the
        # value has to be decrypted server-side.
        response = self.ssm.get_parameter(Name=parameter, WithDecryption=True)
        ami_id = (response.get("Parameter") or {}).get("Value", "").strip()
        if not ami_id:
            raise lab_ops.ProvisioningError(
                "SSM parameter '{}' is empty.".format(parameter)
            )
        return ami_id

    # -- state transitions ---------------------------------------------

    def _move(self, session, state, **attrs):
        updates = dict(attrs)
        updates["state"] = state
        session = self.repo.update_session(session["sessionId"], **updates)
        return session

    def _fail(self, session, message, user=None):
        LOG.error("Session %s failed: %s", session.get("sessionId"), message)
        session = self._move(
            session,
            states.FAILED,
            errorMessage=str(message)[:500],
            terminationReason="provisioning_failed",
        )
        events.record(
            self.repo,
            events.LAB_FAILED,
            "{} failed: {}".format(session["sessionId"], message),
            level=events.LEVEL_ERROR,
            user=user,
            session_id=session["sessionId"],
        )
        return session

    # -- launch --------------------------------------------------------

    def launch(self, session, user=None):
        session_id = session.get("sessionId")
        try:
            session = self._move(session, states.PENDING)
            lab = self.repo.get_lab(session.get("labId")) or {}
            ami_id = self.resolve_ami(lab)

            session = self._move(session, states.PROVISIONING)
            events.record(
                self.repo,
                events.LAB_PROVISIONING,
                "{} launching {} from approved AMI".format(
                    session_id, lab.get("instanceType", "instance")
                ),
                user=user,
                session_id=session_id,
            )

            instance_id = lab_ops.launch_instance(
                self.ec2, self.config, session, lab, ami_id
            )
            session = self._move(session, states.PROVISIONING, instanceId=instance_id)

            session = self._move(session, states.TAILSCALE_ENROLLMENT)
            if not self._wait_until_ready(instance_id):
                return self._fail(
                    session,
                    "Instance {} never passed its status checks.".format(instance_id),
                    user=user,
                )

            session = self._move(
                session,
                states.READY,
                tailscaleHostname=lab_ops.hostname_for(session, lab),
            )
            events.record(
                self.repo,
                events.LAB_READY,
                "{} is READY".format(session_id),
                user=user,
                session_id=session_id,
            )
            return session
        except Exception as exc:  # noqa: BLE001 - reported as a session failure
            LOG.exception("Launch failed for %s", session_id)
            return self._fail(session, str(exc), user=user)

    def _wait_until_ready(self, instance_id):
        """Block until both EC2 status checks pass, or the budget expires."""
        deadline = time.time() + self.config.ready_timeout_seconds
        while time.time() < deadline:
            statuses = self.ec2.describe_instance_status(
                InstanceIds=[instance_id], IncludeAllInstances=True
            ).get("InstanceStatuses") or []
            if statuses:
                status = statuses[0]
                instance_ok = (status.get("InstanceStatus") or {}).get("Status")
                system_ok = (status.get("SystemStatus") or {}).get("Status")
                if instance_ok == "ok" and system_ok == "ok":
                    return True
                state = (status.get("InstanceState") or {}).get("Name")
                if state in ("terminated", "shutting-down", "stopped"):
                    return False
            self._sleep(POLL_INTERVAL_SECONDS)
        return False

    # -- terminate -----------------------------------------------------

    def terminate(self, session, reason="ttl", user=None):
        session_id = session.get("sessionId")
        instance_id = session.get("instanceId")
        event_kind = {
            "ttl": events.LAB_TERMINATED_BY_TTL,
            "admin": events.LAB_TERMINATED_BY_ADMIN,
            "user": events.LAB_TERMINATED_BY_USER,
        }.get(reason, events.LAB_TERMINATED_BY_TTL)

        session = self._move(
            session,
            states.TERMINATING,
            endedAt=session.get("endedAt") or iso(utc_now()),
            terminationReason=reason,
        )

        if instance_id:
            try:
                lab_ops.terminate_instance(self.ec2, instance_id)
            except Exception:  # noqa: BLE001 - GC retries on the next tick
                LOG.exception("Could not terminate %s", instance_id)
                return session

        session = self._move(session, states.TERMINATED)
        events.record(
            self.repo,
            event_kind,
            "{} terminated ({})".format(session_id, reason),
            user=user,
            session_id=session_id,
        )
        return session


def build_orchestrator(repo=None, config=None, ec2=None, ssm=None, sleep=time.sleep):
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
    return Orchestrator(repo=repo, config=config, ec2=ec2, ssm=ssm, sleep=sleep)


def lambda_handler(event, context):  # pragma: no cover - exercised in AWS
    orchestrator = build_orchestrator()
    payload = event or {}
    session = payload.get("session") or {}
    user = {"userId": payload.get("requestedBy")} if payload.get("requestedBy") else None

    if payload.get("action") == "terminate":
        return orchestrator.terminate(session, reason=payload.get("reason", "ttl"))
    return orchestrator.launch(session, user=user)
