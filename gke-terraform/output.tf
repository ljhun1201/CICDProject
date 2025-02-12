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