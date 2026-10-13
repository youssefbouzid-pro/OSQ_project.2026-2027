"""EC2 lifecycle helpers shared by the lab orchestrator and the TTL GC.

Everything here follows ``docs/15-ephemeral-provisioning.md``: required
tags, IMDSv2, encrypted root volume with DeleteOnTermination, no public
SSH, and instance types restricted to the approved list.
"""

import base64
import textwrap

from . import states
from .activity import iso, utc_now

MANAGED_BY = "lab-manager"
AUTO_DESTROY = "true"

#: Instance types allowed by docs/12 / policy LAB-002. Kept in sync with
#: ``policies/opa/cost/large_instance.rego``.
APPROVED_INSTANCE_TYPES = ("t4g.micro", "t4g.small", "t4g.medium")


class ProvisioningError(RuntimeError):
    """Raised when EC2 refuses to launch, or an input is not allowed."""


def build_tags(config, session, lab=None):
    """The mandatory tag set from docs/15."""
    lab = lab or {}
    tags = [
        {"Key": "Project", "Value": config.project_tag},
        {"Key": "ManagedBy", "Value": MANAGED_BY},
        {"Key": "LabId", "Value": str(session.get("labId", ""))},
        {"Key": "SessionId", "Value": str(session.get("sessionId", ""))},
        {"Key": "UserId", "Value": str(session.get("userId", ""))},
        {"Key": "CreatedAt", "Value": str(session.get("createdAt") or iso())},
        {"Key": "ExpiresAt", "Value": str(session.get("expiresAt") or "")},
        {"Key": "TTLMinutes", "Value": str(lab.get("ttlMinutes") or config.ttl_minutes)},
        {"Key": "AutoDestroy", "Value": AUTO_DESTROY},
    ]
    if lab.get("family"):
        tags.append({"Key": "LabFamily", "Value": str(lab["family"])})
    return tags


def assert_approved_instance_type(instance_type):
    if instance_type not in APPROVED_INSTANCE_TYPES:
        raise ProvisioningError(
            "Instance type '{}' is not in the approved list {}.".format(
                instance_type, ", ".join(APPROVED_INSTANCE_TYPES)
            )
        )


def build_user_data(config, session, lab):
    """Bootstrap script injected at launch.

    Contains only session-specific data. Two hard rules:

    * ``expectedFlag`` is never written here. The learner has root on the
      instance, so any answer key in user-data would be readable.
    * The Tailscale auth key is **referenced by SSM parameter name**, not
      value. The instance reads it at boot through its instance profile.
    """
    lab = lab or {}
    # Inject the task instructions, never the answers: the learner has
    # root on this box, so anything written here is readable.
    tasks = [
        {k: v for k, v in t.items() if k != "expectedFlag"}
        for t in (lab.get("tasks") or [])
        if isinstance(t, dict)
    ]

    script = textwrap.dedent(
        """\
        #!/bin/bash
        set -euo pipefail

        exec > >(tee -a /var/log/osq-bootstrap.log | logger -t osq -s 2>/dev/console) 2>&1

        mkdir -p /etc/osq /var/log

        cat > /etc/osq/session.json <<'SESSION'
        {{
          "sessionId": "{session_id}",
          "labId": "{lab_id}",
          "userId": "{user_id}",
          "expiresAt": "{expires_at}"
        }}
        SESSION

        cat > /etc/osq/tasks.json <<'TASKS'
        {tasks}
        TASKS

        echo "{hostname}" > /etc/hostname
        hostnamectl set-hostname "{hostname}" || true

        TAILSCALE_PARAM="{tailscale_param}"
        if [ -n "$TAILSCALE_PARAM" ]; then
          TOKEN=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token \\
            -H "X-aws-ec2-metadata-token-ttl-seconds: 300" || true)
          if [ -n "${{TOKEN:-}}" ]; then
            AUTH_KEY=$(aws ssm get-parameter --region "{region}" \\
              --name "$TAILSCALE_PARAM" --with-decryption \\
              --query Parameter.Value --output text || true)
            if [ -n "${{AUTH_KEY:-}}" ]; then
              tailscale up --auth-key="$AUTH_KEY" --hostname="{hostname}" || true
            fi
          fi
        fi

        touch /etc/osq/bootstrap.done
        """
    )

    import json

    return script.format(
        session_id=session.get("sessionId", ""),
        lab_id=session.get("labId", ""),
        user_id=session.get("userId", ""),
        expires_at=session.get("expiresAt", ""),
        tasks=json.dumps(tasks, indent=2),
        hostname=hostname_for(session, lab),
        tailscale_param=config.tailscale_auth_key_parameter or "",
        region=config.region,
    )


def hostname_for(session, lab=None):
    lab = lab or {}
    family = lab.get("family") or lab.get("labId") or "lab"
    suffix = str(session.get("sessionId", "")).split("-")[-1] or "0000"
    return "{}-{}".format(family, suffix)


def encode_user_data(script):
    return base64.b64encode(script.encode("utf-8")).decode("ascii")


def launch_instance(ec2, config, session, lab, ami_id):
    """Launch one lab instance from the approved launch template."""
    lab = lab or {}
    instance_type = lab.get("instanceType") or "t4g.micro"
    assert_approved_instance_type(instance_type)

    tags = build_tags(config, session, lab)
    params = {
        "ImageId": ami_id,
        "InstanceType": instance_type,
        "MinCount": 1,
        "MaxCount": 1,
        "UserData": encode_user_data(build_user_data(config, session, lab)),
        # IMDSv2 is required (docs/15 security controls).
        "MetadataOptions": {"HttpTokens": "required", "HttpEndpoint": "enabled"},
        "TagSpecifications": [
            {"ResourceType": "instance", "Tags": tags},
            {"ResourceType": "volume", "Tags": tags},
        ],
        "BlockDeviceMappings": [
            {
                "DeviceName": "/dev/xvda",
                "Ebs": {
                    "DeleteOnTermination": True,
                    "Encrypted": True,
                    "VolumeType": "gp3",
                },
            }
        ],
    }

    if config.launch_template_name:
        params["LaunchTemplate"] = {
            "Name": config.launch_template_name,
            "Version": "$Latest",
        }
    if config.lab_security_group_id:
        params["SecurityGroupIds"] = [config.lab_security_group_id]
    if config.lab_subnet_id:
        params["SubnetId"] = config.lab_subnet_id
    if config.lab_instance_profile:
        params["IamInstanceProfile"] = {"Name": config.lab_instance_profile}

    response = ec2.run_instances(**params)
    instances = response.get("Instances") or []
    if not instances:
        raise ProvisioningError("EC2 returned no instance.")
    return instances[0]["InstanceId"]


def describe_instances(ec2, instance_ids):
    if not instance_ids:
        return []
    paginator = ec2.get_paginator("describe_instances")
    found = []
    for page in paginator.paginate(InstanceIds=instance_ids):
        for reservation in page.get("Reservations") or []:
            found.extend(reservation.get("Instances") or [])
    return found


def find_lab_instances(ec2):
    """Every instance the lab manager owns (docs/15 GC responsibility #1)."""
    paginator = ec2.get_paginator("describe_instances")
    filters = [
        {"Name": "tag:ManagedBy", "Values": [MANAGED_BY]},
        {"Name": "instance-state-name", "Values": ["pending", "running", "stopping", "stopped"]},
    ]
    found = []
    for page in paginator.paginate(Filters=filters):
        for reservation in page.get("Reservations") or []:
            found.extend(reservation.get("Instances") or [])
    return found


def instance_state(instance):
    return (instance.get("State") or {}).get("Name", "")


def instance_session_id(instance):
    for tag in instance.get("Tags") or []:
        if tag.get("Key") == "SessionId":
            return tag.get("Value")
    return None


def instance_expires_at(instance):
    for tag in instance.get("Tags") or []:
        if tag.get("Key") == "ExpiresAt":
            return tag.get("Value")
    return None


def terminate_instance(ec2, instance_id):
    ec2.terminate_instances(InstanceIds=[instance_id])


def session_is_expired(session, now_iso):
    expires_at = session.get("expiresAt") or ""
    return bool(expires_at) and expires_at <= now_iso


def ready_timeout_reached(session, now_iso=None):
    """True when a session has sat in a non-READY state past the timeout."""
    now = now_iso or iso(utc_now())
    created = session.get("createdAt") or ""
    return bool(created) and created < now and states.is_active(session.get("state"))
