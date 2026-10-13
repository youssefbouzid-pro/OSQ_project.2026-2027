# 04_Person4_Audit_Compliance.md

> **Scope note:** This charter's generic 8-week sequence is superseded by
> [`diagrams/07-delivery-roadmap.md`](../diagrams/07-delivery-roadmap.md), which sequences the work for the
> CloudyBTTounsi Lab Platform. Drift detection and remediation must follow
> [`diagrams/06-drift-remediation-workflow.md`](../diagrams/06-drift-remediation-workflow.md): Terraform is
> the source of truth and remediation runs through `terraform apply`, not direct resource edits.

## Purpose

Person 4 is the **Audit and Compliance Lead**.  
This person is responsible for detecting drift, collecting audit logs, and producing compliance reports.

The goal is to answer three important questions:

1. Who changed something?
2. What was changed?
3. Did the change match our infrastructure code?

---

## Project Scope for Person 4

### In Scope

Person 4 should deliver:

1. AWS CloudTrail logging
2. AWS Config drift detection
3. Simple compliance reports
4. Alerting for drift or violations
5. Basic forensics documentation
6. Incident response runbook

---

## Out of Scope

Person 4 should **not**:

- Build a custom drift detection engine from scratch
- Create 10+ compliance report templates
- Support GCP logging
- Build a full SIEM platform
- Implement machine learning anomaly detection unless the team is ahead of schedule

---

## 8-Week Plan

### Week 1: Audit Design

Person 4 should define:

- What logs are collected?
- Where logs are stored?
- How long logs are retained?
- Who can read logs?
- How alerts are sent?

Recommended AWS services:

| Service | Purpose |
|---|---|
| CloudTrail | Records AWS API activity |
| AWS Config | Detects configuration drift |
| SNS | Sends alerts |
| S3 | Stores logs and reports |
| Athena | Queries logs |

---

### Week 2: Enable CloudTrail

Person 4 should ensure CloudTrail logs:

- Management events
- Write operations
- Read operations if budget allows
- Log delivery to S3
- Log file validation if available

The S3 bucket should be protected:

- Encrypted
- Versioned
- Restricted by IAM
- Not public

---

### Week 3: Enable AWS Config

AWS Config should monitor important resources.

Start with:

- S3 buckets
- IAM roles
- Security groups
- EC2 instances
- DynamoDB tables

AWS Config can report whether resources are:

```text
COMPLIANT
NON_COMPLIANT
NOT_APPLICABLE
```

---

### Week 4: Drift Detection

Person 4 should show how drift is detected.

Drift means the real AWS resource does not match the expected infrastructure definition.

Example drift scenarios:

| Scenario | Risk Level |
|---|---|
| Someone makes an S3 bucket public | High |
| Someone changes a security group manually | High |
| Someone adds a tag manually | Low |
| Someone changes instance size manually | Medium |
| Someone deletes a backup | Critical |

---

### Week 5: Alerting

Create simple alerts.

Example alert flow:

```text
AWS Config detects NON_COMPLIANT resource
        ↓
SNS topic is notified
        ↓
Email or Slack alert is sent
```

Example alert message:

```text
Alert: AWS Config found a non-compliant S3 bucket.
Resource: example-bucket
Rule: s3-bucket-public-read-prohibited
Action: Review and remediate immediately.
```

---

### Week 6: Compliance Reporting

Person 4 should create at least three simple reports.

Recommended reports:

1. CIS compliance summary
2. Drift summary
3. Policy violation summary

Example compliance summary:

```text
Compliance Summary
------------------
Total rules checked: 20
Compliant: 16
Non-compliant: 4
Compliance score: 80%
```

Example drift summary:

```text
Drift Summary
-------------
Resources checked: 35
Resources in drift: 3
High-risk drift: 1
Low-risk drift: 2
```

---

### Week 7: Forensics and Runbooks

Person 4 should create a simple runbook.

Example runbook structure:

```markdown
## Incident: Public S3 Bucket Detected

### Step 1: Confirm the alert
Check AWS Config and CloudTrail.

### Step 2: Identify who made the change
Query CloudTrail for the S3 bucket name.

### Step 3: Determine if the change was approved
Compare the change with Terraform code and pull requests.

### Step 4: Remediate
Block public access immediately.

### Step 5: Document
Record what happened, who fixed it, and how to prevent it.
```

---

### Week 8: Final Demo Preparation

Person 4 should be ready to show:

- CloudTrail logs in S3
- AWS Config rule result
- Drift detection example
- Compliance report
- Alert message
- Forensics query example

---

## Simple Example: AWS Config Rule

This is a simple Terraform example using an AWS managed rule.

```hcl
resource "aws_config_config_rule" "s3_versioning" {
  name = "s3-versioning-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_VERSIONING_ENABLED"
  }
}
```

Note: AWS Config requires a configuration recorder and delivery channel. This example shows the rule only.

---

## Simple Example: Athena Query for CloudTrail

```sql
SELECT
  eventTime,
  eventName,
  userIdentity.arn AS user_arn,
  sourceIPAddress
FROM cloudtrail_logs
WHERE eventName = 'DeleteBucket'
ORDER BY eventTime DESC
LIMIT 20;
```

This query helps answer:

- Who deleted a bucket?
- When did it happen?
- From which IP address?

---

## Recommended Compliance Dashboard Fields

If the team creates a simple dashboard, it can show:

| Field | Example |
|---|---|
| Total resources | 42 |
| Compliant resources | 38 |
| Non-compliant resources | 4 |
| Resources in drift | 2 |
| High-risk alerts | 1 |
| Last scan time | 2026-04-14 10:00 UTC |

---

## Definition of Done

Person 4 is complete when:

- [ ] CloudTrail is enabled
- [ ] CloudTrail logs are stored in S3
- [ ] AWS Config is enabled
- [ ] At least five AWS Config rules exist
- [ ] Drift detection works
- [ ] At least one alert exists
- [ ] Three compliance or audit reports exist
- [ ] One incident response runbook exists
- [ ] One forensics query example exists
- [ ] Demo shows a detected drift or violation

---

## Common Mistakes to Avoid

1. Enabling logging but not checking if logs are stored correctly
2. Making CloudTrail S3 bucket public
3. Creating too many alerts
4. Not testing drift detection
5. Not documenting how to investigate an alert
6. Forgetting to coordinate with Person 1 and Person 2
7. Trying to build a custom audit platform instead of using AWS services

---

## Questions Person 4 Should Answer

- Where are audit logs stored?
- Who can access audit logs?
- How quickly is drift detected?
- What happens when a high-risk change occurs?
- How can the team prove compliance during an audit?

---

## Suggested Citations

Amazon Web Services. (2023). *AWS Config documentation*. https://docs.aws.amazon.com/config/

Amazon Web Services. (2023). *AWS CloudTrail documentation*. https://docs.aws.amazon.com/awscloudtrail/
