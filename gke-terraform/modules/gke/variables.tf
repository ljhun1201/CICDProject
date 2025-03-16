variable "project_id" {}
variable "region" {}
variable "cluster_name" {}
variable "network_name" {}
variable "subnetwork_name" {}
variable "zones" {
  type = list(string)
  default = ["asia-northeast3-a", "asia-northeast3-b"]
}
