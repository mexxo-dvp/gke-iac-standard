#############################
# providers.tf
#############################

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}
