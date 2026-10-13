# Ephemeral Provisioning Model

## Principle

Labs are created only when requested and destroyed automatically after TTL.

The recommended model is:

    Ephemeral EC2 for realistic labs
    TTL garbage collector for cost control
    Pre-baked AMIs for fast startup
    Tailscale for secure access
    Terraform for governance
    Boto3 SDK for dynamic provisioning

## Provisioning Flow

1. Learner requests a lab.
2. API validates user role and quota.
3. Session is created with status REQUESTED.
4. Lab Orchestrator retrieves approved AMI and launch template.
5. Boto3 launches an EC2 instance.
6. Instance is tagged with session metadata.
7. Instance bootstrap enrolls into Tailscale.
8. Session becomes READY.
9. Learner connects through Tailscale SSH.
10. TTL expires.
11. Garbage collector terminates the instance.
12. Session becomes TERMINATED.

## Readiness

`READY` is set when both EC2 status checks pass. The orchestrator polls
`DescribeInstanceStatus` for up to `READY_TIMEOUT_SECONDS` (default 180)
and marks the session `FAILED` if the instance never becomes healthy.

Tailscale enrollment happens in the instance bootstrap and is verified by
the learner using the Access page. The orchestrator does not call the
Tailscale API.

## Recommended EC2 Settings

| Setting | Value |
|---|---|
| Instance type | t4g.micro or t4g.small |
| Purchasing model | On-Demand |
| Root volume deletion | DeleteOnTermination = true |
| EBS encryption | Enabled |
| Metadata access | IMDSv2 required |
| Public SSH | Disabled |
| Internet access | Outbound only for Tailscale/bootstrap |
| Lab tags | Required |

## Pre-Baked AMI Strategy

Each lab family should have an AMI.

Recommended SSM parameters:

    /cloudybt/ami/linux
    /cloudybt/ami/dba
    /cloudybt/ami/devops

The AMI should include:

- Base Linux OS
- Tailscale agent
- CloudWatch agent or logging setup
- Lab tools
- PostgreSQL for DBA labs
- Docker for DevOps labs
- Bootstrap scripts
- Security hardening

User-data should only inject session-specific data:

- Session ID
- Lab ID
- Hostname
- TTL expiration timestamp
- Tailscale auth key reference
- Lab flags
- Task scenario files

## Required Tags

Every lab instance must have:

    Project       = cloudybt-tounsi
    ManagedBy     = lab-manager
    LabId         = linux-beginner
    SessionId     = lab-12345
    UserId        = student-01
    CreatedAt     = 2026-04-14T10:00:00Z
    ExpiresAt     = 2026-04-14T11:00:00Z
    TTLMinutes    = 60
    AutoDestroy   = true

These tags are used for:

- TTL cleanup
- Cost tracking
- Audit
- Orphan detection
- Session matching

## TTL Enforcement Layers

### Session store

The session record contains expires_at.

### EC2 tag

The instance contains ExpiresAt.

### EventBridge garbage collector

A scheduled Lambda runs every minute and terminates expired instances.

### Tailscale key expiry

Tailscale auth keys should be short-lived.

Recommended:

    Tailscale auth key TTL = 60 minutes

### Budget guardrails

AWS Budgets should alert at low thresholds.

## Garbage Collector Responsibilities

The garbage collector should:

- Find instances tagged ManagedBy = lab-manager
- Check ExpiresAt
- Terminate expired instances
- Terminate orphaned instances
- Update session status
- Delete temporary SSM secrets
- Remove Tailscale device if API access exists
- Write audit event

## Security Controls

- No public SSH
- IMDSv2 required
- Encrypted EBS
- Least-privilege IAM roles
- Short-lived Tailscale auth keys
- No long-lived secrets in AMIs
- No secrets in Git
- No secrets in CloudWatch logs

## Cost Controls

- Use t4g.micro or t4g.small
- Use On-Demand instances for predictable learner UX
- Destroy labs after 60 minutes
- Delete volumes on termination
- Limit active labs per user
- Limit active labs across platform
- Use AWS Budgets alerts
