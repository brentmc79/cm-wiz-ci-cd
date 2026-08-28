# Architecture & Security Design: CodeMender CI/CD Integration

This document outlines the architectural and security design for integrating Google CodeMender into a CI/CD workflow triggered by Wiz security findings.

---

## 1. High-Level Architecture

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer / Security Team
    participant GH as GitHub Issues & Repo
    participant Runner as Azure Self-Hosted Runner
    participant GCP_WIF as GCP Workload Identity (WIF)
    participant CR as Cloud Run Job (VPC-SC Perimeter)
    participant SM as Secret Manager
    participant AI as Gemini 3.5 Flash / CodeMender API

    Note over GH: Wiz scan detects vuln and opens GitHub Issue
    Dev->>GH: Comment "@codemender fix"
    GH->>Runner: Trigger .github/workflows/codemender-fix.yml
    Runner->>GCP_WIF: Authenticate with GitHub OIDC Token
    GCP_WIF-->>Runner: Return ephemeral GCP Access Token
    Runner->>CR: Execute Cloud Run Job (with issue context overrides)
    
    activate CR
    Note over CR: Execution inside Direct VPC Egress & VPC-SC
    CR->>SM: Fetch GitHub App / PAT Token
    CR->>GH: Clone target repository at current branch
    CR->>AI: Send finding context & target code for remediation
    AI-->>CR: Return minimal, secure code patch
    CR->>CR: Apply patch & execute test suite (e.g. pytest)
    CR->>GH: Push fix branch (codemender/fix-issue-X)
    CR->>GH: Open Pull Request referencing Issue
    CR->>GH: Post confirmation comment with PR link on Issue
    deactivate CR
    Runner-->>GH: Job completes successfully
```

---

## 2. Security Boundaries & Guardrails

### A. Authentication via Workload Identity Federation (WIF)
* **Zero Long-Lived Keys**: Azure-hosted runners authenticate to Google Cloud using short-lived GitHub Actions OIDC tokens via a dedicated Workload Identity Pool and Provider.
* **Strict Subject Constraints**: The WIF provider validates that the token was issued for the designated GitHub organization (`assertion.repository_owner == var.github_owner`).

### B. Inbound Access & Invocation
* **Internal Ingress**: Cloud Run compute resources are restricted from public ingress.
* **Flexible Invocation**:
  * **Option 1 (Default)**: Direct invocation via the Google Cloud Run API (`run.googleapis.com`) using IAM permissions granted via WIF.
  * **Option 2 (Private Interconnect)**: Private HTTP invocation via an Internal Application Load Balancer (ILB) with Serverless NEG over an existing Azure-to-GCP VPN or Interconnect.

### C. Outbound Access & Direct VPC Egress
* **Direct VPC Egress**: Configured with `egress = "ALL_TRAFFIC"` to route all outbound network traffic from the container through a private VPC subnet.
* **Controlled Internet Egress**: Outbound connections to GitHub API (`github.com`) and package registries are routed through a dedicated Cloud NAT gateway (which can be toggled off if an enterprise egress proxy is used).

### D. VPC Service Controls (VPC-SC)
* **Data Exfiltration Prevention**: Encloses the project, Cloud Run jobs, Artifact Registry, Secret Manager, and Vertex AI services within a secure Service Perimeter.
* **Access Policies**: Restricts API calls to authorized service accounts and VPC networks only.

### E. Credential Isolation
* GitHub credentials (PAT or GitHub App private keys) are stored in Secret Manager and accessed only at runtime by the Cloud Run execution service account.
