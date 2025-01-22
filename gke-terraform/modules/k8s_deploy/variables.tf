variable "project_id" {}
variable "gke_cluster_endpoint" {}
variable "gke_cluster_ca_certificate" {}

variable "db_endpoint" {}
variable "db_password" {}
variable "db_name" {
  default = "mydb"
}

variable "domain_name" {
  default = "ljhun.shop"
}

variable "www_domain_name" {
  default = "www.ljhun.shop"
}

variable "app_one_image" {
  default = "asia-northeast3-docker.pkg.dev/peppy-arcadia-432311-g5/app-images/user-registration-service:latest"
}

variable "app_two_image" {
  default = "asia-northeast3-docker.pkg.dev/peppy-arcadia-432311-g5/app-images/user-login-service:latest"
}

variable "cluster_name" {
    type = string
}