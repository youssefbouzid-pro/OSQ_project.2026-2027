# CloudyBTTounsi Documentation

This folder contains the full documentation for the CloudyBTTounsi PoC.

CloudyBTTounsi is a learner-facing AWS lab platform. It provisions temporary lab environments, lets learners complete tasks, submit flags, and connect through Tailscale.

This project is a proof of concept, not a production SaaS platform.

## Final PoC Technology Choices

| Area | Final Choice |
|---|---|
| Frontend hosting | S3 + CloudFront |
| Frontend stack | Static HTML/CSS/JavaScript |
| API | API Gateway + Lambda |
| Session store | DynamoDB recommended, PostgreSQL acceptable |
| Lab runtime | Ephemeral EC2 instances |
| Lab images | Pre-baked AMIs |
| Provisioning SDK | Boto3, Python |
| Access | Tailscale SSH |
| TTL cleanup | EventBridge Scheduler + Lambda garbage collector |
| Secrets/config | SSM Parameter Store + KMS |
| IaC governance | Terraform |
| Policy checks | OPA / Conftest |
| CI/CD | GitHub Actions |
| Audit | CloudTrail + CloudWatch + AWS Config + Athena |

## Documentation Index

| File | Purpose |
|---|---|
| `PROJECT_SCOPE.md` | Official high-level PoC scope |
| `01-project-scope.md` | Detailed product scope |
| `02-user-roles-and-permissions.md` | Student, admin, auditor permissions |
| `03-lab-model-and-flags.md` | Lab catalog, tasks, flags |
| `04-session-lifecycle-and-ttl.md` | Session states and TTL rules |
| `05-platform-architecture.md` | Final technical architecture |
| `06-frontend-pages-and-features.md` | Learner-facing pages |
| `07-lab-content-and-flags.md` | Lab scenarios and flag injection |
| `08-access-setup-and-troubleshooting.md` | Tailscale access guide |
| `09-admin-activity-and-audit.md` | Admin and auditor activity model |
| `10-governance-compliance-audit.md` | Internal governance and audit controls |
| `11-security-threat-model.md` | Threats and mitigations |
| `12-cost-and-ttl-model.md` | TTL enforcement and cost controls |
| `13-delivery-and-demo.md` | Delivery plan and demo script |
| `14-tech-stack-and-services.md` | Full technology and AWS service map |
| `15-ephemeral-provisioning.md` | EC2 provisioning and garbage collection |
| `16-api-and-data-model.md` | API endpoints and data structures |
| `17-ci-cd-and-governance.md` | Pipeline, OPA, tests, drift detection |
| `18-deployment-guide.md` | Deployment and verification guide |

## Learner-Facing Content

Only these topics should appear directly in the learner UI:

- Getting Started
- Access Setup
- Help & FAQ
- Lab Catalog
- My Labs
- Lab Guides

## Internal Content

These docs are for the team, supervisor, admins, auditors, and graders:

- Architecture
- Tech stack
- Governance
- Compliance
- Threat model
- Cost model
- CI/CD
- Deployment guide
- Delivery plan
