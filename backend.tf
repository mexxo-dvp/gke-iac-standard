terraform {
  backend "gcs" {
    bucket = "tf-state-fifth-diode-472114-p7"
    prefix = "gke-iac/terraform-state"
  }
}
