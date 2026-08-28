# Deployment & Setup Guide: CodeMender CI/CD

Follow this guide to deploy the Google Cloud infrastructure and integrate CodeMender into your GitHub repositories.

---

## Step 1: Provision Google Cloud Infrastructure via Terraform

1. Navigate to the `terraform/` directory:
   ```bash
   cd terraform
   ```

2. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Configure your variables in `terraform.tfvars`:
   * `project_id`: Your Google Cloud project ID.
   * `region`: Target GCP region (e.g. `us-central1`).
   * `github_owner`: Your GitHub organization or username.
   * `create_cloud_nat`: `true` to provision Cloud NAT for internet egress, or `false` if using an existing proxy.
   * `enable_internal_load_balancer`: `true` if invoking via private Azure-to-GCP Interconnect.
   * `enable_vpc_sc`: `true` if enabling VPC Service Controls perimeter.
   * `enable_gcp_runner`: `true` if you want Terraform to provision a private GCP Compute Engine VM self-hosting the GitHub Actions runner (see [GCP Self-Hosted Runner Guide](gcp_self_hosted_runner.md)).

4. Initialize and apply the Terraform plan:
   ```bash
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

5. Record the Terraform outputs:
   * `workload_identity_provider`
   * `github_runner_service_account`
   * `artifact_registry_repository`
   * `github_secret_id`

---

## Step 2: Store GitHub Credentials in Secret Manager

Store your GitHub App private key or Personal Access Token (with `repo` permissions) in the Secret Manager secret created by Terraform:

```bash
# Add your GitHub PAT or App token as the latest secret version
echo -n "ghp_yourPersonalAccessTokenOrAppKey" | gcloud secrets versions add codemender-github-token \
  --project="YOUR_PROJECT_ID" \
  --data-file=-
```

---

## Step 3: Build & Push the Runner Container Image

1. Authenticate Docker with Artifact Registry:
   ```bash
   gcloud auth configure-docker us-central1-docker.pkg.dev
   ```

2. Build and push the container image:
   ```bash
   cd ../docker
   REPO_URI="us-central1-docker.pkg.dev/YOUR_PROJECT_ID/codemender-runners/codemender-runner:latest"

   docker build -t "${REPO_URI}" .
   docker push "${REPO_URI}"
   ```

---

## Step 4: Configure GitHub Repository Variables

In your target GitHub repository (or Organization settings), configure the following repository variables under **Settings > Secrets and variables > Actions > Variables**:

| Variable Name | Value Description | Example Value |
|---|---|---|
| `GCP_PROJECT_ID` | Your GCP Project ID | `my-security-project-123` |
| `GCP_REGION` | GCP Region | `us-central1` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Output from `terraform output workload_identity_provider` | `projects/123/locations/global/workloadIdentityPools/...` |
| `GCP_RUNNER_SERVICE_ACCOUNT` | Output from `terraform output github_runner_service_account` | `gh-runner-invoker@my-proj.iam.gserviceaccount.com` |
| `GCP_CLOUD_RUN_JOB_NAME` | Cloud Run Job Name | `codemender-fix-runner` |

---

## Step 5: Test the Integration with PoC

1. Copy `.github/workflows/codemender-fix.yml` into `.github/workflows/` of your target repo.
2. Open a test GitHub issue with a Wiz finding (e.g. from `poc-app/sample_wiz_finding.md`).
3. Add a comment:
   ```text
   @codemender fix
   ```
4. Observe the GitHub Action run on your Azure self-hosted runner:
   * It logs in via WIF.
   * Kicks off the Cloud Run Job.
   * CodeMender fixes the vulnerability, passes tests, and opens a Pull Request.
