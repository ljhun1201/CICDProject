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
      ipv4_enabled    = false
      private_network = var.vpc_self_link  # 여기서는 단순히 어떤 VPC와 peering 할 것인지 지정
    }
  }
}

resource "google_sql_database" "default_db" {
  name     = var.db_name
  instance = google_sql_database_instance.mysql_instance.name
}

resource "google_sql_user" "root_user" {
  name       = "root"
  instance   = google_sql_database_instance.mysql_instance.name
  password   = var.db_password
  host       = "%"
}