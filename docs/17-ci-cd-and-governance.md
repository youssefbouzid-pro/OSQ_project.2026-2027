# CI/CD and Governance

## Goal

All infrastructure changes should pass through a governed pipeline before deployment.

Runtime lab provisioning should use approved infrastructure created by the pipeline.

## Pipeline Model

    Pull Request
      -> terraform fmt
      -> terraform validate
      -> tflint
      -> Rego unit tests and policy fixtures
      -> security scan (Checkov + TruffleHog)
      -> terraform plan
      -> conftest against the plan JSON
      -> approval
      -> terraform apply

Two policy stages exist on purpose:

- **Fixture stage** runs Rego unit tests plus the pass/fail plan fixtures. It
  needs no AWS credentials, so it runs on every pull request.
- **Plan stage** runs `conftest` against the real `terraform show -json` output.
  It requires the OIDC role and therefore runs in the plan job.

Scheduled:

    Drift Check (cron)
      -> terraform plan -detailed-exitcode
      -> AWS Config compliance status
      -> SNS alert on drift

## GitHub Actions Workflows

Workflows live in `.github/workflows/`.

| Workflow | Trigger | Purpose |
|---|---|---|
| `terraform-validate.yml` | pull request, push to main | fmt, init, validate, tflint |
| `policy-check.yml` | pull request, push to main | Rego unit tests, fixtures, PR comment on failure |
| `terraform-plan.yml` | pull request, push to main | gated `terraform plan`, conftest on plan JSON, artifact upload |
| `deploy-dev.yml` | manual, protected environment | `terraform apply` to dev, verify outputs, notify |
| `drift-check.yml` | daily schedule, manual | `plan -detailed-exitcode`, AWS Config status, alert |
| `security.yml` | pull request, push to main | Checkov IaC scan, TruffleHog secret scan |

### terraform-validate.yml

Runs on pull request:

- `terraform fmt -check -recursive`
- `terraform init -backend=false` + `terraform validate`
- `tflint --init` + `tflint --recursive`

### policy-check.yml

Runs on pull request:

- `conftest verify` against `policies/opa`
- Pass and fail fixtures under `policies/tests/fixtures`
- Comments the failures on the pull request

### terraform-plan.yml

Runs on pull request:

- Assumes the GitHub OIDC role
- `terraform plan -out=tfplan`
- `conftest test tfplan.json --policy policies/opa`
- Saves `tfplan.json` as an artifact

### deploy-dev.yml

Runs after approval:

- `terraform apply` to dev
- Verify outputs
- Notify success or failure

### drift-check.yml

Scheduled:

- `terraform plan -detailed-exitcode`
- AWS Config status check
- Alert on drift

## OPA Policy Categories

### Security

- No public SSH
- No public database
- Encryption required
- IMDSv2 required

### Tagging

- SessionId required
- UserId required
- ExpiresAt required
- ManagedBy required

### Cost

- Approved instance types only
- TTL max 60 minutes
- Active lab limit

### Lab Governance

- Approved AMI only
- Launch template required
- DeleteOnTermination required
- Tailscale-only access expected

## Tests

Recommended test layers:

### Terraform tests

- terraform validate
- terraform plan
- go-terratest optional for modules

### Policy tests

- Conftest pass cases
- Conftest fail cases

### API tests

- Auth validation
- Lab start validation
- Quota validation
- Flag submission validation
- `GET /labs/{labId}` response contains no `expectedFlag` field

### Frontend tests

- Manual smoke tests
- Optional Playwright/Cypress later

## Drift Detection

Recommended PoC drift detection:

- AWS Config rules
- CloudTrail alerts
- Scheduled terraform plan
- Orphaned instance scanner

Example drift scenarios:

| Scenario | Detection |
|---|---|
| Security group manually changed | AWS Config / CloudTrail |
| EC2 launched outside platform | Tag scanner |
| Lab missing ExpiresAt tag | Tag validator |
| S3 public access changed | AWS Config |
| Terraform state differs | terraform plan |

## Observability

Recommended metrics:

- Lambda errors
- Lab start success rate
- Lab failure rate
- TTL terminations
- Orphaned instances found
- Policy violations blocked
- Deployment success rate

Services:

- CloudWatch Metrics
- CloudWatch Logs
- CloudWatch Alarms
- SNS notifications
