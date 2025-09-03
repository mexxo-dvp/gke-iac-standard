terraform {
  backend "gcs" {
    bucket = "tf-state-civil-pattern-466501-m8"  # заміни на назву свого bucket'а
    prefix = "gke-iac/terraform-state"
  }
}
