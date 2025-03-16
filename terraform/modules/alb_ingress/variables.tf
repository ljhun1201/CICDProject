variable "vpc_id" {}
variable "private_subnet_ids" {}
variable "public_subnet_ids" {}
variable "eks_cluster_name" {}
variable "eks_cluster_endpoint" {}
variable "eks_cluster_ca" {}
variable "eks_auth" {}
variable "oidc_issuer_url" {}
variable "alb_security_group_id" {}

variable "db_endpoint" {
  type = string
}

variable "db_password" {
  type = string
}