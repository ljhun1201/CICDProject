variable "project_id" {}
variable "region" {}
variable "domain_name" {}
variable "domain_name_www" {}
variable "gcs_bucket_name" {}
variable "vpc_self_link" {}
variable "subnet_self_link" {}

variable "zones" {
  type = list(string)
  description = "List of zones where NEGs will be created"
}

variable "www_domain_name" {
    type = string
    default = "www.ljhun.shop"
}

variable "mig_info" {
  description = "List of MIG names and zones"
  type = list(object({
    name = string
    zone = string
  }))
}

variable "cluster_name" {
    type = string
}

variable "ingress_name" {}
variable "ingress_namespace" {}
variable "neg_app_one" {}
variable "neg_app_two" {}
