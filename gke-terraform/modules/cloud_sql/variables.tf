variable "project_id" {}
variable "region" {}
variable "db_name" {}
variable "db_password" {}
variable "vpc_self_link" {}

variable "user_name" {
  type = string
  default = "root"
}