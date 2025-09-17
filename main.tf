############################################################
# main.tf — GKE Standard (zonal) + cost-friendly defaults
# Notes:
# - Uses a separate VPC/Subnet
# - Keeps Workload Identity
# - Manages a small autoscaled node pool (1..2 e2-medium)
############################################################

############################################################
# 0) Locals (network names, ranges, cost knobs)
############################################################
locals {
  # New, separate network (avoid collisions with old one)
  vpc_name        = "gke-vpc-std"
  subnet_name     = "gke-subnet-std"
  pods_range_name = "gke-pods-std"
  svcs_range_name = "gke-services-std"

  # Non-overlapping CIDRs (adjust if they collide in your org)
  subnet_cidr   = "10.60.0.0/20"
  pods_cidr     = "10.80.0.0/14"
  services_cidr = "10.100.0.0/20"

  # Cost knobs (keep small & stable)
  node_machine_type = "e2-medium" # 2 vCPU / 4 GB — safe baseline
  node_min_count    = 1           # keep 1 node for system pods
  node_max_count    = 2           # light burst
  node_disk_gb      = 30
  image_type        = "COS_CONTAINERD"
  use_spot          = false # set true only if OK with evictions
}

############################################################
# 1) VPC + Subnet with secondary ranges (VPC-native GKE)
############################################################
resource "google_compute_network" "vpc_std" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  # lifecycle { prevent_destroy = true } # optional safety
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

  # lifecycle { prevent_destroy = true } # optional safety
}

############################################################
# 2) GKE Standard (zonal) + Workload Identity
############################################################
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  # Zonal = cheaper; if you need regional HA, change to var.region
  location = var.zone

  network    = google_compute_network.vpc_std.self_link
  subnetwork = google_compute_subnetwork.gke_std.self_link

  # Remove default pool; manage our own node pool below
  remove_default_node_pool = true
  initial_node_count       = 1 # required by API

  release_channel {
    channel = "STABLE"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.svcs_range_name
  }

  # Workload Identity (cluster part)
  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }

  deletion_protection = false

  # lifecycle {
  #   create_before_destroy = true  # useful when renaming clusters
  # }
}

# Managed node pool (on-demand by default; tiny & autoscaled)
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

  node_config {
    machine_type = local.node_machine_type
    disk_size_gb = local.node_disk_gb
    image_type   = local.image_type

    # Use dedicated node service account if provided; otherwise default Compute SA is used by GKE
    # (if left empty, your TF runner must have iam.serviceAccountUser on the default Compute SA)
    service_account = var.node_sa_email != "" ? var.node_sa_email : null

    # Aggressive savings (eviction risk). Use ONE of the following depending on provider version.
    # spot        = local.use_spot     # newer provider attribute

    # Workload Identity (node part) — required on Standard
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  depends_on = [google_container_cluster.this]
}

############################################################
# 3) kubeconfig via official auth module → local file
# NOTE: The auth module reads the cluster via data source.
# Apply in two steps:
#   a) create cluster & node pool (targeted)
#   b) full apply to render kubeconfig
############################################################
module "gke_auth_self" {
  source       = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  project_id   = var.project
  location     = var.zone # zonal cluster
  cluster_name = var.cluster_name

  depends_on = [google_container_cluster.this]
}

resource "local_file" "kubeconfig" {
  content         = module.gke_auth_self.kubeconfig_raw
  filename        = abspath("${path.root}/.kube/gke-${var.cluster_name}.kubeconfig")
  file_permission = "0600"
}

############################################################
# 4) GitHub deploy key (RO)
############################################################
module "tls_private_key" {
  source = "github.com/den-vasyliev/tf-hashicorp-tls-keys"
}

resource "github_repository_deploy_key" "flux_ro_gke" {
  repository = var.github_repo
  title      = "flux-readonly-gke"
  key        = module.tls_private_key.public_key_openssh
  read_only  = true
}
