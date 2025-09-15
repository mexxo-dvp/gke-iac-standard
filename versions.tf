terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.49" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.49" }
    github      = { source = "integrations/github", version = "~> 6.6" }
    local       = { source = "hashicorp/local", version = "~> 2.5" }
    tls         = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
