# Detailed Project Scope

## Product Scope

osq is a learner-facing lab platform.

The user-facing frontend must focus on:

- Learning labs
- Lab catalog
- Difficulty levels
- Lab tasks
- Flags as proof of completion
- Lab session lifecycle
- Tailscale access
- Help and onboarding

The frontend should not present internal governance, architecture, compliance, or team project documentation to normal learners.

## Platform Goal

The platform allows a learner to:

1. Sign in.
2. Browse available labs.
3. Start a lab session.
4. Wait for the environment to become ready.
5. Connect to the lab using Tailscale.
6. Complete lab tasks.
7. Submit flags as proof of completion.
8. End the lab or wait for automatic expiration.

## PoC Technical Scope

The PoC uses:

- AWS only
- Serverless control plane
- Ephemeral EC2 labs
- Pre-baked AMIs
- Boto3 dynamic provisioning
- Tailscale-only access
- TTL garbage collection
- Terraform-governed baseline
- OPA policy checks
- GitHub Actions CI/CD

## Core Constraints

- Labs are temporary.
- Default TTL is 60 minutes.
- TTL cannot be extended.
- Expired labs are destroyed automatically.
- Learners do not manage AWS infrastructure directly.
- Learners do not see internal cost or governance dashboards unless they have admin or auditor permissions.

## Lab Families

- Linux Sysadmin
- Database Administration
- DevOps Pipeline

## Difficulty Levels

- Beginner
- Intermediate
- Advanced

## Session Model

Each session is isolated and ephemeral.

A session should include:

- Session ID
- User ID
- Lab ID
- State
- Created time
- Expiration time
- Instance ID
- Tailscale hostname
- Completed flags

## Cost Model

The PoC should remain low-cost by using:

- AWS free-tier services where possible
- Ephemeral EC2 labs
- Small Graviton instance types
- TTL enforcement
- DeleteOnTermination for EBS volumes
- No always-on lab instances

## Documentation Scope

Repository documentation may include internal technical documents.

Learner UI should only include:

- Getting Started
- Access Setup
- Help & FAQ
- Lab Catalog
- My Labs
- Lab Guides
