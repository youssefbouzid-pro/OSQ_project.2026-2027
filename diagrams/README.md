# osq Diagrams

This folder contains the updated architecture and workflow diagrams for the osq Lab Platform.

The diagrams reflect the current PoC scope:

- AWS-only architecture
- 8-week academic project
- 5 users or fewer
- simple token-based authentication
- dynamic EC2 lab provisioning
- hard 60-minute lab TTL
- no TTL extension
- Tailscale SSH access
- no SSH private key distribution
- Terraform-governed baseline infrastructure
- SDK-based (Boto3) runtime provisioning
- OPA policy enforcement
- automated garbage collection

---

## Diagram Index

| File | Purpose |
|---|---|
| `01-high-level-architecture.md` | Overall platform architecture |
| `02-simple-auth-access-flow.md` | Simple token authentication and lab access flow |
| `03-dynamic-lab-provisioning-sequence.md` | Runtime provisioning of ephemeral EC2 labs |
| `04-cicd-governance-pipeline.md` | CI/CD pipeline with OPA policy gates |
| `05-lab-lifecycle-state-machine.md` | Lab session lifecycle states |
| `06-drift-remediation-workflow.md` | Drift, orphan detection, and remediation |
| `07-delivery-roadmap.md` | 8-week delivery plan and role ownership |

---


