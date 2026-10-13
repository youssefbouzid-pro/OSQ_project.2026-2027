# Policy library (OPA / Rego)

Policies evaluated against `terraform show -json` plan output by `conftest`, both locally (`make test-policies`) and in CI.

## Layout

```text
policies/
 ├── opa/
 │   ├── security/       SEC-* rules
 │   ├── cost/           LAB-002 instance-type rule
 │   ├── governance/     GOV-* rules
 │   ├── tagging/        TAG-* rules   (planned)
 │   └── compliance/     CIS-mapped rules (planned)
 └── tests/
     └── fixtures/       hand-maintained plan JSON, one per expected outcome
```

All policies live in `package main` (conftest's default namespace) and use `import rego.v1`.

## Current policies

Policy IDs are owned by the canonical catalog in
[`docs/10-governance-compliance-audit.md`](../docs/10-governance-compliance-audit.md).
Rego messages must open with the ID from that table.

| ID | File | Rule | Status |
| :--- | :--- | :--- | :--- |
| `SEC-001` | `opa/security/sg_ssh.rego` | No security group may allow 22/tcp from `0.0.0.0/0` or `::/0`. The remediation range is `100.64.0.0/10` (Tailscale). | Implemented |
| `LAB-002` | `opa/cost/large_instance.rego` | Lab instances must use an approved instance type: `t4g.micro`, `t4g.small`, or `t4g.medium`. | Implemented |
| `GOV-001` | `opa/governance/trail_integrity.rego` | Every CloudTrail trail in the plan must have both `enable_logging` and `enable_log_file_validation` set to `true`. | Implemented |

`SEC-001` currently rejects only the fully open `0.0.0.0/0` and `::/0` cases.
Rejecting individual public CIDR ranges is not yet covered and is tracked as a
planned enhancement.

## Tests

Three layers, all free and offline:

```bash
make test-policies
```

1. **Rego unit tests** — `*_test.rego` files, run by `conftest verify`.
2. **Passing fixtures** — `plan_private_ssh.json` and `plan_trail_ok.json` must produce zero violations. These are the false-positive guards: a policy that denies them is wrong, not the fixture.
3. **Failing fixtures** — `plan_public_ssh.json`, `plan_oversized_instance.json` and `plan_trail_disabled.json` must be rejected; the Makefile fails if any is accepted.

## Adding a policy

1. Claim an ID from the catalog in [`docs/10-governance-compliance-audit.md`](../docs/10-governance-compliance-audit.md).
2. Create `opa/<category>/<id>.rego` with `deny contains msg`. The message must open with the policy ID and name the resource **and the fix**.
3. Add `opa/<category>/<id>_test.rego` with one deny and one allow case.
4. Add or update a fixture under `tests/fixtures/`.
5. Update the Status column in `docs/10-governance-compliance-audit.md` and the table above, in the same commit.
