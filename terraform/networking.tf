# VPC Network
resource "google_compute_network" "codemender_vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  project                 = var.project_id
  description             = "Dedicated VPC for CodeMender CI/CD execution and Cloud Run Direct VPC Egress"
  depends_on              = [google_project_service.enabled_apis]
}

# Subnet for Cloud Run Direct VPC Egress
resource "google_compute_subnetwork" "codemender_subnet" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.codemender_vpc.id
  project                  = var.project_id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Proxy-only Subnet (Only created if Internal Application Load Balancer is enabled)
resource "google_compute_subnetwork" "proxy_only_subnet" {
  count         = var.enable_internal_load_balancer ? 1 : 0
  name          = "${var.subnet_name}-proxy-only"
  ip_cidr_range = var.ilb_subnet_cidr
  region        = var.region
  network       = google_compute_network.codemender_vpc.id
  project       = var.project_id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# --- Optional Cloud NAT & Cloud Router for Outbound Internet Egress ---

resource "google_compute_router" "nat_router" {
  count   = var.create_cloud_nat ? 1 : 0
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.codemender_vpc.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat_gateway" {
  count                              = var.create_cloud_nat ? 1 : 0
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.nat_router[0].name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.codemender_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- Optional Internal Application Load Balancer (for private Azure -> GCP invocation) ---

resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  count                 = var.enable_internal_load_balancer ? 1 : 0
  name                  = "codemender-serverless-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  project               = var.project_id

  cloud_run {
    service = var.cloud_run_job_name
  }
}

resource "google_compute_region_backend_service" "ilb_backend" {
  count                 = var.enable_internal_load_balancer ? 1 : 0
  name                  = "codemender-ilb-backend"
  region                = var.region
  project               = var.project_id
  protocol              = "HTTPS"
  load_balancing_scheme = "INTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg[0].id
  }
}

resource "google_compute_region_url_map" "ilb_url_map" {
  count           = var.enable_internal_load_balancer ? 1 : 0
  name            = "codemender-ilb-url-map"
  region          = var.region
  project         = var.project_id
  default_service = google_compute_region_backend_service.ilb_backend[0].id
}

resource "google_compute_region_target_http_proxy" "ilb_target_proxy" {
  count   = var.enable_internal_load_balancer ? 1 : 0
  name    = "codemender-ilb-proxy"
  region  = var.region
  project = var.project_id
  url_map = google_compute_region_url_map.ilb_url_map[0].id
}

resource "google_compute_forwarding_rule" "ilb_forwarding_rule" {
  count                 = var.enable_internal_load_balancer ? 1 : 0
  name                  = "codemender-ilb-forwarding-rule"
  region                = var.region
  project               = var.project_id
  ip_protocol           = "TCP"
  port_range            = "80"
  load_balancing_scheme = "INTERNAL_MANAGED"
  network               = google_compute_network.codemender_vpc.id
  subnetwork            = google_compute_subnetwork.codemender_subnet.id
  target                = google_compute_region_target_http_proxy.ilb_target_proxy[0].id
  depends_on            = [google_compute_subnetwork.proxy_only_subnet]
}
