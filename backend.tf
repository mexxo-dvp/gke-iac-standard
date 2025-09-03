terraform {
  backend "gcs" {
    bucket = "tf-state-civil-pattern-466501-m8"
    prefix = "gke-iac/terraform-state"
  }
}
