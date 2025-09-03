variable "GOOGLE_PROJECT" {
  type    = string
  default = "civil-pattern-466501-m8"
}

variable "GOOGLE_REGION" {
  type    = string
  default = "europe-west1"
}

variable "GOOGLE_LOCATION" {
  type    = string
  default = "europe-west1-b"
}

variable "GKE_CLUSTER_NAME" {
  type    = string
  default = "main"
}

variable "GKE_POOL_NAME" {
  type    = string
  default = "main"
}

variable "GKE_MACHINE_TYPE" {
  type    = string
  default = "g1-small"
}

variable "GKE_NUM_NODES" {
  type    = number
  default = 1
}
