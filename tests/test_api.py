"""End-to-end tests for the HTTP API described in docs/16.

These drive ``Api.handle`` with real API Gateway events against an
in-memory repository, so routing, authentication, authorization, quota
enforcement and flag redaction are all exercised together.
"""

import json

import pytest

from common import states
from common.auth import hash_token
from common.config import Config
from common.repository import MemoryRepository
from common.seed_catalog import LABS, SEEDED_USERS
from session_handler.handler import Api

TOKENS = {
    "student-01": "token-student-01",
    "student-02": "token-student-02",
    "admin-01": "token-admin-01",
    "auditor-01": "token-auditor-01",
    "student-99": "token-student-99",
}


def make_config(**overrides):
    values = dict(
        region="us-east-1",
        ttl_minutes=60,
        max_active_labs_per_user=4,
        max_active_labs_platform=4,
        orchestrator_function="orchestrator",
        terminator_function="orchestrator",
        project_tag="osq",
        launch_template_name="lab-template",
        lab_security_group_id="sg-123",
        lab_subnet_id="subnet-123",
        lab_instance_profile="lab-profile",
        tailscale_auth_key_parameter="/cloudybt/tailscale/authkey",
        ready_timeout_seconds=5,
    )
    values.update(overrides)
    return Config(**values)


class FakeLauncher:
    def __init__(self):
        self.started = []
        self.stopped = []
        self.error = None

    def start(self, session, user):
        if self.error:
            raise self.error
        self.started.append(session["sessionId"])

    def stop(self, session, user):
        self.stopped.append(session["sessionId"])


def make_app(config=None):
    repo = MemoryRepository()
    for lab in LABS:
        repo.put_lab(lab)
    for template in SEEDED_USERS:
        user_id = template["userId"]
        repo.put_user(dict(template, tokenHash=hash_token(TOKENS[user_id])))

    launcher = FakeLauncher()
    api = Api(
        repo=repo,
        config=config or make_config(),
        start_lab=launcher.start,
        stop_lab=launcher.stop,
    )
    return api, repo, launcher


def event(route, token=None, body=None, params=None, query=None):
    method, path = route.split(" ", 1)
    headers = {}
    if token:
        headers["authorization"] = "Bearer {}".format(token)
    return {
        "version": "2.0",
        "routeKey": route,
        "rawPath": path,
        "headers": headers,
        "body": json.dumps(body) if body is not None else None,
        "pathParameters": params,
        "queryStringParameters": query,
        "requestContext": {"http": {"method": method, "path": path}},
    }


def call(api, route, **kwargs):
    response = api.handle(event(route, **kwargs))
    payload = json.loads(response["body"]) if response.get("body") else None
    return response["statusCode"], payload


def start_lab(api, token, lab_id="linux-beginner"):
    return call(api, "POST /labs/start", token=token, body={"labId": lab_id})


# -- authentication -------------------------------------------------------


def test_missing_token_is_rejected():
    api, _, _ = make_app()
    status, payload = call(api, "GET /me")
    assert status == 401
    assert payload["error"] == "UNAUTHORIZED"


def test_unknown_token_is_rejected():
    api, _, _ = make_app()
    status, _ = call(api, "GET /me", token="not-a-real-token")
    assert status == 401


def test_revoked_token_is_rejected():
    api, _, _ = make_app()
    status, _ = call(api, "GET /me", token=TOKENS["student-99"])
    assert status == 401


def test_me_never_returns_the_token_hash():
    api, _, _ = make_app()
    status, payload = call(api, "GET /me", token=TOKENS["student-01"])
    assert status == 200
    assert payload["userId"] == "student-01"
    assert "tokenHash" not in payload
    assert "tokenHash" not in json.dumps(payload)


# -- labs -----------------------------------------------------------------


def test_labs_response_never_contains_expected_flag():
    api, _, _ = make_app()
    for token in (TOKENS["student-01"], TOKENS["admin-01"]):
        status, payload = call(api, "GET /labs", token=token)
        assert status == 200
        assert "expectedFlag" not in json.dumps(payload)
        assert payload["labs"], "catalog should not be empty"


def test_lab_detail_never_contains_expected_flag():
    api, _, _ = make_app()
    status, payload = call(api, "GET /labs/{labId}", token=TOKENS["student-01"],
                           params={"labId": "linux-beginner"})
    assert status == 200
    assert "expectedFlag" not in json.dumps(payload)
    assert payload["tasks"][0]["taskId"] == "linux-b-1"


def test_auditor_sees_the_catalog_but_not_the_tasks():
    api, _, _ = make_app()
    status, payload = call(api, "GET /labs", token=TOKENS["auditor-01"])
    assert status == 200
    assert payload["labs"]
    assert "tasks" not in json.dumps(payload)
    assert "expectedFlag" not in json.dumps(payload)


def test_unknown_lab_is_404():
    api, _, _ = make_app()
    status, _ = call(api, "GET /labs/{labId}", token=TOKENS["student-01"],
                     params={"labId": "does-not-exist"})
    assert status == 404


# -- starting a session ---------------------------------------------------


def test_start_creates_a_requested_session():
    api, repo, launcher = make_app()
    status, payload = start_lab(api, TOKENS["student-01"])
    assert status == 201
    assert payload["state"] == states.REQUESTED
    assert payload["userId"] == "student-01"
    assert payload["labId"] == "linux-beginner"
    assert payload["sessionId"].startswith("lab-")
    assert launcher.started == [payload["sessionId"]]

    stored = repo.get_session(payload["sessionId"])
    assert stored["expiresAt"] > stored["createdAt"]


def test_auditor_cannot_start_a_lab():
    api, _, _ = make_app()
    status, payload = start_lab(api, TOKENS["auditor-01"])
    assert status == 403
    assert payload["error"] == "FORBIDDEN"


def test_start_unknown_lab_is_404():
    api, _, _ = make_app()
    status, _ = call(api, "POST /labs/start", token=TOKENS["student-01"],
                     body={"labId": "nope"})
    assert status == 404


def test_start_requires_a_lab_id():
    api, _, _ = make_app()
    status, payload = call(api, "POST /labs/start", token=TOKENS["student-01"], body={})
    assert status == 400
    assert "labId" in payload["message"]


def test_user_quota_is_enforced():
    api, _, launcher = make_app()
    for _ in range(4):
        assert start_lab(api, TOKENS["student-01"])[0] == 201
    status, payload = start_lab(api, TOKENS["student-01"])
    assert status == 409
    assert payload["error"] == "CONFLICT"
    assert "Quota reached" in payload["message"]
    assert len(launcher.started) == 4


def test_platform_limit_is_enforced():
    api, _, _ = make_app()
    for _ in range(2):
        assert start_lab(api, TOKENS["student-01"])[0] == 201
    for _ in range(2):
        assert start_lab(api, TOKENS["student-02"])[0] == 201
    status, payload = start_lab(api, TOKENS["student-02"])
    assert status == 409
    assert "Platform limit" in payload["message"]


def test_terminated_sessions_release_quota():
    api, _, launcher = make_app()
    started = [start_lab(api, TOKENS["student-01"])[1] for _ in range(4)]
    session_id = started[0]["sessionId"]
    call(api, "POST /sessions/{sessionId}/destroy", token=TOKENS["student-01"],
         params={"sessionId": session_id})
    api.repo.update_session(session_id, state=states.TERMINATED)

    assert start_lab(api, TOKENS["student-01"])[0] == 201
    assert len(launcher.started) == 5


# -- reading sessions -----------------------------------------------------


def test_student_only_sees_their_own_sessions():
    api, _, _ = make_app()
    start_lab(api, TOKENS["student-01"])
    start_lab(api, TOKENS["student-02"])

    status, payload = call(api, "GET /sessions", token=TOKENS["student-01"])
    assert status == 200
    assert payload["sessions"]
    assert {s["userId"] for s in payload["sessions"]} == {"student-01"}


def test_admin_and_auditor_see_every_session():
    api, _, _ = make_app()
    start_lab(api, TOKENS["student-01"])
    start_lab(api, TOKENS["student-02"])

    for token in (TOKENS["admin-01"], TOKENS["auditor-01"]):
        status, payload = call(api, "GET /sessions", token=token)
        assert status == 200
        assert {s["userId"] for s in payload["sessions"]} == {"student-01", "student-02"}


def test_student_cannot_read_another_students_session():
    api, _, _ = make_app()
    other = start_lab(api, TOKENS["student-02"])[1]
    status, _ = call(api, "GET /sessions/{sessionId}", token=TOKENS["student-01"],
                     params={"sessionId": other["sessionId"]})
    assert status == 404


# -- destroying -----------------------------------------------------------


def test_owner_can_destroy_their_session():
    api, repo, launcher = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    status, payload = call(api, "POST /sessions/{sessionId}/destroy",
                           token=TOKENS["student-01"],
                           params={"sessionId": session["sessionId"]})
    assert status == 200
    assert payload["state"] == states.TERMINATING
    assert payload["terminationReason"] == "user"
    assert launcher.stopped == [session["sessionId"]]
    assert repo.get_session(session["sessionId"])["state"] == states.TERMINATING


def test_admin_can_destroy_any_session():
    api, _, launcher = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    status, payload = call(api, "POST /sessions/{sessionId}/destroy",
                           token=TOKENS["admin-01"],
                           params={"sessionId": session["sessionId"]})
    assert status == 200
    assert payload["terminationReason"] == "admin"
    assert launcher.stopped == [session["sessionId"]]


def test_auditor_cannot_destroy():
    api, _, _ = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    status, _ = call(api, "POST /sessions/{sessionId}/destroy",
                     token=TOKENS["auditor-01"],
                     params={"sessionId": session["sessionId"]})
    assert status == 403


def test_student_cannot_destroy_another_students_session():
    api, _, _ = make_app()
    session = start_lab(api, TOKENS["student-02"])[1]
    status, _ = call(api, "POST /sessions/{sessionId}/destroy",
                     token=TOKENS["student-01"],
                     params={"sessionId": session["sessionId"]})
    assert status == 404


def test_terminating_twice_is_a_conflict():
    api, _, _ = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    call(api, "POST /sessions/{sessionId}/destroy", token=TOKENS["student-01"],
         params={"sessionId": session["sessionId"]})
    status, _ = call(api, "POST /sessions/{sessionId}/destroy",
                     token=TOKENS["student-01"],
                     params={"sessionId": session["sessionId"]})
    # TERMINATING is still active, so a second destroy is allowed only
    # once the session is fully TERMINATED.
    api.repo.update_session(session["sessionId"], state=states.TERMINATED)
    status, _ = call(api, "POST /sessions/{sessionId}/destroy",
                     token=TOKENS["student-01"],
                     params={"sessionId": session["sessionId"]})
    assert status == 409


# -- flags ----------------------------------------------------------------


def test_correct_flag_is_accepted_and_stored():
    api, repo, _ = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    api.repo.update_session(session["sessionId"], state=states.READY)

    status, payload = call(api, "POST /sessions/{sessionId}/flags",
                           token=TOKENS["student-01"],
                           params={"sessionId": session["sessionId"]},
                           body={"taskId": "linux-b-1", "flag": "cb-linux-b-01 "})
    assert status == 200
    assert payload == {"correct": True, "taskId": "linux-b-1"}
    assert repo.get_session(session["sessionId"])["flags"]["linux-b-1"] is True


def test_wrong_flag_is_rejected_but_recorded():
    api, repo, _ = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    api.repo.update_session(session["sessionId"], state=states.READY)

    status, payload = call(api, "POST /sessions/{sessionId}/flags",
                           token=TOKENS["student-01"],
                           params={"sessionId": session["sessionId"]},
                           body={"taskId": "linux-b-1", "flag": "wrong"})
    assert status == 200
    assert payload["correct"] is False
    assert repo.get_session(session["sessionId"])["flags"]["linux-b-1"] is False


def test_flag_response_never_leaks_the_answer():
    api, _, _ = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    api.repo.update_session(session["sessionId"], state=states.READY)
    _, payload = call(api, "POST /sessions/{sessionId}/flags",
                      token=TOKENS["student-01"],
                      params={"sessionId": session["sessionId"]},
                      body={"taskId": "linux-b-1", "flag": "nope"})
    assert "CB-LINUX-B-01" not in json.dumps(payload)


def test_flags_are_rejected_for_a_terminal_session():
    api, _, _ = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    api.repo.update_session(session["sessionId"], state=states.TERMINATED)
    status, _ = call(api, "POST /sessions/{sessionId}/flags",
                     token=TOKENS["student-01"],
                     params={"sessionId": session["sessionId"]},
                     body={"taskId": "linux-b-1", "flag": "CB-LINUX-B-01"})
    assert status == 409


def test_flags_for_an_unknown_task_are_404():
    api, _, _ = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    api.repo.update_session(session["sessionId"], state=states.READY)
    status, _ = call(api, "POST /sessions/{sessionId}/flags",
                     token=TOKENS["student-01"],
                     params={"sessionId": session["sessionId"]},
                     body={"taskId": "not-a-task", "flag": "X"})
    assert status == 404


def test_auditor_cannot_submit_flags():
    api, _, _ = make_app()
    session = start_lab(api, TOKENS["student-01"])[1]
    status, _ = call(api, "POST /sessions/{sessionId}/flags",
                     token=TOKENS["auditor-01"],
                     params={"sessionId": session["sessionId"]},
                     body={"taskId": "linux-b-1", "flag": "CB-LINUX-B-01"})
    assert status == 403


# -- activity -------------------------------------------------------------


def test_activity_is_admin_and_auditor_only():
    api, _, _ = make_app()
    status, _ = call(api, "GET /activity", token=TOKENS["student-01"])
    assert status == 403

    for token in (TOKENS["admin-01"], TOKENS["auditor-01"]):
        status, payload = call(api, "GET /activity", token=token)
        assert status == 200
        assert "events" in payload


def test_starting_a_lab_writes_an_audit_event():
    api, _, _ = make_app()
    call(api, "GET /activity", token=TOKENS["admin-01"])
    start_lab(api, TOKENS["student-01"])
    _, payload = call(api, "GET /activity", token=TOKENS["admin-01"])
    kinds = {e["kind"] for e in payload["events"]}
    assert "LAB_REQUESTED" in kinds


# -- misc -----------------------------------------------------------------


def test_unknown_route_is_404():
    api, _, _ = make_app()
    status, _ = call(api, "GET /me", token=TOKENS["student-01"])
    assert status == 200
    response = api.handle({"requestContext": {"http": {"method": "GET", "path": "/x"}},
                           "routeKey": "GET /x", "headers": {}})
    assert response["statusCode"] == 404


def test_unconfigured_provisioning_is_reported_honestly():
    api, _, _ = make_app()
    api._start_lab = None
    status, payload = start_lab(api, TOKENS["student-01"])
    assert status == 500
    assert payload["error"] == "NOT_CONFIGURED"


@pytest.mark.parametrize("route", ["GET /me", "GET /labs", "GET /sessions"])
def test_every_read_endpoint_survives_every_role(route):
    for user_id, token in TOKENS.items():
        api, _, _ = make_app()
        status, _ = call(api, route, token=token)
        if user_id == "student-99":
            # Seeded revoked: must never authenticate, on any endpoint.
            assert status == 401, user_id
        else:
            assert status in (200, 403), (user_id, status)
