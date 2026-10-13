# 03_Person3_CICD_Lead.md

> **Scope note:** This charter's generic 8-week sequence is superseded by
> [`diagrams/07-delivery-roadmap.md`](../diagrams/07-delivery-roadmap.md), which sequences the work for the
> osq Lab Platform. Pipeline design, including GitHub OIDC authentication and secrets handling,
> is specified in [`diagrams/04-cicd-governance-pipeline.md`](../diagrams/04-cicd-governance-pipeline.md).

## Purpose

Person 3 is the **CI/CD Lead**.  
This person is responsible for building the automation pipeline that checks, tests, and deploys Terraform code safely.

The goal is to create a pipeline where unsafe or non-compliant code cannot be deployed easily.

---

## Project Scope for Person 3

### In Scope

Person 3 should deliver:

1. GitHub Actions workflows
2. Terraform validation
3. OPA policy checking
4. Security scanning
5. Deployment approval process
6. Simple automation commands
7. Pipeline documentation

---

## Out of Scope

Person 3 should **not**:

- Build a 1000-line custom CLI
- Create a custom deployment platform
- Support GCP
- Build a custom policy engine
- Try to implement blue-green deployment unless the team is ahead of schedule

---

## 8-Week Plan

### Week 1: Repository Setup

Person 3 should help create:

- GitHub repository
- Branch protection rules
- Pull request template
- Basic folder structure
- Initial workflow files

Example folder:

```text
.github/
 └── workflows/
     ├── terraform-validate.yml
     ├── policy-check.yml
     └── deploy.yml
```

---

### Week 2: Basic Validation Pipeline

Create a workflow that runs:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

This catches basic syntax errors.

---

### Week 3: Add Policy Check

Add OPA or `conftest` to the pipeline.

The pipeline should fail if a policy violation is found.

Example command:

```bash
conftest test tfplan.json --policy policies/opa
```

---

### Week 4: Add Security Scanning

Add at least one security scanning tool.

Recommended tools:

- Checkov
- TruffleHog
- tfsec

Example purpose:

| Tool | Purpose |
|---|---|
| Checkov | Scans Terraform for misconfigurations |
| TruffleHog | Detects hardcoded secrets |
| tfsec | Static analysis for Terraform |

---

### Week 5: Add Terraform Plan

The pipeline should generate a Terraform plan.

Example commands:

```bash
terraform init
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
```

The JSON plan can then be checked by OPA.

---

### Week 6: Add Approval Gate

Production deployment should require approval.

Recommended flow:

```text
Pull Request
   ↓
Validation
   ↓
Policy Check
   ↓
Security Scan
   ↓
Terraform Plan
   ↓
Manual Approval
   ↓
Terraform Apply
```

---

### Week 7: Add Simple Automation Wrapper

Person 3 should create a simple `Makefile` or script wrapper.

The goal is to make common commands easy.

Example commands:

```bash
make lint
make test
make plan-dev
make policy-check
```

Important: In a real `Makefile`, commands must begin with a tab character.

Example `Makefile` structure:

```make
.PHONY: lint validate policy-check

lint:
	terraform fmt -check -recursive

validate:
	terraform validate

policy-check:
	conftest test tfplan.json --policy policies/opa
```

---

### Week 8: Final Demo Preparation

Person 3 should be ready to show:

- A failed pipeline because of a policy violation
- A successful pipeline after fixing the issue
- A Terraform plan output
- Security scan results
- Deployment approval process

---

## Simple GitHub Actions Example

```yaml
name: Terraform Validate

on:
  pull_request:
    branches:
      - main

jobs:
  validate:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform format check
        run: terraform fmt -check -recursive

      - name: Terraform init
        run: terraform init -backend=false

      - name: Terraform validate
        run: terraform validate
```

---

## Recommended Pipeline Stages

| Stage | Purpose | Example Tool |
|---|---|---|
| Format check | Ensure code style | `terraform fmt` |
| Validate | Catch syntax errors | `terraform validate` |
| Policy check | Block unsafe infrastructure | OPA / Conftest |
| Security scan | Find misconfigurations and secrets | Checkov / TruffleHog |
| Plan | Preview infrastructure changes | `terraform plan` |
| Approve | Human review before production | GitHub Environments |
| Apply | Deploy approved changes | `terraform apply` |

---

## Definition of Done

Person 3 is complete when:

- [ ] GitHub Actions workflow exists
- [ ] Terraform format check runs
- [ ] Terraform validate runs
- [ ] OPA policy check runs
- [ ] Security scan runs
- [ ] Terraform plan is generated
- [ ] Production deployment requires approval
- [ ] Pipeline documentation exists
- [ ] Simple Makefile or automation script exists
- [ ] Pipeline can demonstrate a blocked deployment

---

## Common Mistakes to Avoid

1. Allowing direct apply to production
2. Running pipeline checks only on push, not on pull request
3. Ignoring security scan results
4. Making the pipeline too complicated too early
5. Not coordinating with Person 2 about OPA commands
6. Storing secrets in GitHub repository files
7. Building a large custom CLI instead of finishing the pipeline

---

## Questions Person 3 Should Answer

- What checks must pass before merge?
- Who approves production deployments?
- Where are pipeline logs stored?
- What happens if a security scan fails?
- How can a developer reproduce the pipeline locally?

---

## Suggested Citations

GitHub. (2023). *GitHub Actions documentation*. https://docs.github.com/en/actions

HashiCorp. (2023). *Terraform CLI documentation*. https://developer.hashicorp.com/terraform/cli
