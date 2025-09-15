#############################
# variables.tf (Autopilot + WI)
#############################

variable "project" {
  type        = string
  description = "GCP Project ID (e.g., fifth-diode-472114-p7)"
}

variable "region" {
  type        = string
  description = "GCP region (e.g., europe-west1)"
  default     = "europe-west1"
}

variable "zone" {
  type        = string
  description = "Optional GCP zone (e.g., europe-west1-b) for tools/compat"
  default     = "europe-west1-b"
}

variable "cluster_name" {
  type        = string
  description = "GKE Autopilot cluster name"
  default     = "gke-flux"
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
  description = "GitHub PAT (classic) with repo scope for bootstrap (use ONLY if you enable TF bootstrap)"
  sensitive   = true
  default     = ""
}

variable "flux_path" {
  type        = string
  description = "Path in the GitOps repo for cluster manifests"
  default     = "clusters/gke"
}

variable "enable_flux_bootstrap" {
  type        = bool
  description = "Run Flux bootstrap from Terraform (first-time only). Default=false — use CLI-bootstrap in CI."
  default     = false
}
