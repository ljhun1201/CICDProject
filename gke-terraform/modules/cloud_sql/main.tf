# MySQL 8.0
resource "google_sql_database_instance" "mysql_instance" {
  name             = "${var.db_name}-instance"
  project          = var.project_id
  region           = var.region
  database_version = "MYSQL_8_0"
  deletion_protection = false

  settings {
    tier = "db-f1-micro"   # 테스트용 스펙
    ip_configuration {
      ipv4_enabled    = false # 퍼블릭 IP 비활성화
      private_network = var.vpc_self_link  # VPC와 peering
    }
  }
}

resource "google_sql_database" "default_db" {
  name     = var.db_name
  instance = google_sql_database_instance.mysql_instance.name
}

resource "google_sql_user" "root_user" {
  name       = var.user_name
  instance   = google_sql_database_instance.mysql_instance.name
  password   = var.db_password
  host       = "%"
}