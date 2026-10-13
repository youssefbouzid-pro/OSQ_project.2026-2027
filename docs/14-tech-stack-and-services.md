# Technology Stack and AWS Services

This document defines the final PoC technology choices.

## Summary

| Layer | Technology | Purpose |
|---|---|---|
| Frontend hosting | S3 | Static website storage |
| Frontend CDN | CloudFront | HTTPS and caching |
| DNS | Route 53 | Optional custom domain |
| Frontend code | HTML/CSS/JavaScript | Learner UI |
| API | API Gateway | REST endpoints |
| Backend logic | Lambda | Session and lab orchestration |
| Session database | DynamoDB | Low-cost session/event store |
| Lab compute | EC2 | Ephemeral learner labs |
| Lab image | AMI | Pre-baked lab environment |
| Launch config | Launch Template | Approved instance settings |
| Image build | EC2 Image Builder or Packer | AMI automation |
| Runtime provisioning | Boto3 | Dynamic EC2 launch/terminate |
| Scheduler | EventBridge Scheduler | TTL garbage collection |
| Secrets | SSM Parameter Store | AMI IDs, Tailscale keys, config |
| Encryption | KMS | Secret and EBS encryption |
| Access | Tailscale | Private SSH mesh |
| IaC | Terraform | Governed baseline infrastructure |
| Policy | OPA / Conftest | Policy-as-code checks |
| CI/CD | GitHub Actions | Validate, test, deploy |
| Audit | CloudTrail | AWS API audit log |
| Drift/config | AWS Config | Configuration compliance |
| Logs | CloudWatch Logs | Runtime logs |
| Alerts | SNS | Notifications |
| Queries | Athena | Optional CloudTrail analysis |
| Cost control | AWS Budgets | Cost alerts |

## Frontend Stack

Recommended:

- Static HTML/CSS/JavaScript
- No frontend framework required for PoC
- Hosted on S3
- Served through CloudFront

Reason:

- Very low cost
- Simple deployment
- Fast loading
- No always-on frontend server

## Backend Stack

Recommended:

- API Gateway HTTP API
- Python Lambda functions
- Boto3 AWS SDK
- DynamoDB session store

Reason:

- Free-tier friendly
- No idle server cost
- Easy integration with AWS services
- Simple scaling for PoC

### Runtime provisioning

`ec2:RunInstances` is granted only for the approved instance types,
using an `ec2:InstanceType` condition on `t4g.micro`, `t4g.small` and
`t4g.medium`. The IAM layer and the OPA layer (LAB-002) reject an
oversized instance independently, so neither one has to be trusted
alone.

## Lab Stack

Recommended:

- Ephemeral EC2 instances
- Graviton instance types: t4g.micro or t4g.small
- Pre-baked AMIs
- Launch templates
- DeleteOnTermination EBS volumes

Reason:

- Realistic Linux labs
- Low cost with per-second billing
- Clean environment per session
- Easy destruction after TTL

## Access Stack

Recommended:

- Tailscale for private mesh access
- Tailscale SSH for lab connection
- No public SSH exposure

Fallback:

- SSM Session Manager if Tailscale user limit or cost is an issue

## Governance Stack

Recommended:

- Terraform for baseline infrastructure
- OPA/Conftest for policy checks
- GitHub Actions for CI/CD
- Checkov or tflint for optional scanning
- Infracost for optional cost estimation

## Observability Stack

Recommended:

- CloudTrail for API audit
- CloudWatch Logs for Lambda logs
- CloudWatch Metrics/Alarms for operational health
- AWS Config for drift and compliance
- SNS for alerts
- Athena for optional forensic queries

## Database Choice

Preferred PoC database:

- DynamoDB

Why DynamoDB:

- Free-tier friendly
- No server management
- Works naturally with Lambda
- Good for session records and events

PostgreSQL is acceptable if:

- The team already has a PostgreSQL-based mock/backend
- The project wants to demonstrate database administration
- Cost remains controlled

If PostgreSQL is used, prefer:

- Small instance
- Automatic backups
- Encryption
- Private access
