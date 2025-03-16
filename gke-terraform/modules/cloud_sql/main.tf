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

    # 백업 및 PITR(포인트 인 타임 리커버리) 설정
    backup_configuration {
      enabled                        = true             # 자동 백업 사용
      start_time                     = "22:00"          # 백업 시작 시간(UTC 기준)
      binary_log_enabled = true             # PITR 활성화
      transaction_log_retention_days = 1                # 로그(트랜잭션) 보관 기간: 1일
    }

    # 백업 보관 기간 설정(현재 지원 하지 않음)
    # backup_retention_settings {
      # retention_unit   = "DAYS"  # DAYS(일 단위), COUNT(백업 개수 단위) 등
      # retained_backups = 7       # 7일 동안 백업 보관
    # }
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