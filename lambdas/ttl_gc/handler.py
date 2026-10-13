"""TTL garbage collector.

Runs every minute on EventBridge Scheduler (docs/15). Two independent
sweeps, because either can find something the other missed:

1. **EC2 sweep** (the documented primary path): every instance tagged
   ``ManagedBy=lab-manager`` whose ``ExpiresAt`` has passed is
   terminated, and its session is marked TERMINATED.
2. **Session sweep** (fallback): a session past its TTL whose instance
   is already gone is still closed out, so quota is released and the
   audit trail is complete.

Orphaned lab instances (owned by the lab manager but unknown to the
sessions table) are terminated so they cannot accumulate cost.
"""

import logging

from common import activity as events
from common import lab_ops
from common import states
from common.activity import iso, utc_now
from common.config import Config
from common.repository import Repository

LOG = logging.getLogger(__name__)
LOG.setLevel(logging.INFO)


class GarbageCollector:
    def __init__(self, repo, config, ec2=None):
        self.repo = repo
        self.config = config
        self._ec2 = ec2

    @property
    def ec2(self):
        if self._ec2 is None:
            import boto3

            self._ec2 = boto3.client("ec2", region_name=self.config.region)
        return self._ec2

    def run(self, now_iso=None):
        now = now_iso or iso(utc_now())
        terminated = {"instances": [], "sessions": [], "orphans": []}

        terminated["instances"] = self.sweep_instances(now)
        terminated["sessions"] = self.sweep_sessions(now)
        return terminated

    # -- sweep 1: EC2 ---------------------------------------------------

    def sweep_instances(self, now):
        reaped = []
        for instance in lab_ops.find_lab_instances(self.ec2):
            instance_id = instance.get("InstanceId")
            session_id = lab_ops.instance_session_id(instance)
            expires_at = lab_ops.instance_expires_at(instance)

            expired = bool(expires_at) and expires_at <= now
            if not expired:
                continue

            session = self.repo.get_session(session_id) if session_id else None
            if session is None:
                # Orphan: owned by us, unknown to the session store.
                LOG.warning("Terminating orphaned lab instance %s", instance_id)
                lab_ops.terminate_instance(self.ec2, instance_id)
                reaped.append({"instanceId": instance_id, "orphan": True})
                events.record(
                    self.repo,
                    events.LAB_TERMINATED_BY_TTL,
                    "Orphaned instance {} terminated".format(instance_id),
                    level=events.LEVEL_WARN,
                    session_id=session_id,
                )
                continue

            if not states.is_active(session.get("state")):
                continue

            LOG.info("Terminating expired instance %s", instance_id)
            lab_ops.terminate_instance(self.ec2, instance_id)
            self.repo.update_session(
                session["sessionId"],
                state=states.TERMINATED,
                endedAt=session.get("endedAt") or now,
                terminationReason="ttl",
            )
            events.record(
                self.repo,
                events.LAB_TERMINATED_BY_TTL,
                "{} terminated by TTL (instance {})".format(
                    session["sessionId"], instance_id
                ),
                level=events.LEVEL_WARN,
                session_id=session["sessionId"],
            )
            reaped.append({"instanceId": instance_id, "sessionId": session["sessionId"]})
        return reaped

    # -- sweep 2: sessions ---------------------------------------------

    def sweep_sessions(self, now):
        closed = []
        for session in self.repo.list_expired_sessions(now):
            instance_id = session.get("instanceId")
            if instance_id and self._instance_alive(instance_id):
                # Still up; the EC2 sweep owns it and will finish the job.
                continue
            self.repo.update_session(
                session["sessionId"],
                state=states.TERMINATED,
                endedAt=session.get("endedAt") or now,
                terminationReason="ttl",
            )
            events.record(
                self.repo,
                events.LAB_TERMINATED_BY_TTL,
                "{} closed out by GC (no live instance)".format(session["sessionId"]),
                level=events.LEVEL_WARN,
                session_id=session["sessionId"],
            )
            closed.append(session["sessionId"])
        return closed

    def _instance_alive(self, instance_id):
        try:
            response = self.ec2.describe_instances(InstanceIds=[instance_id])
        except Exception:  # noqa: BLE001 - treat lookup failure as "gone"
            return False
        for reservation in response.get("Reservations") or []:
            for instance in reservation.get("Instances") or []:
                if lab_ops.instance_state(instance) not in (
                    "terminated",
                    "shutting-down",
                ):
                    return True
        return False


def build_collector(repo=None, config=None, ec2=None):
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
    return GarbageCollector(repo=repo, config=config, ec2=ec2)


def lambda_handler(event, context):  # pragma: no cover - exercised in AWS
    return build_collector().run()
