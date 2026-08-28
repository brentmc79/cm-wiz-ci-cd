# ==============================================================================
# Optional GCP Self-Hosted GitHub Actions Runner Compute Engine VM
# ==============================================================================

locals {
  runner_startup_script = <<-EOF
    #!/bin/bash
    set -eo pipefail
    exec > >(tee /var/log/github-runner-init.log|logger -t github-runner-init -s 2>/dev/console) 2>&1

    echo "=========================================================="
    echo " Starting GitHub Actions Self-Hosted Runner Setup in GCP "
    echo "=========================================================="

    # Update system and install required packages
    apt-get update -y
    apt-get install -y --no-install-recommends \
        curl \
        jq \
        git \
        tar \
        build-essential \
        libssl-dev \
        libffi-dev \
        python3 \
        python3-pip \
        ca-certificates \
        gnupg \
        lsb-release

    # Install Docker
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y || true
    apt-get install -y docker-ce docker-ce-cli containerd.io || true
    systemctl enable docker
    systemctl start docker

    # Create non-root runner user
    id -u runner &>/dev/null || useradd -m -s /bin/bash runner
    usermod -aG docker runner || true

    # Download GitHub Actions Runner
    RUNNER_DIR="/home/runner/actions-runner"
    mkdir -p "$RUNNER_DIR"
    cd "$RUNNER_DIR"

    RUNNER_VERSION="2.321.0"
    if [ ! -f "config.sh" ]; then
      echo "Downloading GitHub Actions runner v$${RUNNER_VERSION}..."
      curl -o actions-runner-linux-x64.tar.gz -L "https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"
      tar xzf ./actions-runner-linux-x64.tar.gz
      rm -f actions-runner-linux-x64.tar.gz
      ./bin/installdependencies.sh
      chown -R runner:runner "$RUNNER_DIR"
    fi

    # Register Runner if registration token is provided
    REPO_URL="${var.github_repo_url}"
    REG_TOKEN="${var.github_runner_registration_token}"
    LABELS="${var.github_runner_labels}"

    if [ -n "$REG_TOKEN" ] && [ -n "$REPO_URL" ]; then
      echo "Registering runner against $REPO_URL..."
      sudo -u runner ./config.sh \
        --url "$REPO_URL" \
        --token "$REG_TOKEN" \
        --name "$(hostname)" \
        --labels "$LABELS" \
        --unattended \
        --replace

      # Install and start systemd service
      ./svc.sh install runner
      ./svc.sh start
      echo "GitHub Actions Runner service installed and running."
    else
      echo "WARNING: github_repo_url or github_runner_registration_token not set. Skipping automatic runner registration."
    fi
  EOF
}

resource "google_compute_instance" "gcp_github_runner" {
  count        = var.enable_gcp_runner ? 1 : 0
  name         = "gcp-github-runner-${var.environment}"
  machine_type = var.runner_vm_machine_type
  zone         = var.runner_vm_zone
  project      = var.project_id

  tags = ["github-runner", "codemender-ci-cd"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.runner_vm_disk_size_gb
      type  = "pd-balanced"
    }
  }

  # Network Interface: Attached to private subnet with NO external IP (uses Cloud NAT)
  network_interface {
    network    = google_compute_network.codemender_vpc.id
    subnetwork = google_compute_subnetwork.codemender_subnet.id
    # Note: Omit access_config block so the VM has NO public IP address
  }

  service_account {
    email  = google_service_account.github_runner_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = local.runner_startup_script

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  depends_on = [
    google_compute_subnetwork.codemender_subnet,
    google_compute_router_nat.nat_gateway,
  ]
}
