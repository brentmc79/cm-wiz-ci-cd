# Required GCP APIs
locals {
  required_services = [
    "run.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "aiplatform.googleapis.com",
    "accesscontextmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "logging.googleapis.com",
  ]

  default_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.codemender_repo.repository_id}/codemender-runner:latest"
  runner_image  = var.codemender_image != "" ? var.codemender_image : local.default_image
}

resource "google_project_service" "enabled_apis" {
  for_each                   = toset(local.required_services)
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Artifact Registry Repository for CodeMender Runner Images
resource "google_artifact_registry_repository" "codemender_repo" {
  repository_id = var.artifact_registry_repo_id
  format        = "DOCKER"
  location      = var.region
  project       = var.project_id
  description   = "Docker repository for CodeMender runner container images"

  labels = {
    managed_by = "terraform"
    purpose    = "codemender-ci-cd"
  }

  depends_on = [google_project_service.enabled_apis]
}

# Cloud Run v2 Job for CodeMender Fix Execution
resource "google_cloud_run_v2_job" "codemender_fix_job" {
  name                = var.cloud_run_job_name
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  template {
    task_count = 1

    template {
      timeout         = "${var.job_timeout_seconds}s"
      service_account = google_service_account.codemender_runner_sa.email

      # Direct VPC Egress: route all outbound traffic through the dedicated VPC subnet
      vpc_access {
        network_interfaces {
          network    = google_compute_network.codemender_vpc.name
          subnetwork = google_compute_subnetwork.codemender_subnet.name
        }
        egress = "ALL_TRAFFIC"
      }

      containers {
        image = local.runner_image

        resources {
          limits = {
            cpu    = var.job_cpu
            memory = var.job_memory
          }
        }

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "GEMINI_MODEL"
          value = var.gemini_model
        }

        env {
          name  = "GCP_REGION"
          value = var.region
        }

        # GitHub authentication token securely injected from Secret Manager
        env {
          name = "GITHUB_TOKEN"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.github_token.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  labels = {
    managed_by = "terraform"
    service    = "codemender"
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_compute_subnetwork.codemender_subnet,
    google_secret_manager_secret_version.github_token_version,
    google_secret_manager_secret_iam_member.codemender_secret_accessor,
  ]
}
