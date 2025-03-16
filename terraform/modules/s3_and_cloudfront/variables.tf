variable "alb_dns_name" {
  description = "The DNS name of the ALB to be used as the origin for CloudFront."
  type        = string
}

variable "rds_endpoint" {
  description = "RDS instance endpoint"
  type        = string
}