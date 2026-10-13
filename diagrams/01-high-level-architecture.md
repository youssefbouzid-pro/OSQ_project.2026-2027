# 01 Proposed Architecture

## Purpose

This diagram shows the updated CloudyBTTounsi architecture.

The platform is divided into:

1. **Edge and Frontend**
   - Route 53
   - CloudFront
   - S3 static frontend

2. **Application Plane**
   - API Gateway
   - simple token authentication middleware
   - backend Lambda or application service
   - DynamoDB

3. **Control Plane**
   - Lab Manager
   - approved EC2 Launch Template
   - ephemeral EC2 lab provisioning
   - TTL garbage collector

4. **Access Plane**
   - Tailscale
   - Tailscale SSH
   - no public SSH

5. **Governance Plane**
   - Terraform
   - OPA
   - GitHub Actions
   - CloudTrail
   - AWS Config
   - SNS alerts

---

## Diagram

```mermaid
graph TB
    Internet["Internet"] --> R53["Route 53<br />cloudy.tn"]
    R53 --> CF["CloudFront"]

    subgraph Edge["Edge and Frontend"]
        S3["S3 Static Frontend"]
    end

    CF --> S3
    CF --> API["API Gateway"]

    subgraph ApplicationPlane["Application Plane"]
        API --> Auth["Simple Token Auth Middleware"]
        Auth --> Backend["Lab Backend / Lambda"]
        Backend --> DB[("DynamoDB")]
    end

    subgraph ControlPlane["Control Plane"]
        Backend --> LabManager["Lab Manager"]
        LabManager --> Template["Approved EC2 Launch Template"]
        LabManager --> EC2["Ephemeral EC2 Lab Instance"]

        Scheduler["EventBridge Scheduler"] --> GC["TTL Garbage Collector"]
        GC --> EC2
    end

    subgraph AccessPlane["Access Plane"]
        Student["Student"] --> Tailscale["Tailscale"]
        Tailscale --> EC2
    end

    subgraph GovernancePlane["Governance Plane"]
        Repo["GitHub Repository"] --> Actions["GitHub Actions"]
        Actions --> Terraform["Terraform Modules"]
        Actions --> OPA["OPA / Conftest"]
        OPA --> Terraform

        Terraform -.-> S3
        Terraform -.-> API
        Terraform -.-> Auth
        Terraform -.-> Backend
        Terraform -.-> DB
        Terraform -.-> Template
        Terraform -.-> LabManager
        Terraform -.-> GC

        EC2 --> Trail["CloudTrail"]
        Backend --> Trail
        Trail --> Config["AWS Config"]
        Config --> SNS["SNS Alerts"]
    end
```

---

## Key Architecture Notes

- The frontend is static and hosted on S3.
- CloudFront is optional but recommended.
- The API uses simple token authentication.
- DynamoDB stores users, token hashes, lab sessions, and audit events.
- Labs are not always running.
- EC2 instances are launched only when a lab is requested.
- Every lab has a hard TTL of 60 minutes.
- Student access happens through Tailscale SSH.
- Public SSH is not allowed.
- Terraform governs the baseline infrastructure.
- Runtime provisioning is handled by the AWS SDK for speed.
