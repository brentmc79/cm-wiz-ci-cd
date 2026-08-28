output "workload_identity_provider" {
  description = "The Workload Identity Provider resource name to configure in GitHub Actions workflow"
  value       = google_iam_workload_identity_pool_provider.github_provider.name
}

output "github_runner_service_account" {
  description = "The Service Account email that GitHub Actions should impersonate via WIF"
  value       = google_service_account.github_runner_sa.email
}

output "codemender_runtime_service_account" {
  description = "The runtime Service Account email assigned to the Cloud Run Job"
  value       = google_service_account.codemender_runner_sa.email
}

output "cloud_run_job_name" {
  description = "Name of the Cloud Run Job"
  value       = google_cloud_run_v2_job.codemender_fix_job.name
}

output "cloud_run_job_location" {
  description = "Region of the Cloud Run Job"
  value       = google_cloud_run_v2_job.codemender_fix_job.location
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository URI for pushing the CodeMender runner Docker image"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.codemender_repo.repository_id}"
}

output "vpc_network_name" {
  description = "The VPC network name"
  value       = google_compute_network.codemender_vpc.name
}

output "subnet_name" {
  description = "The Subnet name used for Cloud Run Direct VPC Egress"
  value       = google_compute_subnetwork.codemender_subnet.name
}

output "github_secret_id" {
  description = "Secret Manager secret ID holding the GitHub token"
  value       = google_secret_manager_secret.github_token.secret_id
}

output "ilb_ip_address" {
  description = "Internal Application Load Balancer IP address (if enabled)"
  value       = var.enable_internal_load_balancer ? google_compute_forwarding_rule.ilb_forwarding_rule[0].ip_address : "N/A (Disabled)"
}

output "gcp_runner_instance_name" {
  description = "Name of the GCP self-hosted GitHub Actions runner VM (if enabled)"
  value       = var.enable_gcp_runner ? google_compute_instance.gcp_github_runner[0].name : "N/A (Disabled)"
}

output "gcp_runner_private_ip" {
  description = "Internal IP address of the GCP self-hosted GitHub runner VM"
  value       = var.enable_gcp_runner ? google_compute_instance.gcp_github_runner[0].network_interface[0].network_ip : "N/A (Disabled)"
}
