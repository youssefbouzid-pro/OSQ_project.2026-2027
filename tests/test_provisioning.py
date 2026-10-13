"""Provisioning: tagging, user-data, the orchestrator and the TTL GC."""

import pytest

from common import lab_ops
from common import states
from common.activity import iso, utc_now
from common.config import Config
from common.repository import MemoryRepository
from common.seed_catalog import LABS, labs_by_id
from ttl_gc.handler import GarbageCollector
from orchestrator.handler import Orchestrator

AMI_ID = "ami-0abc1234567890abc"


class FakePaginator:
    def __init__(self, client):
        self._client = client

    def paginate(self, **kwargs):
        return [self._client.describe_instances(**kwargs)]


class FakeEC2:
    def __init__(self):
        self.instances = {}
        self.terminated = []
        self.run_calls = []
        self._counter = 0

    def run_instances(self, **params):
        self._counter += 1
        instance_id = "i-{:08x}".format(self._counter)
        tags = []
        for spec in params.get("TagSpecifications") or []:
            if spec.get("ResourceType") == "instance":
                tags = spec.get("Tags") or []
        self.instances[instance_id] = {
            "InstanceId": instance_id,
            "State": {"Name": "running"},
            "Tags": tags,
        }
        self.run_calls.append(params)
        return {"Instances": [{"InstanceId": instance_id}]}

    def terminate_instances(self, InstanceIds):
        self.terminated.extend(InstanceIds)
        for instance_id in InstanceIds:
            if instance_id in self.instances:
                self.instances[instance_id]["State"] = {"Name": "terminated"}

    def describe_instances(self, InstanceIds=None, Filters=None, **_):
        selected = []
        for instance_id, instance in self.instances.items():
            if InstanceIds and instance_id not in InstanceIds:
                continue
            if Filters and not self._matches(instance, Filters):
                continue
            selected.append(instance)
        return {"Reservations": [{"Instances": selected}]}

    def describe_instance_status(self, InstanceIds=None, **_):
        out = []
        for instance_id in InstanceIds or []:
            instance = self.instances.get(instance_id)
            if not instance:
                continue
            out.append(
                {
                    "InstanceId": instance_id,
                    "InstanceStatus": {"Status": "ok"},
                    "SystemStatus": {"Status": "ok"},
                    "InstanceState": {"Name": instance["State"]["Name"]},
                }
            )
        return {"InstanceStatuses": out}

    def get_paginator(self, name):
        assert name == "describe_instances"
        return FakePaginator(self)

    @staticmethod
    def _matches(instance, filters):
        for flt in filters:
            name, values = flt["Name"], flt["Values"]
            if name.startswith("tag:"):
                key = name[4:]
                tags = {t["Key"]: t["Value"] for t in instance.get("Tags") or []}
                if tags.get(key) not in values:
                    return False
            elif name == "instance-state-name":
                if instance["State"]["Name"] not in values:
                    return False
        return True


class FakeSSM:
    def __init__(self, params=None):
        self.params = params or {"/cloudybt/ami/linux": AMI_ID}
        self.calls = []

    def get_parameter(self, Name, WithDecryption=False):
        self.calls.append(Name)
        if Name not in self.params:
            raise KeyError(Name)
        return {"Parameter": {"Value": self.params[Name]}}


def make_config(**overrides):
    values = dict(
        region="us-east-1",
        ttl_minutes=60,
        ready_timeout_seconds=5,
        launch_template_name="lab-template",
        lab_security_group_id="sg-123",
        lab_subnet_id="subnet-123",
        lab_instance_profile="lab-profile",
        tailscale_auth_key_parameter="/cloudybt/tailscale/authkey",
        project_tag="cloudybttounsi",
    )
    values.update(overrides)
    return Config(**values)


def make_repo():
    repo = MemoryRepository()
    for lab in LABS:
        repo.put_lab(lab)
    return repo


def make_session(repo, user_id="student-01", lab_id="linux-beginner", ttl=60):
    created = utc_now()
    session = {
        "sessionId": "lab-abc123",
        "userId": user_id,
        "labId": lab_id,
        "state": states.REQUESTED,
        "createdAt": iso(created),
        "expiresAt": _plus(created, ttl),
        "flags": {},
    }
    repo.put_session(session)
    return session


def _plus(created, minutes):
    from datetime import timedelta

    return iso(created + timedelta(minutes=minutes))


# -- tagging and user-data ------------------------------------------------


def test_required_tags_from_docs_15():
    config = make_config()
    session = {
        "sessionId": "lab-12345",
        "userId": "student-01",
        "labId": "linux-beginner",
        "createdAt": "2026-04-14T10:00:00Z",
        "expiresAt": "2026-04-14T11:00:00Z",
    }
    tags = {t["Key"]: t["Value"] for t in lab_ops.build_tags(config, session)}
    assert tags["Project"] == "cloudybttounsi"
    assert tags["ManagedBy"] == "lab-manager"
    assert tags["LabId"] == "linux-beginner"
    assert tags["SessionId"] == "lab-12345"
    assert tags["UserId"] == "student-01"
    assert tags["CreatedAt"] == "2026-04-14T10:00:00Z"
    assert tags["ExpiresAt"] == "2026-04-14T11:00:00Z"
    assert tags["TTLMinutes"] == "60"
    assert tags["AutoDestroy"] == "true"


def test_unapproved_instance_type_is_refused():
    with pytest.raises(lab_ops.ProvisioningError):
        lab_ops.assert_approved_instance_type("m5.2xlarge")
    lab_ops.assert_approved_instance_type("t4g.micro")


def test_user_data_never_contains_an_answer_key():
    config = make_config()
    lab = labs_by_id()["linux-beginner"]
    session = {"sessionId": "lab-1", "userId": "u", "labId": "linux-beginner",
               "expiresAt": "2026-04-14T11:00:00Z"}
    script = lab_ops.build_user_data(config, session, lab)
    assert "CB-LINUX-B-01" not in script
    assert "expectedFlag" not in script
    # Task instructions are injected, answers are not.
    assert "Locate the application config" in script


def test_user_data_references_the_tailscale_parameter_not_the_key():
    config = make_config()
    script = lab_ops.build_user_data(
        config, {"sessionId": "lab-1"}, labs_by_id()["linux-beginner"]
    )
    assert "/cloudybt/tailscale/authkey" in script
    assert "--with-decryption" in script


def test_launch_uses_the_hardened_settings():
    config = make_config()
    ec2 = FakeEC2()
    session = {"sessionId": "lab-1", "userId": "u", "labId": "linux-beginner",
               "createdAt": "2026-04-14T10:00:00Z", "expiresAt": "2026-04-14T11:00:00Z"}
    lab = labs_by_id()["linux-beginner"]

    instance_id = lab_ops.launch_instance(ec2, config, session, lab, AMI_ID)

    call = ec2.run_calls[0]
    assert call["ImageId"] == AMI_ID
    assert call["InstanceType"] == "t4g.micro"
    assert call["MetadataOptions"]["HttpTokens"] == "required"
    assert call["LaunchTemplate"]["Name"] == "lab-template"
    assert call["SecurityGroupIds"] == ["sg-123"]
    assert call["SubnetId"] == "subnet-123"
    assert call["IamInstanceProfile"] == {"Name": "lab-profile"}
    volume = call["BlockDeviceMappings"][0]["Ebs"]
    assert volume["DeleteOnTermination"] is True
    assert volume["Encrypted"] is True
    assert instance_id in ec2.instances


def test_launch_refuses_an_unapproved_instance_type():
    config = make_config()
    lab = dict(labs_by_id()["linux-beginner"], instanceType="m5.large")
    with pytest.raises(lab_ops.ProvisioningError):
        lab_ops.launch_instance(FakeEC2(), config, {"sessionId": "lab-1"}, lab, AMI_ID)


# -- orchestrator ---------------------------------------------------------


def make_orchestrator(repo=None, config=None, ec2=None, ssm=None):
    repo = repo or make_repo()
    return (
        Orchestrator(
            repo=repo,
            config=config or make_config(),
            ec2=ec2 or FakeEC2(),
            ssm=ssm or FakeSSM(),
            sleep=lambda _s: None,
        ),
        repo,
    )


def test_launch_reaches_ready():
    orchestrator, repo = make_orchestrator()
    session = make_session(repo)

    result = orchestrator.launch(session)

    assert result["state"] == states.READY
    assert result["instanceId"].startswith("i-")
    assert result["tailscaleHostname"].startswith("linux-")

    kinds = [e["kind"] for e in repo.list_events()]
    assert "LAB_PROVISIONING" in kinds
    assert "LAB_READY" in kinds


def test_launch_resolves_the_ami_from_ssm():
    ssm = FakeSSM({"/cloudybt/ami/linux": AMI_ID})
    orchestrator, repo = make_orchestrator(ssm=ssm)
    orchestrator.launch(make_session(repo))
    assert "/cloudybt/ami/linux" in ssm.calls


def test_launch_fails_when_the_instance_never_becomes_healthy():
    ec2 = FakeEC2()
    ec2.describe_instance_status = lambda **kwargs: {"InstanceStatuses": []}
    orchestrator, repo = make_orchestrator(ec2=ec2, config=make_config(ready_timeout_seconds=0))

    result = orchestrator.launch(make_session(repo))

    assert result["state"] == states.FAILED
    assert "status checks" in result["errorMessage"]
    assert "LAB_FAILED" in [e["kind"] for e in repo.list_events()]


def test_launch_fails_on_an_unapproved_instance_type():
    repo = make_repo()
    repo.put_lab(dict(labs_by_id()["linux-beginner"], instanceType="m5.large"))
    orchestrator, _ = make_orchestrator(repo=repo)

    result = orchestrator.launch(make_session(repo, lab_id="linux-beginner"))

    assert result["state"] == states.FAILED
    assert "approved list" in result["errorMessage"]


def test_terminate_stops_the_instance_and_closes_the_session():
    ec2 = FakeEC2()
    orchestrator, repo = make_orchestrator(ec2=ec2)
    session = make_session(repo)
    session = orchestrator.launch(session)
    instance_id = session["instanceId"]

    result = orchestrator.terminate(session, reason="ttl")

    assert instance_id in ec2.terminated
    assert result["state"] == states.TERMINATED
    assert result["terminationReason"] == "ttl"
    assert "LAB_TERMINATED_BY_TTL" in [e["kind"] for e in repo.list_events()]


# -- garbage collector ----------------------------------------------------


def seed_instance(ec2, session_id, expires_at, state="running"):
    instance_id = "i-{}".format(session_id)
    ec2.instances[instance_id] = {
        "InstanceId": instance_id,
        "State": {"Name": state},
        "Tags": [
            {"Key": "ManagedBy", "Value": "lab-manager"},
            {"Key": "SessionId", "Value": session_id},
            {"Key": "ExpiresAt", "Value": expires_at},
        ],
    }
    return instance_id


def test_expired_instance_is_terminated_and_session_closed():
    past = "2026-04-14T10:00:00Z"
    future = "2999-01-01T00:00:00Z"
    repo = make_repo()
    ec2 = FakeEC2()
    session = make_session(repo)
    instance_id = seed_instance(ec2, session["sessionId"], past)
    repo.update_session(
        session["sessionId"], state=states.READY, instanceId=instance_id
    )

    result = GarbageCollector(repo, make_config(), ec2=ec2).run(now_iso=future)

    assert instance_id in ec2.terminated
    assert result["instances"], "the EC2 sweep should have reaped the instance"
    assert repo.get_session(session["sessionId"])["state"] == states.TERMINATED
    assert repo.get_session(session["sessionId"])["terminationReason"] == "ttl"
    assert "LAB_TERMINATED_BY_TTL" in [e["kind"] for e in repo.list_events()]


def test_unexpired_instance_is_left_alone():
    repo = make_repo()
    ec2 = FakeEC2()
    session = make_session(repo)
    instance_id = seed_instance(ec2, session["sessionId"], "2999-01-01T00:00:00Z")
    repo.update_session(session["sessionId"], state=states.READY, instanceId=instance_id)

    GarbageCollector(repo, make_config(), ec2=ec2).run(now_iso="2026-04-14T10:00:00Z")

    assert instance_id not in ec2.terminated
    assert repo.get_session(session["sessionId"])["state"] == states.READY


def test_orphaned_instance_is_terminated():
    repo = make_repo()
    ec2 = FakeEC2()
    instance_id = seed_instance(ec2, "lab-ghost", "2020-01-01T00:00:00Z")

    result = GarbageCollector(repo, make_config(), ec2=ec2).run(now_iso="2026-04-14T10:00:00Z")

    assert instance_id in ec2.terminated
    assert result["orphans"] or result["instances"]


def test_expired_session_without_an_instance_is_still_closed():
    repo = make_repo()
    ec2 = FakeEC2()
    session = make_session(repo, ttl=60)
    repo.update_session(session["sessionId"], state=states.READY)
    repo.sessions.items[session["sessionId"]]["expiresAt"] = "2020-01-01T00:00:00Z"

    result = GarbageCollector(repo, make_config(), ec2=ec2).run(now_iso="2026-04-14T10:00:00Z")

    assert session["sessionId"] in result["sessions"]
    assert repo.get_session(session["sessionId"])["state"] == states.TERMINATED


def test_live_instance_defers_to_the_ec2_sweep():
    repo = make_repo()
    ec2 = FakeEC2()
    session = make_session(repo)
    instance_id = seed_instance(ec2, session["sessionId"], "2020-01-01T00:00:00Z")
    repo.update_session(
        session["sessionId"], state=states.READY, instanceId=instance_id
    )
    repo.sessions.items[session["sessionId"]]["expiresAt"] = "2020-01-01T00:00:00Z"

    result = GarbageCollector(repo, make_config(), ec2=ec2).run(now_iso="2026-04-14T10:00:00Z")

    assert session["sessionId"] not in result["sessions"]
    assert session["sessionId"] in [r["sessionId"] for r in result["instances"]]
