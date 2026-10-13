# 03 Dynamic Lab Provisioning Sequence

## Purpose

This diagram shows how a lab is dynamically provisioned only when requested.

The platform uses:

- Terraform-managed Launch Templates
- AWS SDK runtime provisioning
- ephemeral Tailscale auth keys
- session-specific tags
- 60-minute TTL
- automatic garbage collection

---

## Diagram

```mermaid
sequenceDiagram
    participant Backend as Lab Backend
    participant LabManager as Lab Manager
    participant TailscaleAPI as Tailscale API
    participant SSM as SSM Parameter Store
    participant EC2 as EC2 Launch Template
    participant Student as Student Laptop

    Backend->>LabManager: Create lab session
    LabManager->>LabManager: Calculate expires_at = now + 60 minutes

    LabManager->>TailscaleAPI: Create ephemeral auth key
    TailscaleAPI-->>LabManager: Return short-lived auth key

    LabManager->>SSM: Store auth key as SecureString
    LabManager->>EC2: RunInstances using approved Launch Template

    EC2->>SSM: Retrieve auth key using instance role
    EC2->>TailscaleAPI: Join tailnet with Tailscale SSH enabled
    TailscaleAPI-->>EC2: Device registered

    LabManager->>Backend: Update session status to READY
    Backend->>Student: UI shows lab hostname and access command

    Student->>EC2: tailscale ssh student@lab-hostname
```

---

## Session Tags

Every dynamically created lab instance must include these tags:

```text
Project       = cloudybt-tounsi
ManagedBy     = lab-manager
LabType       = linux
SessionId     = lab-9f2a
UserId        = student-01
CreatedAt     = 2026-04-14T10:00:00Z
ExpiresAt     = 2026-04-14T11:00:00Z
TTLMinutes    = 60
AutoDestroy   = true
```

---

## TTL Enforcement

The 60-minute TTL is enforced by:

```text
1. DynamoDB session record
2. EC2 ExpiresAt tag
3. Tailscale ephemeral auth key expiry
4. EventBridge scheduled garbage collector
5. Audit logging
```

---

## Garbage Collection

A scheduled Lambda function runs every 5 minutes.

It performs:

```text
Find all lab instances with ManagedBy = lab-manager
Check ExpiresAt tag
Terminate expired instances
Update session status
Remove stale Tailscale devices if needed
Write audit log
```

---

## Important Note

The platform does not run `terraform apply` for every lab session.

Terraform manages the governed baseline:

```text
VPC
Subnets
Security Groups
IAM roles
SSM parameters
Launch Templates
API infrastructure
Garbage collector infrastructure
```

The application uses the AWS SDK to launch ephemeral labs from the approved template.
