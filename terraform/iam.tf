# --- Service Accounts ---

# 1. Service Account for GitHub Actions Runner (Invoker)
resource "google_service_account" "github_runner_sa" {
  account_id   = "gh-runner-invoker"
  display_name = "GitHub Actions Cloud Run Invoker SA"
  description  = "Service account assumed by GitHub Actions (via WIF) to trigger CodeMender Cloud Run Jobs"
  project      = var.project_id
  depends_on   = [google_project_service.enabled_apis]
}

# 2. Service Account for Cloud Run Job Runtime (CodeMender Execution)
resource "google_service_account" "codemender_runner_sa" {
  account_id   = "codemender-runner-sa"
  display_name = "CodeMender Cloud Run Runner SA"
  description  = "Runtime service account for CodeMender container execution inside Cloud Run"
  project      = var.project_id
  depends_on   = [google_project_service.enabled_apis]
}

# --- Workload Identity Federation (WIF) ---

resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions OIDC"
  project                   = var.project_id
  disabled                  = false
  depends_on                = [google_project_service.enabled_apis]
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "GitHub Actions Provider"
  description                        = "OIDC Provider for GitHub Actions"
  project                            = var.project_id

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow GitHub Actions matching repository owner to impersonate the Invoker Service Account
resource "google_service_account_iam_member" "github_runner_wif_binding" {
  service_account_id = google_service_account.github_runner_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository_owner/${var.github_owner}"
}

# Allow Invoker SA to act as the Cloud Run Job runtime service account
resource "google_service_account_iam_member" "allow_invoker_sa_user" {
  service_account_id = google_service_account.codemender_runner_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_runner_sa.email}"
}

# --- Permissions for GitHub Runner Invoker SA ---

# Permission to run and manage Cloud Run Job executions
resource "google_project_iam_member" "github_runner_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.github_runner_sa.email}"
}

# Permission to view execution logs
resource "google_project_iam_member" "github_runner_log_viewer" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.github_runner_sa.email}"
}

# --- Permissions for CodeMender Runtime SA ---

# Permission to write logs
resource "google_project_iam_member" "codemender_runner_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.codemender_runner_sa.email}"
}

# Permission to access Vertex AI / Gemini API
resource "google_project_iam_member" "codemender_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.codemender_runner_sa.email}"
}

# Permission to pull container images from Artifact Registry
resource "google_project_iam_member" "codemender_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.codemender_runner_sa.email}"
}
