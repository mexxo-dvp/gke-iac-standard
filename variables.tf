#############################
# variables.tf (Standard GKE + WI)
#############################

variable "project" {
  type        = string
  description = "GCP Project ID (e.g., fifth-diode-472114-p7)"
}

variable "region" {
  type        = string
  description = "GCP region used for networking and regional resources (e.g., europe-west1)"
  default     = "europe-west1"
}

variable "zone" {
  type        = string
  description = "GCP zone for the zonal Standard cluster (e.g., europe-west1-b)"
  default     = "europe-west1-b"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name (Standard, zonal)"
  default     = "gke-flux-std"
}

# --- Flux / GitHub ---
variable "github_owner" {
  type        = string
  description = "GitHub owner/org"
  default     = "mexxo-dvp"
}

variable "github_repo" {
  type        = string
  description = "GitOps repository name"
  default     = "gitops"
}

variable "github_token" {
  type        = string
  description = "GitHub PAT (classic) with repo scope (used by Terraform GitHub provider if enabled)"
  sensitive   = true
  default     = ""
}

variable "flux_path" {
  type        = string
  description = "Path in the GitOps repo for cluster manifests"
  default     = "clusters/gke"
}
