variable "project_id" {
  description = "The Google Cloud Project ID where resources will be provisioned"
  type        = string
}

variable "region" {
  description = "The GCP region for Cloud Run jobs, networking, and Artifact Registry"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment identifier (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

# --- Networking Variables ---

variable "network_name" {
  description = "Name of the VPC network to create"
  type        = string
  default     = "codemender-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet for Cloud Run Direct VPC Egress"
  type        = string
  default     = "codemender-runner-subnet"
}

variable "subnet_cidr" {
  description = "IP CIDR range for the Cloud Run runner subnet"
  type        = string
  default     = "10.10.0.0/24"
}

variable "create_cloud_nat" {
  description = "Set to true to provision Cloud Router and Cloud NAT for outbound internet egress (e.g. GitHub API, package downloads). Set to false if an enterprise proxy or existing interconnect routing is used."
  type        = bool
  default     = true
}

variable "enable_internal_load_balancer" {
  description = "Set to true to provision an Internal Application Load Balancer (ILB) with Serverless NEG for private HTTP invocation across an Azure-GCP Interconnect/VPN. If false, invocation is performed directly via Google Cloud Run API over WIF."
  type        = bool
  default     = false
}

variable "ilb_subnet_cidr" {
  description = "IP CIDR range for the proxy-only subnet if Internal Load Balancer is enabled"
  type        = string
  default     = "10.10.1.0/24"
}

# --- Cloud Run Job Variables ---

variable "cloud_run_job_name" {
  description = "Name of the Cloud Run Job for CodeMender fix execution"
  type        = string
  default     = "codemender-fix-runner"
}

variable "codemender_image" {
  description = "Docker image URI for the CodeMender runner container in Artifact Registry. If empty, defaults to the image in the managed Artifact Registry repository."
  type        = string
  default     = ""
}

variable "gemini_model" {
  description = "The Gemini model to use for CodeMender fix reasoning (e.g. gemini-3.5-flash, gemini-3.1-pro)"
  type        = string
  default     = "gemini-3.5-flash"
}

variable "job_cpu" {
  description = "CPU allocation for the Cloud Run Job"
  type        = string
  default     = "2"
}

variable "job_memory" {
  description = "Memory allocation for the Cloud Run Job"
  type        = string
  default     = "4Gi"
}

variable "job_timeout_seconds" {
  description = "Maximum execution timeout in seconds for the Cloud Run Job"
  type        = number
  default     = 1800 # 30 minutes
}

variable "artifact_registry_repo_id" {
  description = "Repository ID for Artifact Registry storing CodeMender runner images"
  type        = string
  default     = "codemender-runners"
}

# --- Workload Identity Federation (GitHub Actions / Azure Runners) ---

variable "wif_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions"
  type        = string
  default     = "github-actions-pool"
}

variable "wif_provider_id" {
  description = "Workload Identity Provider ID for GitHub Actions OIDC"
  type        = string
  default     = "github-actions-provider"
}

variable "github_owner" {
  description = "GitHub Organization or user account (e.g., my-enterprise-org)"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name allowed to authenticate via WIF (e.g. 'my-app' or '*' for all repos in org)"
  type        = string
  default     = "*"
}

# --- Secrets Management ---

variable "github_token_secret_name" {
  description = "Secret Manager secret ID holding the GitHub App Private Key or GitHub PAT used by Cloud Run to open Pull Requests"
  type        = string
  default     = "codemender-github-token"
}

variable "initial_github_token" {
  description = "Initial GitHub token value for Secret Manager secret version (can be updated later via gcloud or UI)"
  type        = string
  default     = "PLACEHOLDER_SET_ACTUAL_GITHUB_TOKEN"
  sensitive   = true
}

# --- VPC Service Controls (VPC-SC) ---

variable "enable_vpc_sc" {
  description = "Whether to create/enforce a VPC Service Controls perimeter around the CodeMender infrastructure"
  type        = bool
  default     = false
}

variable "access_context_manager_policy_id" {
  description = "The existing Access Context Manager Policy ID (numerical string). Required if enable_vpc_sc is true unless create_access_policy is true."
  type        = string
  default     = ""
}

variable "create_access_policy" {
  description = "Whether to create a new Access Context Manager policy (requires organization admin permissions and org_id)"
  type        = bool
  default     = false
}

variable "org_id" {
  description = "Google Cloud Organization ID (numerical). Required if create_access_policy is true."
  type        = string
  default     = ""
}
