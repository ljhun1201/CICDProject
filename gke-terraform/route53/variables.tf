variable "lb_ip_address" {
  description = "Static IP of the GCP HTTP(S) Load Balancer"
  type        = string
}

variable "ingress_ip" {
  description = "Static IP of Ingress"
  type        = string
}