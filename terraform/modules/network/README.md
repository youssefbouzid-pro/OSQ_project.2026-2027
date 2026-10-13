# network module

VPC with three subnet tiers and **no NAT gateway** (the single biggest cost lever in this project).

## Layout

| Tier | Route | Used by |
| :--- | :--- | :--- |
| `public` (2 AZ) | `0.0.0.0/0 → IGW`, auto public IPs | lab EC2, Tailscale egress, ops host |
| `app` (2 AZ) | local only | backend Lambda (CloudWatch via 1 AZ VPC endpoint, provisioned separately) |
| `data` (2 AZ) | local only | Reserved for a future data tier; unused with the DynamoDB control plane (`docs/14`) |

Also hardens the VPC: default security group has **no rules**, DNS support/hostnames enabled.

## Usage

```hcl
module "network" {
  source      = "../../modules/network"
  project     = "osq"
  environment = "dev"
}
```

## Notes

- App/data subnets have no internet route. Anything inside them that must call an AWS API needs a VPC endpoint — the backend's only endpoint is CloudWatch Logs (1 AZ) because Lambda cannot log without it.
- Labs reach the internet through the IGW because they live in public subnets; their security group still denies all inbound from the internet (see `policies/opa/security/sg_ssh.rego`).
- Costs: `$0` for routing itself. NAT gateway deliberately omitted (~$35/mo).

## Definition of Done

- [x] `terraform fmt` passes
- [x] `terraform validate` passes
- [x] `terraform test` passes (needs AWS credentials)
- [ ] Applied to account A and verified idempotent (second `plan` empty)
