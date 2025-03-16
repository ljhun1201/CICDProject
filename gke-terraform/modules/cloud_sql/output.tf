output "db_private_ip" {
  value = google_sql_database_instance.mysql_instance.private_ip_address
}
/*
output "sql_instance_name" {
  value = google_sql_database_instance.mysql_instance.name
}
*/
output "cloud_sql_db_name" {
  description = "Cloud SQL Database Name"
  value       = var.db_name
}

output "cloud_sql_user" {
  description = "Cloud SQL User (root)"
  value       = var.user_name
}