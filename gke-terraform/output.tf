output "cloud_sql_private_ip" {
  value = module.cloud_sql.db_private_ip
}

output "cloud_sql_db_name" {
  description = "Cloud SQL Database Name"
  value       = module.cloud_sql.cloud_sql_db_name
}

output "cloud_sql_user" {
  description = "Cloud SQL User (root)"
  value       = module.cloud_sql.cloud_sql_user
}

output "ingress_ip" {
  description = "Ingress LB IP"
  value       = module.k8s_deploy.ingress_ip
}

output "lb_ip_address" {
  description = "GCS LB IP"
  value = module.storage_and_lb.lb_ip_address
}

output "gcp_vpc_id" {
  value = module.network.gcp_vpc_id
}

output "ingress_dns" {
  value = module.k8s_deploy.ingress_dns
}