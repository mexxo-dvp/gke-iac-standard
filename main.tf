############################################################
# main.tf — GKE Standard (zonal) + cost-friendly defaults
# Notes:
# - Separate VPC/Subnet (safety)
# - Workload Identity
# - Small autoscaled node pool (1..2 e2-medium)
############################################################

locals {
  vpc_name        = "gke-vpc-std"
  subnet_name     = "gke-subnet-std"
  pods_range_name = "gke-pods-std"
  svcs_range_name = "gke-services-std"

  subnet_cidr   = "10.60.0.0/20"
  pods_cidr     = "10.80.0.0/14"
  services_cidr = "10.100.0.0/20"

  node_machine_type = "e2-medium"
  node_min_count    = 1
  node_max_count    = 2
  node_disk_gb      = 30
  image_type        = "COS_CONTAINERD"
  use_spot          = false
}

# --- Network ---
resource "google_compute_network" "vpc_std" {
  name                    = local.vpc_name
  auto_create_subnetworks = false

  # Safety net so TF won't nuke the VPC by accident
  lifecycle { prevent_destroy = true }
}

resource "google_compute_subnetwork" "gke_std" {
  name          = local.subnet_name
  ip_cidr_range = local.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_std.id

  secondary_ip_range {
    range_name    = local.pods_range_name
    ip_cidr_range = local.pods_cidr
  }
  secondary_ip_range {
    range_name    = local.svcs_range_name
    ip_cidr_range = local.services_cidr
  }

  # Recommend to keep while migrating; remove when sure
  lifecycle { prevent_destroy = true }
}

# --- Cluster ---
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.zone

  network    = google_compute_network.vpc_std.self_link
  subnetwork = google_compute_subnetwork.gke_std.self_link

  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel { channel = "STABLE" }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.svcs_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }

  deletion_protection = false

  # Avoid downtime if name/settings change in future
  lifecycle {
    create_before_destroy = true
  }
}

# --- Node pool ---
resource "google_container_node_pool" "default" {
  name     = "np-default"
  location = google_container_cluster.this.location
  cluster  = google_container_cluster.this.name

  autoscaling {
    min_node_count = local.node_min_count
    max_node_count = local.node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Rolling upgrades: keep capacity during upgrade
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = local.node_machine_type
    disk_size_gb = local.node_disk_gb
    image_type   = local.image_type

    # If empty, GKE uses default Compute SA (runner must have iam.serviceAccountUser on it)
    service_account = var.node_sa_email != "" ? var.node_sa_email : null

    # Use ONE of the following depending on provider version (kept commented until needed)
    # spot        = local.use_spot
    # preemptible = local.use_spot

    workload_metadata_config { mode = "GKE_METADATA" }
  }

  depends_on = [google_container_cluster.this]

  # Let autoscaler/GKE adjust size without TF fighting back
  lifecycle {
    ignore_changes = [
      # GKE may adjust underlying node_count during autoscaling/upgrade
      node_count
    ]
  }
}

# --- Kubeconfig output via auth module ---
module "gke_auth_self" {
  source       = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  project_id   = var.project
  location     = var.zone
  cluster_name = var.cluster_name

  depends_on = [google_container_cluster.this]
}

resource "local_file" "kubeconfig" {
  content         = module.gke_auth_self.kubeconfig_raw
  filename        = abspath("${path.root}/.kube/gke-${var.cluster_name}.kubeconfig")
  file_permission = "0600"
}

# --- GitHub deploy key (RO) ---
module "tls_private_key" {
  source = "github.com/den-vasyliev/tf-hashicorp-tls-keys"
}

resource "github_repository_deploy_key" "flux_ro_gke" {
  repository = var.github_repo
  title      = "flux-readonly-gke"
  key        = module.tls_private_key.public_key_openssh
  read_only  = true
}
