# Secret Manager Secret for GitHub Token / GitHub App Key
resource "google_secret_manager_secret" "github_token" {
  secret_id = var.github_token_secret_name
  project   = var.project_id

  replication {
    auto {}
  }

  labels = {
    managed_by = "terraform"
    purpose    = "codemender-github-auth"
  }

  depends_on = [google_project_service.enabled_apis]
}

# Initial secret version to ensure Cloud Run job creation succeeds
resource "google_secret_manager_secret_version" "github_token_version" {
  secret      = google_secret_manager_secret.github_token.id
  secret_data = var.initial_github_token
}

# Grant Cloud Run Runtime Service Account access to read the secret
resource "google_secret_manager_secret_iam_member" "codemender_secret_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.github_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.codemender_runner_sa.email}"
}
