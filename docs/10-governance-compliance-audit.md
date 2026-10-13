# Governance, Compliance, and Audit

This document is internal. It should not be shown in the learner UI.

## Governance Goal

osq should provision labs only from approved, controlled infrastructure.

Learners should never manage cloud resources directly.

## Governance Model

### Terraform

Terraform owns the baseline infrastructure:

- VPC
- Subnets
- Security groups
- IAM roles
- Launch templates
- AMI parameters
- Lambda functions
- API Gateway
- DynamoDB tables
- EventBridge rules
- CloudTrail
- AWS Config
- CloudWatch log groups
- SNS topics

### Boto3 SDK

Boto3 owns runtime actions:

- Launch lab instances
- Terminate lab instances
- Describe instance state
- Clean up session secrets
- Update session records

### OPA / Conftest

OPA checks Terraform plans before deployment.

Recommended policy categories:

- Security
- Tagging
- Cost
- TTL
- Networking
- Lab governance

## Policy Catalog

This table is the **single canonical policy catalog** for the project. The
pipeline diagram in [../diagrams/04-cicd-governance-pipeline.md](../diagrams/04-cicd-governance-pipeline.md)
and [../policies/README.md](../policies/README.md) both reference these IDs.
Rego messages must open with the ID shown here.

| Policy ID | Rule | Status |
|---|---|---|
| LAB-001 | Labs must use approved AMIs | Planned |
| LAB-002 | Labs must use approved instance types | Implemented |
| LAB-003 | Labs must use launch templates | Planned |
| LAB-004 | Lab instances must carry a SessionId tag | Planned |
| LAB-005 | Lab instances must carry an ExpiresAt tag | Planned |
| SEC-001 | No security group may expose SSH to the internet | Implemented |
| SEC-002 | EBS encryption required | Planned |
| SEC-003 | IMDSv2 required on lab instances | Planned |
| SEC-004 | The frontend S3 bucket must not be publicly writable | Planned |
| TTL-001 | TTL must not exceed 60 minutes | Planned |
| COST-001 | Active lab count must be limited | Planned |
| COST-002 | Monthly spend must stay under the budget threshold | Planned |
| NET-001 | Learner access must use Tailscale, never public SSH | Planned |
| GOV-001 | CloudTrail must remain enabled | Implemented (`policies/opa/governance/`) |
| GOV-002 | State and secrets must use customer-managed KMS keys | Planned |

Implemented policies live in [../policies/opa/](../policies/README.md) with
Rego unit tests and plan fixtures. To add a policy, follow the process at the
bottom of that file and update the Status column here in the same commit.

## Compliance Controls

| Control | Mechanism |
|---|---|
| Authentication | Token auth for PoC, OIDC/Cognito for production |
| Authorization | Role-based access control |
| Session isolation | Session ownership checks |
| Lab isolation | Ephemeral EC2 and Tailscale-only access |
| Expiration | TTL garbage collector |
| Auditability | Activity events and CloudTrail |
| Cost control | TTL, quotas, budgets |
| Drift detection | AWS Config and Terraform plan checks |

## Audit Evidence

The platform should be able to answer:

- Who started a lab?
- Which lab was started?
- When did the lab become ready?
- Which flags were submitted?
- When did the lab expire?
- Who ended the lab?
- Did the lab exceed TTL?
- Was the lab terminated automatically?

## AWS Audit Services

| Service | Purpose |
|---|---|
| CloudTrail | API activity audit |
| AWS Config | Configuration and drift checks |
| CloudWatch Logs | Runtime logs |
| Athena | Optional CloudTrail querying |
| SNS | Alerts |

## Production Recommendations

For production:

- Replace token auth with OIDC/SSO.
- Persist and protect audit logs.
- Add per-user dynamic Tailscale ACLs.
- Add formal compliance mapping.
- Add centralized monitoring and alerting.
- Add immutable log storage.
