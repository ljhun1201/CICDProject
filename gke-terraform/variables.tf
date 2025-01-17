variable "project_id" {
  type        = string
  default = "peppy-arcadia-432311-g5"
  description = "GCP Project ID"
}

variable "region" {
  type    = string
  default = "asia-northeast3"  # Seoul region
}

variable "vpc_name" {
  type    = string
  default = "gcp-dr-vpc"
}

variable "cluster_name" {
  type    = string
  default = "gcp-dr-gke"
}

variable "db_name" {
  type    = string
  default = "mydb"
}

variable "db_password" {
  type        = string
  description = "Cloud SQL root/admin password"
  default = "hi8857036"
}

variable "domain_name" {
  type        = string
  description = "Main domain, e.g. ljhun.shop"
  default = "ljhun.shop"
}

variable "domain_name_www" {
  type        = string
  description = "WWW domain, e.g. www.ljhun.shop"
  default = "www.ljhun.shop"
}

variable "gcs_bucket_name" {
  type        = string
  description = "Name of GCS bucket for hosting static files"
  default     = "shoppingwebfrontend-gcp"
}

variable "app_one_image" {
  type        = string
  default     = "gcr.io/my-project/user-registration-service:latest"
}
variable "app_two_image" {
  type        = string
  default     = "gcr.io/my-project/user-login-service:latest"
}