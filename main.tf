############################################################
# 0) Local names
############################################################
locals {
  vpc_name        = "gke-vpc"
  subnet_name     = "gke-subnet"
  pods_range_name = "gke-pods"
  svcs_range_name = "gke-services"
}

############################################################
# 1) VPC + Subnet with secondary ranges (VPC-native GKE)
############################################################
resource "google_compute_network" "vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  name          = local.subnet_name
  ip_cidr_range = "10.10.0.0/20"
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = local.pods_range_name
    ip_cidr_range = "10.20.0.0/14"
  }
  secondary_ip_range {
    range_name    = local.svcs_range_name
    ip_cidr_range = "10.40.0.0/20"
  }
}

############################################################
# 2) GKE Autopilot (regional) + Workload Identity
############################################################
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region

  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.gke.self_link

  release_channel {
    channel = "STABLE"
  }

  # Autopilot is enabled like this (without the autopilot{} block)
  enable_autopilot = true

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.svcs_range_name
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }

  deletion_protection = false
}

############################################################
# 3) kubeconfig via official auth module → local file
############################################################
module "gke_auth_self" {
  source       = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  project_id   = var.project
  location     = var.region
  cluster_name = var.cluster_name

  depends_on = [google_container_cluster.this]
}

resource "local_file" "kubeconfig" {
  content         = module.gke_auth_self.kubeconfig_raw
  filename        = abspath("${path.root}/.kube/gke-${var.cluster_name}.kubeconfig")
  file_permission = "0600"
}

############################################################
# 4) Deploy key (RO) для GitHub
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