output "db_private_ip" {
  value = google_sql_database_instance.mysql_instance.private_ip_address
}

output "sql_instance_name" {
  value = google_sql_database_instance.mysql_instance.name
}