# Official Project Scope

## Project Name

osq

## Project Type

Learner-facing AWS lab platform proof of concept.

## Core Product

osq allows learners to:

1. Sign in.
2. Browse labs.
3. Start a temporary lab environment.
4. Connect to the lab through Tailscale.
5. Complete guided tasks.
6. Submit flags as proof of completion.
7. Let the lab expire automatically after 60 minutes.

## PoC Boundary

This is not a production platform.

The PoC focuses on:

- AWS-only infrastructure
- Learner-facing lab experience
- Ephemeral EC2 lab provisioning
- TTL-based cost control
- Secure Tailscale access
- Terraform-governed baseline infrastructure
- SDK-based dynamic provisioning
- Basic audit and activity visibility

## Final Technology Direction

| Area | Decision |
|---|---|
| Cloud provider | AWS only |
| Frontend | Static S3 + CloudFront |
| Backend API | API Gateway + Lambda |
| Session store | DynamoDB recommended |
| Lab compute | Ephemeral EC2 |
| Lab images | Pre-baked AMIs |
| Provisioning | Boto3 SDK |
| Access | Tailscale SSH |
| TTL cleanup | EventBridge + Lambda |
| IaC | Terraform |
| Policy checks | OPA / Conftest |
| CI/CD | GitHub Actions |
| Audit | CloudTrail + CloudWatch + AWS Config |

## Out of Scope

The learner UI should not expose:

- Internal architecture docs
- OPA policy internals
- Terraform internals
- CloudTrail forensic dashboards
- Budget and cost governance
- Internal runbooks
- Threat model
- Delivery plan

These remain repository-level or admin-level documentation.
