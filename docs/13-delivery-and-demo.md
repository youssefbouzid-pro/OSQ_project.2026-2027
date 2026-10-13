# Delivery Plan and Demo Script

## Delivery Focus

The project should deliver a working learner-facing PoC, not a full production SaaS platform.

Priority order:

1. Learner authentication
2. Lab catalog
3. Lab session lifecycle
4. Lab guide and tasks
5. Flag submission
6. Tailscale access explanation
7. TTL expiration behavior
8. Admin activity view
9. Terraform baseline
10. CI/CD and policy checks
11. Documentation
12. Final demo

## Suggested Milestones

### Milestone 1: Core Learner UI

- Login
- Home
- Catalog
- My Labs
- Lab Guide

### Milestone 2: Lab Session Flow

- Start lab
- Session states
- TTL countdown
- End lab

### Milestone 3: AWS Provisioning

- Terraform baseline deployed
- Launch templates created
- AMI parameters stored
- Boto3 provisioning Lambda working
- EC2 lab instance launched

### Milestone 4: Tasks and Flags

- Lab tasks
- Hints
- Flag submission
- Completion state

### Milestone 5: TTL and Cleanup

- EventBridge scheduler
- Garbage collector Lambda
- Expired lab termination
- Session state update

### Milestone 6: Governance and Audit

- GitHub Actions pipeline
- OPA policy checks
- CloudTrail enabled
- Activity feed
- Admin budget indicator

### Milestone 7: Documentation and Demo

- Repo docs
- Demo script
- Final polish

## Final Demo Script

### 1. Sign in as student

Show:

- Home dashboard
- Recommended labs
- Continue learning card

### 2. Browse catalog

Show:

- Lab families
- Difficulty levels
- Filters

### 3. Open a lab guide

Show:

- Lab description
- Tasks
- Hints
- Flags

### 4. Start a lab

Show:

- Session created
- Provisioning states
- Ready state
- TTL countdown

### 5. Show AWS resources

Show:

- EC2 instance launched
- Tags applied
- Launch template used
- CloudTrail event

### 6. Connect to lab

Show:

- SSH command
- Tailscale access explanation
- Lab terminal if available

### 7. Submit a flag

Show:

- Flag accepted
- Task marked complete

### 8. Show expiration

Show:

- TTL warning
- Garbage collector terminating instance
- Session marked ended

### 9. Sign in as admin

Show:

- Activity feed
- All sessions
- Budget indicator

### 10. Explain governance

Show:

- Terraform baseline
- OPA policy check
- GitHub Actions pipeline
- Learner UI does not expose internal docs
