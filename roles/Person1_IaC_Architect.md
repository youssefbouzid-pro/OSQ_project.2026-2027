# 01_Person1_IaC_Architect.md

> **Scope note:** This charter's generic 8-week sequence is superseded by
> [`diagrams/07-delivery-roadmap.md`](../diagrams/07-delivery-roadmap.md), which sequences the work for the
> osq Lab Platform. The governance deliverables below (modules, state, tests, docs) are this
> role's contribution to that platform; module names in the roadmap take precedence where they differ.

## Purpose

Person 1 is the **IaC Architect**.  
This person is responsible for building the AWS Terraform modules and managing Terraform state safely.

The goal is not to create as many modules as possible.  
The goal is to create **6 clean, reusable, well-documented AWS modules** and a secure state backend.

---

## Project Scope for Person 1

### In Scope

Person 1 should deliver:

1. Six AWS Terraform modules for the osq platform:
   - `network` — VPC, public/app/data subnets, IGW, route tables, hardened security groups
   - `frontend` — S3 static site, CloudFront, optional Route 53
   - `api` — API Gateway, Lambda functions, IAM roles (token auth, **no Cognito**; see `docs/16`)
   - `data` — DynamoDB tables, SSM Parameter Store parameters, KMS keys (**no RDS**; see `docs/14`)
   - `lab` — launch templates, approved AMIs resolved from SSM, lab security group, TTL/instance tags (**no ASG**; Boto3 runs instances at runtime, see `docs/15`)
   - `governance` — CloudTrail, AWS Config recorder and rules, SNS alerting

2. Remote Terraform state:
   - S3 bucket for state storage
   - DynamoDB table for state locking
   - KMS encryption recommended

3. Environment structure:
   - `dev` (the PoC ships a single environment; see `docs/18`)

4. Basic Terraform testing:
   - Module validation
   - Simple integration tests using `go-terratest`

5. Documentation:
   - Module README files
   - State management explanation
   - Setup instructions

---

## Out of Scope

Person 1 should **not**:

- Build GCP modules
- Create 10 or more modules
- Build a custom state backend from scratch
- Build a custom Terraform engine
- Try to support every AWS service

---

## 8-Week Plan

### Week 1: Setup and Design

- Create repository folder structure
- Decide module naming rules
- Create S3 backend design
- Create DynamoDB lock table design

Example folder structure:

```text
terraform/
 ├── modules/
 │   ├── network/
 │   ├── frontend/
 │   ├── api/
 │   ├── data/
 │   ├── lab/
 │   └── governance/
 ├── environments/
 │   └── dev/
 └── backend.tf
```

---

### Week 2: Build First Modules

Build the first two modules:

- S3 module
- IAM module

Why these first?

- They are simpler than networking or databases.
- They are useful for testing policies.
- They help the policy team test OPA rules early.

---

### Week 3: Build VPC and EC2 Modules

Build:

- VPC module
- EC2 module

The VPC module should include:

- VPC
- Public subnets
- Private subnets
- Internet gateway
- Route tables

The EC2 module should include:

- EC2 instance
- Security group
- Basic tagging

---

### Week 4: Build Data Module and Test

Build:

- `data` module

The `data` module should include:

- DynamoDB `users`, `labs`, `sessions`, and `activity` tables (`docs/16`)
- SSM parameters for approved AMIs (`/cloudybt/ami/linux`, `/dba`, `/devops`)
- KMS key for secrets and encryption

Start writing simple tests.

---

### Week 5: State Backend Finalization

Ensure the backend has:

- State locking
- Encryption
- Versioning
- Proper IAM permissions

Example backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket         = "example-project-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "example-project-tf-lock"
    encrypt        = true
  }
}
```

---

### Week 6: Improve Modules

Add:

- Variable validation
- Output values
- Tags
- Default values where safe
- README examples

Example variable validation:

```hcl
variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}
```

---

### Week 7: Fix Issues and Polish

Person 1 should:

- Fix bugs found by CI/CD
- Fix problems found by OPA policies
- Improve module documentation
- Make sure `terraform plan` works cleanly

---

### Week 8: Final Demo Preparation

Person 1 should be ready to show:

- Terraform module structure
- Remote state setup
- A clean `terraform plan`
- One deployed example environment

---

## Simple Example: S3 Module

Example file structure:

```text
terraform/modules/s3/
 ├── main.tf
 ├── variables.tf
 ├── outputs.tf
 └── README.md
```

Simple example inside `main.tf`:

```hcl
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

This is a simple example. The final module should include more settings, such as:

- Versioning
- Encryption
- Logging
- Lifecycle rules
- Tags

---

## Definition of Done

Person 1 is complete when:

- [ ] Six AWS modules exist
- [ ] Each module has `main.tf`, `variables.tf`, `outputs.tf`, and `README.md`
- [ ] Remote state uses S3 and DynamoDB
- [ ] State locking works
- [ ] State encryption is enabled
- [ ] `terraform fmt` passes
- [ ] `terraform validate` passes
- [ ] `terraform plan` works for dev
- [ ] Basic tests exist
- [ ] Documentation explains how to use each module

---

## Common Mistakes to Avoid

1. Making modules too large
2. Hardcoding environment names
3. Forgetting state locking
4. Using default security groups
5. Not documenting module inputs and outputs
6. Creating resources without tags
7. Trying to finish too many modules at once

---

## Questions Person 1 Should Answer

- What is the naming convention for modules?
- How are environments separated?
- How is Terraform state protected?
- What happens if two people run `terraform apply` at the same time?
- How can another team member reuse a module?

---

## Suggested Citations

Amazon Web Services. (2023). *AWS Well-Architected Framework*. https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html

HashiCorp. (2023). *Terraform backend configuration*. https://developer.hashicorp.com/terraform/language/settings/backends
