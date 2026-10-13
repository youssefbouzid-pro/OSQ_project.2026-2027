# Cost and TTL Model

This document is internal. Learners should not see cost data.

## TTL Model

- Default TTL: 60 minutes
- Maximum TTL: 60 minutes
- Extension: not allowed
- Expiration action: terminate instance
- Data retention: none by default

## Cost Strategy

The PoC should remain low-cost by using:

- Serverless control plane
- Ephemeral EC2 labs
- Small Graviton instances
- AWS free tiers
- DeleteOnTermination volumes
- TTL garbage collection
- Budget alerts

## Recommended Instance Types

| Lab Type | Recommended Instance |
|---|---|
| Linux Beginner | t4g.micro |
| Linux Intermediate | t4g.small |
| Linux Advanced | t4g.small |
| DBA Beginner | t4g.small |
| DBA Intermediate | t4g.small |
| DBA Advanced | t4g.medium |
| DevOps Beginner | t4g.small |
| DevOps Intermediate | t4g.small |
| DevOps Advanced | t4g.medium |

## Approximate Lab Cost

| Instance | Approx Hourly Cost | 60-Minute Lab Cost |
|---|---:|---:|
| t4g.micro | ~$0.0084 | ~$0.0084 |
| t4g.small | ~$0.0168 | ~$0.0168 |
| t4g.medium | ~$0.0336 | ~$0.0336 |

Actual pricing depends on region and account.

## Monthly Estimate

| Usage | Labs per Day | Approx EC2 Cost |
|---|---:|---:|
| Minimal demo | 2 | $1-$2/month |
| Team testing | 10 | $4-$6/month |
| Class demo | 30 | $10-$15/month |

Most control-plane services should remain within free-tier limits for PoC usage.

## Budget and Quota Parameters

These are the exact values the platform uses. The frontend constants in
`frontend/api.js` and the budget pill in `frontend/app.js` must match them.

| Parameter | Value | Purpose |
|---|---:|---|
| Monthly budget | $20 | Admin budget indicator ceiling |
| Max active labs per learner | 4 | Per-user quota |
| Max active labs platform-wide | 4 | Platform stop valve |
| Default TTL | 60 minutes | Fixed, no extension |

## Cost Guardrails

- Fixed TTL
- No extensions
- Instance type restrictions
- Active lab limit
- Per-user quota
- Automatic garbage collection
- DeleteOnTermination volumes
- Budget indicator for admins
- AWS Budgets alerts

## Budget Behavior

If estimated cost approaches budget:

- Admin sees warning in budget indicator.
- Platform may restrict new labs in future implementation.

## Cost Visibility

| Role | Sees Cost? |
|---|---:|
| Student | No |
| Admin | Yes |
| Auditor | No |

This matches the permission matrix in
[02-user-roles-and-permissions.md](02-user-roles-and-permissions.md) and the
budget rule in [09-admin-activity-and-audit.md](09-admin-activity-and-audit.md).

Learner UI should show time remaining, not money remaining.
