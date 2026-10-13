# 02_Person2_Policy_Engineer.md

> **Scope note:** This charter's generic 8-week sequence is superseded by
> [`diagrams/07-delivery-roadmap.md`](../diagrams/07-delivery-roadmap.md), which sequences the work for the
> CloudyBTTounsi Lab Platform. Use the policy catalog in
> [`docs/10-governance-compliance-audit.md`](../docs/10-governance-compliance-audit.md) as the
> architecture-specific starting set, and the generic examples below as the pattern.

## Purpose

Person 2 is the **Policy Engineer**.  
This person is responsible for writing OPA policies that block unsafe or non-compliant infrastructure.

The goal is not to write 50 policies quickly.  
The goal is to write **20 to 25 clear, tested, useful policies** that protect the AWS environment.

---

## Project Scope for Person 2

### In Scope

Person 2 should deliver:

1. OPA policies for Terraform plans
2. Policy categories:
   - Security
   - Compliance
   - Cost
   - Tagging
3. CIS AWS Foundations Benchmark mapping
4. Policy tests
5. Policy documentation

Recommended number of policies:

| Category | Minimum |
|---|---:|
| Security | 10 |
| Compliance | 5 |
| Cost | 5 |
| Tagging | 5 |
| Total | 25 |

---

## Out of Scope

Person 2 should **not**:

- Build a custom policy engine from scratch
- Write policies for GCP
- Try to cover every CIS rule
- Create policies that are too broad and cause many false failures
- Copy policies from the internet without understanding them

---

## 8-Week Plan

### Week 1: Learn OPA and Terraform Plan Input

Person 2 should understand:

- What a Terraform plan JSON file looks like
- How OPA reads JSON input
- How deny rules work
- How `conftest` runs policies

Example command:

```bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
conftest test tfplan.json --policy policies/opa
```

---

### Week 2: Write First Security Policies

Start with high-risk AWS mistakes.

Examples:

- S3 bucket is public
- Security group allows SSH from `0.0.0.0/0`
- DynamoDB table is not encrypted with a customer-managed KMS key
- IAM policy allows `*` actions
- Resources are missing required tags

---

### Week 3: Write Compliance Policies

Map policies to CIS AWS Foundations Benchmark.

Examples:

- S3 buckets must block public access
- DynamoDB tables must use customer-managed KMS encryption
- CloudTrail must be enabled
- Password policy must require strong passwords
- Root account must not have access keys

---

### Week 4: Write Cost Policies

Examples:

- EC2 instance type must not be too large
- EC2 instance type must be within the approved list (LAB-002)
- Resources must include cost center tag
- Lab instances must launch from an approved launch template (LAB-003)
- Unused EBS volumes should be flagged

---

### Week 5: Write Tagging Policies

Examples:

- All resources must have `Environment`
- All resources must have `Project`
- All resources must have `Owner`
- Environment must be `dev`
- Tags must be lowercase

---

### Week 6: Test Policies

For every policy, create:

- One passing example
- One failing example

Example test table:

| Policy ID | Pass Example | Fail Example |
|---|---|---|
| SEC-001 | SSH limited to `100.64.0.0/10` | SSH open to `0.0.0.0/0` |
| LAB-002 | Instance type `t4g.micro` | Instance type `m5.2xlarge` |
| SEC-002 | EBS volume encrypted | EBS volume unencrypted |
| LAB-004 | `SessionId` tag present | `SessionId` tag missing |

---

### Week 7: Reduce False Positives

Person 2 should check:

- Does the policy fail safe resources?
- Is the policy too broad?
- Is the error message clear?
- Does the policy explain how to fix the issue?

Good error message example:

```text
DENY: aws_security_group.web allows SSH from 0.0.0.0/0.
Fix: Restrict SSH to a trusted IP range.
```

---

### Week 8: Final Documentation and Demo

Person 2 should be ready to show:

- A failing Terraform plan
- OPA blocking the plan
- A passing Terraform plan
- Policy documentation
- CIS mapping table

---

## Simple OPA Policy Example

This is a simplified teaching example.

```rego
package terraform.deny

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "aws_security_group"
  ingress := rc.change.after.ingress[_]
  ingress.from_port == 22
  cidr := ingress.cidr_blocks[_]
  cidr == "0.0.0.0/0"
  msg := sprintf("DENY: %v allows SSH from 0.0.0.0/0. Restrict SSH to trusted IPs.", [rc.address])
}
```

---

## Policy Documentation Template

Person 2 should document each policy using this format:

```markdown
## Policy ID: SEC-001

### Rule Name
Restrict SSH access

### Description
Security groups must not allow SSH from the public internet.

### Severity
High

### Affected Resource
aws_security_group

### CIS Mapping
CIS AWS Foundations Benchmark control related to network access restriction.

### Remediation
Restrict SSH to a trusted IP range or VPN CIDR.
```

---

## Definition of Done

Person 2 is complete when:

- [ ] 20 to 25 OPA policies exist
- [ ] Policies are organized by category
- [ ] Each policy has a clear error message
- [ ] Each policy has at least one test case
- [ ] Policies run successfully in CI/CD
- [ ] CIS AWS mapping document exists
- [ ] Policy README exists
- [ ] Demo shows a policy blocking an unsafe plan

---

## Common Mistakes to Avoid

1. Writing policies that are too broad
2. Not testing policies against real Terraform plan JSON
3. Using unclear error messages
4. Copying Rego code without understanding it
5. Trying to create too many policies
6. Forgetting to map policies to CIS controls
7. Not coordinating with Person 1 about module structure

---

## Questions Person 2 Should Answer

- Which policies are mandatory?
- Which policies are warnings only?
- How do we test that a policy works?
- What happens if a policy gives a false positive?
- How does the team update a policy safely?

---

## Suggested Citations

Center for Internet Security. (2023). *CIS Amazon Web Services Foundations Benchmark v1.5.0*. https://www.cisecurity.org/benchmark/aws

Open Policy Agent Authors. (2023). *OPA documentation*. https://www.openpolicyagent.org/docs/latest/
