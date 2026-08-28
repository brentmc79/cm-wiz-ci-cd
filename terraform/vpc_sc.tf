# Access Context Manager Policy (Optional creation if organization policy doesn't already exist)
resource "google_access_context_manager_access_policy" "custom_policy" {
  count  = var.enable_vpc_sc && var.create_access_policy ? 1 : 0
  parent = "organizations/${var.org_id}"
  title  = "CodeMender Security Policy"
}

locals {
  access_policy_id = var.create_access_policy ? (
    length(google_access_context_manager_access_policy.custom_policy) > 0 ? google_access_context_manager_access_policy.custom_policy[0].name : ""
  ) : var.access_context_manager_policy_id
}

# VPC Service Controls Perimeter for CodeMender
resource "google_access_context_manager_service_perimeter" "codemender_perimeter" {
  count  = var.enable_vpc_sc && local.access_policy_id != "" ? 1 : 0
  parent = "accessPolicies/${local.access_policy_id}"
  name   = "accessPolicies/${local.access_policy_id}/servicePerimeters/codemender_secure_perimeter"
  title  = "CodeMender Secure Perimeter"

  status {
    restricted_services = [
      "run.googleapis.com",
      "storage.googleapis.com",
      "artifactregistry.googleapis.com",
      "secretmanager.googleapis.com",
      "aiplatform.googleapis.com",
      "logging.googleapis.com",
    ]

    resources = [
      "projects/${var.project_id}",
    ]

    vpc_accessible_services {
      enable_restriction = true
      allowed_services = [
        "run.googleapis.com",
        "storage.googleapis.com",
        "artifactregistry.googleapis.com",
        "secretmanager.googleapis.com",
        "aiplatform.googleapis.com",
        "logging.googleapis.com",
      ]
    }

    # Egress rule allowing Cloud Run runtime SA to reach external CodeMender/Gemini APIs if needed
    egress_policies {
      egress_from {
        identity_type = "ANY_IDENTITY"
      }
      egress_to {
        resources = ["*"]
        operations {
          service_name = "aiplatform.googleapis.com"
          method_selectors {
            method = "*"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.enabled_apis
  ]
}
