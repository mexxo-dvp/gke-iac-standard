terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.36, < 7.0"
    }
  }
}

provider "google" {
  project = var.GOOGLE_PROJECT
  region  = var.GOOGLE_REGION
}

module "gke_cluster" {
  source = "github.com/mexxo-dvp/tf-google-gke-cluster"

  GOOGLE_PROJECT  = var.GOOGLE_PROJECT
  GOOGLE_REGION   = var.GOOGLE_REGION
  GOOGLE_LOCATION = var.GOOGLE_LOCATION

  GKE_CLUSTER_NAME = var.GKE_CLUSTER_NAME
  GKE_POOL_NAME    = var.GKE_POOL_NAME
  GKE_MACHINE_TYPE = var.GKE_MACHINE_TYPE
  GKE_NUM_NODES    = var.GKE_NUM_NODES
}
