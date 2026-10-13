# Deployment Guide

## Prerequisites

Required:

- AWS account
- AWS CLI configured
- Terraform installed
- Python 3 installed
- Boto3 installed for Lambda packaging
- GitHub repository
- Tailscale account or test tailnet

Optional:

- Packer or EC2 Image Builder for AMI automation
- Infracost for cost comments
- Checkov for security scanning

## Repository Layout Recommendation

    cloudybt-tounsi/
      frontend/
      docs/
      terraform/
        modules/
        environments/
          dev/
      lambdas/
        session_handler/
        lab_orchestrator/
        ttl_gc/
      policies/
        opa/
      scripts/
      .github/
        workflows/

## Step 1: Deploy Baseline Infrastructure

Use Terraform to deploy:

- VPC
- Subnets
- Security groups
- IAM roles
- DynamoDB tables
- API Gateway
- Lambda functions
- EventBridge rules
- CloudTrail
- AWS Config
- CloudWatch log groups
- SNS topics

Example:

    cd terraform/environments/dev
    terraform init
    terraform plan
    terraform apply

### Seed the tables

The tables are empty on first apply. Load the lab catalog and mint the
learner tokens:

    make seed-labs LABS_TABLE=cloudybttounsi-dev-labs
    make seed-users USERS_TABLE=cloudybttounsi-dev-users

`scripts/seed_users.py` prints each plaintext token exactly once and
stores only its SHA-256 hash. Hand the tokens to learners out of band:
they cannot be recovered. Both scripts are idempotent, so re-running
them leaves existing tokens and lab content alone. Use `--rotate` to
deliberately revoke and replace a token.

The API has no login endpoint. A learner presents their token as
`Authorization: Bearer <token>`.

## Step 2: Build or Select Lab AMIs

Store AMI IDs in SSM Parameter Store:

    /cloudybt/ami/linux
    /cloudybt/ami/dba
    /cloudybt/ami/devops

Each AMI should include:

- Tailscale
- CloudWatch agent or logging
- Lab tools
- Bootstrap scripts

## Step 3: Deploy Frontend

`terraform/modules/frontend` creates a private S3 bucket behind CloudFront.
Neither is public: CloudFront reaches the bucket through origin access
control, and the only reader is the distribution itself.

The bucket name is AWS-generated, so read it back from state:

    terraform -chdir=terraform/environments/dev output frontend_bucket_name
    terraform -chdir=terraform/environments/dev output frontend_url

Then sync the site and invalidate the cache:

    make deploy-frontend

That target runs `aws s3 sync` (excluding `smoke.test.js`, which is a
Node test and not part of the site), sets a short cache lifetime on
`index.html` so a deploy is visible on the next refresh, and issues a
CloudFront invalidation. It reads the bucket and distribution id from
dev state automatically; override `FRONTEND_BUCKET` and
`FRONTEND_DISTRIBUTION` when targeting a different environment.

## Step 4: Configure Lab Secrets

Store short-lived or managed values in SSM:

- Tailscale auth key generation reference
- Lab bootstrap configuration
- Optional DNS or domain values

Do not store plaintext secrets in Git.

## Step 5: Verify API

Test endpoints:

    GET /me
    GET /labs
    POST /labs/start
    GET /sessions
    POST /sessions/{id}/destroy

## Step 6: Verify Lab Provisioning

Confirm:

- EC2 instance launches
- Tags are applied
- Tailscale enrollment starts
- Session becomes READY
- SSH command appears in UI

## Step 7: Verify TTL Cleanup

Confirm:

- EventBridge rule is active
- TTL Lambda runs
- Expired EC2 instance is terminated
- Session becomes TERMINATED
- Activity event is recorded

## Step 8: Verify Governance

Confirm:

- GitHub Actions pipeline runs
- OPA policy check blocks bad Terraform
- CloudTrail records deployment events
- AWS Config is enabled
- Alerts are delivered to SNS

## Troubleshooting

### API returns 401

- Check token
- Check token hash
- Check user isActive

### Lab stuck in PROVISIONING

- Check Lambda logs
- Check EC2 RunInstances permissions
- Check AMI ID parameter
- Check launch template

### Tailscale not reachable

- Check Tailscale auth key
- Check instance outbound internet access
- Check learner device Tailscale status

### Lab not terminated

- Check EventBridge schedule
- Check TTL Lambda permissions
- Check ExpiresAt tag
- Check instance state filters
