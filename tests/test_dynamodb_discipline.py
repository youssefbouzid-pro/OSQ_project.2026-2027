"""Everything the handlers write must actually be storable in DynamoDB.

``MemoryRepository`` is a plain dict store, so it will happily accept a
Python ``set`` or a ``datetime`` that DynamoDB cannot serialize. These
tests pin the discipline: after a full API flow every stored value is a
DynamoDB scalar (or a list/dict of them) and round-trips through
boto3's real ``TypeSerializer``.
"""

import datetime

import pytest
from boto3.dynamodb.types import TypeSerializer

import seed_users
from common import lab_ops
from common.auth import hash_token
from common.config import Config
from common.repository import MemoryRepository
from common.seed_catalog import LABS, SEEDED_USERS, labs_by_id
from session_handler.handler import Api

ALLOWED_LEAF_TYPES = (str, int, float, bool, type(None))

TOKENS = {
    "student-01": "token-student-01",
    "student-02": "token-student-02",
    "admin-01": "token-admin-01",
    "auditor-01": "token-auditor-01",
    "student-99": "token-student-99",
}


def assert_dynamo_safe(value, path="$"):
    """Reject anything DynamoDB's serializer cannot round-trip."""
    if isinstance(value, dict):
        for key, item in value.items():
            assert isinstance(key, str), "{}: key {!r} is not a string".format(path, key)
            assert_dynamo_safe(item, "{}.{}".format(path, key))
        return
    if isinstance(value, (list, tuple)):
        for index, item in enumerate(value):
            assert_dynamo_safe(item, "{}[{}]".format(path, index))
        return

    assert isinstance(value, ALLOWED_LEAF_TYPES), (
        "{}: {} is not a DynamoDB scalar (got {})".format(path, value, type(value).__name__)
    )
    TypeSerializer().serialize(value)


def make_app():
    repo = MemoryRepository()
    for lab in LABS:
        repo.put_lab(lab)
    for template in SEEDED_USERS:
        user_id = template["userId"]
        repo.put_user(dict(template, tokenHash=hash_token(TOKENS[user_id])))

    api = Api(
        repo=repo,
        config=Config(
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
        ),
        start_lab=lambda session, user: None,
        stop_lab=lambda session, user: None,
    )
    return api, repo


def drive_a_full_session(api, repo):
    """start -> progress -> flag -> destroy, the whole learner journey."""
    import json

    def call(route, token, body=None, params=None):
        method, path = route.split(" ", 1)
        event = {
            "routeKey": route,
            "rawPath": path,
            "headers": {"authorization": "Bearer {}".format(token)},
            "body": json.dumps(body) if body is not None else None,
            "pathParameters": params or {},
            "requestContext": {"http": {"method": method, "path": path}},
        }
        return api.handle(event)

    started = json.loads(
        call("POST /labs/start", TOKENS["student-01"], body={"labId": "linux-beginner"})["body"]
    )
    repo.update_session(started["sessionId"], state="READY", instanceId="i-0abc")

    call(
        "POST /sessions/{sessionId}/flags",
        TOKENS["student-01"],
        body={"taskId": "linux-b-1", "flag": "cb-linux-b-01"},
        params={"sessionId": started["sessionId"]},
    )
    call(
        "POST /sessions/{sessionId}/destroy",
        TOKENS["student-01"],
        params={"sessionId": started["sessionId"]},
    )
    return started


def test_a_full_api_flow_only_writes_storable_values():
    api, repo = make_app()
    drive_a_full_session(api, repo)

    for name, table in (
        ("users", repo.users),
        ("labs", repo.labs),
        ("sessions", repo.sessions),
        ("activity", repo.activity),
    ):
        for key, item in table.items.items():
            TypeSerializer().serialize(item)
            assert_dynamo_safe(item, "{}[{}]".format(name, key))


def test_sets_are_rejected():
    api, repo = make_app()
    with pytest.raises(AssertionError):
        assert_dynamo_safe({"userId": "student-01", "roles": {"student", "admin"}})


def test_datetimes_are_rejected():
    api, repo = make_app()
    with pytest.raises(AssertionError):
        assert_dynamo_safe({"createdAt": datetime.datetime(2026, 4, 14)})


def test_session_fields_written_by_the_api_are_scalars():
    api, repo = make_app()
    started = drive_a_full_session(api, repo)
    session = repo.get_session(started["sessionId"])
    for field in ("sessionId", "userId", "labId", "state", "createdAt", "expiresAt",
                  "endedAt", "instanceId", "flags", "terminationReason"):
        if field in session:
            assert_dynamo_safe(session[field], "session.{}".format(field))


# -- user-data ------------------------------------------------------------


def test_user_data_includes_task_instructions_without_answers():
    config = Config.from_env(
        {"TAILSCALE_AUTH_KEY_PARAMETER": "/cloudybt/tailscale/authkey", "AWS_REGION": "us-east-1"}
    )
    lab = labs_by_id()["linux-beginner"]
    session = {
        "sessionId": "lab-abc123",
        "userId": "student-01",
        "labId": "linux-beginner",
        "expiresAt": "2026-04-14T11:00:00Z",
    }
    script = lab_ops.build_user_data(config, session, lab)

    assert "mkdir -p /etc/osq" in script
    assert "Locate the application config" in script
    assert "Fix the config permissions" in script
    assert "CB-LINUX-B-01" not in script
    assert "CB-LINUX-B-02" not in script
    assert "expectedFlag" not in script
    assert script.count("<<'SESSION'") == 1
    assert script.count("<<'TASKS'") == 1


def test_user_data_heredocs_are_balanced():
    config = Config.from_env({"TAILSCALE_AUTH_KEY_PARAMETER": "/cloudybt/tailscale/authkey"})
    script = lab_ops.build_user_data(
        config,
        {"sessionId": "lab-1", "labId": "linux-beginner", "expiresAt": "x"},
        labs_by_id()["linux-beginner"],
    )
    # Every opener has a matching delimiter on its own line.
    lines = [line.strip() for line in script.splitlines()]
    assert lines.count("cat > /etc/osq/session.json <<'SESSION'") == 1
    assert lines.count("SESSION") == 1
    assert lines.count("cat > /etc/osq/tasks.json <<'TASKS'") == 1
    assert lines.count("TASKS") == 1
    assert "set -euo pipefail" in lines


# -- seed_users -----------------------------------------------------------


class FakeTable:
    def __init__(self):
        self.items = {}

    def get_item(self, Key):
        item = self.items.get(Key["userId"])
        return {"Item": dict(item)} if item else {}

    def put_item(self, Item):
        self.items[Item["userId"]] = dict(Item)
        return {}


def test_seed_users_stores_only_a_hash():
    table = FakeTable()
    created, rotated, skipped = seed_users.seed(table, SEEDED_USERS[:1])

    assert len(created) == 1
    user_id, token = created[0]
    stored = table.items[user_id]
    assert "token" not in stored
    assert stored["tokenHash"] == hash_token(token)
    assert stored["role"] == "student"


def test_seed_users_is_idempotent():
    table = FakeTable()
    first, _, _ = seed_users.seed(table, SEEDED_USERS[:1])
    original_token = first[0][1]

    second, rotated, skipped = seed_users.seed(table, SEEDED_USERS[:1])

    assert second == []
    assert rotated == []
    assert skipped == [SEEDED_USERS[0]["userId"]]
    assert table.items[SEEDED_USERS[0]["userId"]]["tokenHash"] == hash_token(original_token)


def test_seed_users_rotate_replaces_the_hash():
    table = FakeTable()
    first, _, _ = seed_users.seed(table, SEEDED_USERS[:1])
    original_token = first[0][1]

    second, rotated, skipped = seed_users.seed(table, SEEDED_USERS[:1], rotate=True)

    assert second == []
    assert len(rotated) == 1
    new_token = rotated[0][1]
    assert new_token != original_token
    assert table.items[SEEDED_USERS[0]["userId"]]["tokenHash"] == hash_token(new_token)
