# Platform Architecture

## Overview

osq uses a serverless control plane and an ephemeral AWS lab plane.

The platform is divided into:

1. Learner frontend
2. Control plane
3. Lab plane
4. Access plane
5. Governance and audit plane

## High-Level Flow

    Learner
      -> S3/CloudFront Frontend
      -> API Gateway
      -> Lambda Session Handler
      -> DynamoDB / Session Store
      -> Lab Orchestrator Lambda
      -> Boto3 EC2 RunInstances
      -> Ephemeral EC2 Lab
      -> Tailscale Enrollment
      -> Learner connects
      -> TTL Lambda terminates lab

## Learner Frontend

Hosting:

- S3 static hosting
- CloudFront distribution
- Optional Route 53 custom domain

Responsibilities:

- Authentication UI
- Home dashboard
- Lab catalog
- My Labs
- Lab guides
- Flag submission
- Getting Started
- Access Setup
- Help & FAQ

The frontend should remain simple and learner-focused.

## Control Plane

Recommended services:

| Component | AWS Service |
|---|---|
| API | API Gateway |
| Session logic | Lambda |
| Lab orchestration | Lambda |
| TTL cleanup | Lambda |
| Scheduler | EventBridge Scheduler |
| Session store | DynamoDB |
| Secrets/config | SSM Parameter Store |
| Encryption | KMS |

Responsibilities:

- Validate user
- Check quota
- Create session
- Launch lab instance
- Track session state
- Terminate expired labs
- Record activity events

## Lab Plane

Recommended services:

| Component | AWS Service |
|---|---|
| Lab compute | EC2 |
| Lab image | Pre-baked AMI |
| Launch config | EC2 Launch Template |
| Storage | EBS with DeleteOnTermination |
| Instance secrets | SSM Parameter Store |
| Logs | CloudWatch Logs |

Responsibilities:

- Run the learner environment
- Inject lab tasks and flags
- Enroll into Tailscale
- Remain isolated from the control plane
- Expire automatically

## Access Plane

Recommended access method:

- Tailscale-only access

Learner connection model:

    Learner device joins tailnet
    Lab instance joins tailnet
    Learner connects using Tailscale SSH

Public SSH should not be exposed.

Fallback for zero-cost or restricted environments:

- AWS SSM Session Manager

## Governance and Audit Plane

Recommended services:

| Component | Service/Tool |
|---|---|
| Infrastructure as Code | Terraform |
| Policy checks | OPA / Conftest |
| CI/CD | GitHub Actions |
| API audit | CloudTrail |
| Drift/config checks | AWS Config |
| Logs | CloudWatch Logs |
| Alerts | SNS |
| Log queries | Athena |
| Cost alerts | AWS Budgets |

## Terraform vs SDK Responsibility

Terraform manages the governed baseline:

- VPC
- Subnets
- Security groups
- IAM roles
- Launch templates
- AMI parameters
- API Gateway
- Lambda functions
- DynamoDB tables
- EventBridge rules
- CloudTrail
- AWS Config
- CloudWatch log groups
- SNS topics

Boto3 SDK manages runtime actions:

- RunInstances
- TerminateInstances
- DescribeInstances
- Create/update session records
- Fetch short-lived secrets
- Clean up session resources

Do not run terraform apply for every learner lab session.

## PoC Simplifications

For the PoC:

- Authentication can use simple personal access tokens.
- Session store can use DynamoDB or PostgreSQL.
- Tailscale enrollment can be simplified.
- Multi-tenant isolation can be simplified.
- Internal governance pages should stay out of the learner UI.
