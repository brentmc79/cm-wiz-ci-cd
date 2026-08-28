# Google CodeMender + Wiz CI/CD Integration

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Google Cloud](https://img.shields.io/badge/Google_Cloud-Cloud_Run_|_VPC--SC-4285F4?logo=googlecloud&logoColor=white)](https://cloud.google.com)
[![Gemini](https://img.shields.io/badge/Model-Gemini_3.5_Flash-8E75B2?logo=google)](https://deepmind.google/technologies/gemini/)

This repository contains an enterprise reference implementation for integrating **Google CodeMender** into a CI/CD workflow to automatically remediate security vulnerabilities detected by **Wiz**.

---

## 🎯 Solution Highlights

* **Automated Remediation on Mention**: Developers and security engineers can trigger automated remediation simply by commenting `@codemender` on any Wiz finding GitHub issue.
* **Azure-Hosted Runner Support**: Seamless integration for GitHub runners self-hosted in Azure, authenticating passwordless to Google Cloud using **Workload Identity Federation (WIF)**.
* **Isolated Cloud Run Execution**: Code remediation runs inside Google Cloud Run Jobs protected by **Direct VPC Egress** and **VPC Service Controls (VPC-SC)** perimeters.
* **Configurable Inbound/Outbound Controls**:
  * Ingress restricted to Internal / Internal & Cloud Load Balancing.
  * Egress routed directly through a dedicated VPC subnet, with optional Cloud NAT or custom proxy routing.
  * Invocation supported via Google Cloud Run API or private Azure-to-GCP Interconnect.
* **Automated Pull Request Generation**: CodeMender inspects the Wiz finding, applies surgical patches using `gemini-3.5-flash`, runs test suites to verify zero regressions, and opens a Pull Request with full context.

---

## 📁 Repository Structure

```text
.
├── .github/
│   ├── workflows/
│   │   └── codemender-fix.yml       # GitHub Actions workflow responding to @codemender comments
│   └── ISSUE_TEMPLATE/
│       └── wiz-finding.md           # Standard Wiz security finding issue template
├── docker/
│   ├── Dockerfile                   # CodeMender Cloud Run runner container image definition
│   ├── entrypoint.sh                # Container entrypoint script
│   └── fix_orchestrator.py          # Python orchestrator coordinating git clone, fix, test, and PR creation
├── terraform/
│   ├── versions.tf                  # Provider requirements
│   ├── variables.tf                 # Configurable variables (NAT, ILB, VPC-SC, WIF, Model)
│   ├── main.tf                      # Core resources (Cloud Run Job, Artifact Registry, APIs)
│   ├── networking.tf                # VPC, Subnets, Direct VPC Egress, Cloud NAT, Internal Load Balancer
│   ├── iam.tf                       # WIF Pool/Provider, Service Accounts, and least-privilege IAM
│   ├── secrets.tf                   # Secret Manager integration for GitHub tokens
│   ├── vpc_sc.tf                    # VPC Service Controls Security Perimeter
│   ├── outputs.tf                   # Exported configuration values for CI/CD setup
│   └── terraform.tfvars.example     # Example variable values
├── poc-app/                         # Sample vulnerable application for PoC validation
│   ├── app.py                       # Sample Flask application with a SQL Injection finding
│   ├── requirements.txt             # Application dependencies
│   ├── tests/
│   │   └── test_app.py              # Unit tests with security regression assertions
│   ├── sample_wiz_finding.md        # Sample Wiz finding issue template for testing
│   └── README.md                    # PoC instructions
├── docs/
│   ├── architecture.md              # Detailed architecture and security boundaries
│   └── deployment_guide.md          # Step-by-step infrastructure and CI/CD deployment guide
└── README.md
```

---

## 🚀 Quick Start

### 1. Provision Infrastructure
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project ID and GitHub org
terraform init
terraform apply
```

### 2. Build & Push Runner Image
```bash
cd ../docker
REPO_URI="us-central1-docker.pkg.dev/<PROJECT_ID>/codemender-runners/codemender-runner:latest"
docker build -t "${REPO_URI}" .
docker push "${REPO_URI}"
```

### 3. Configure GitHub Repo & Test
1. Set the repository variables (`GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_RUNNER_SERVICE_ACCOUNT`, `GCP_CLOUD_RUN_JOB_NAME`) as detailed in [docs/deployment_guide.md](docs/deployment_guide.md).
2. Create an issue using [poc-app/sample_wiz_finding.md](poc-app/sample_wiz_finding.md).
3. Comment `@codemender fix` to watch the automated remediation in action!

---

## 📖 Documentation
* [Architecture & Security Design](docs/architecture.md)
* [Deployment & Setup Guide](docs/deployment_guide.md)
* [PoC Application Guide](poc-app/README.md)
