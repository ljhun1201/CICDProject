#####################################################
# (A) Terraform & Providers
#####################################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
  required_version = ">= 1.3.0"
}

#####################################################
# (B) Remote State to get Cloud SQL Info
#####################################################
data "terraform_remote_state" "gcp_cloudsql" {
  backend = "gcs"
  config = {
    bucket = "my-terraform-db-info"  # gke/main.tf에서 선언한 것과 동일
    prefix = "cloudsql-state"        # gke/main.tf의 prefix와 동일
  }
}

# 이제 data.terraform_remote_state.gcp_cloudsql.outputs.cloud_sql_private_ip 를 사용할 수 있음
# => Cloud SQL private IP

#####################################################
# (C) VPC Subnet & Security Groups for DMS
#####################################################
# DMS를 놓을 Subnet Group 등 (이미 있다면 가져다 쓰기)
# 예를 들어, EKS와 같은 VPC/Subnet에 DMS를 띄운다고 가정
resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id = "my-dms-subnet-group"
  replication_subnet_group_description = "My DMS Subnet Group"

  subnet_ids                  = var.private_subnet_ids  # 예) AWS private 서브넷 ID들
  tags = {
    Name = "my-dms-subnet-group"
  }
}

resource "aws_security_group" "dms_sg" {
  name   = "dms-sg"
  vpc_id = var.vpc_id

  # DMS -> RDS(MySQL:3306), DMS -> Cloud SQL(3306) 접속 허용
  # 실제로는 NAT등을 거쳐 GCP로 가야 하므로, VPN/DirectConnect/VpcPeering 필요.
  # 여기서는 간단히 "0.0.0.0/0" 예시
  ingress {
    description = "Allow MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "dms-sg"
  }
}

#####################################################
# (D) Replication Instance
#####################################################
resource "aws_dms_replication_instance" "dms_instance" {
  replication_instance_id    = "my-dms-instance"
  replication_instance_class = "dms.t3.medium"
  allocated_storage          = 50

  replication_subnet_group_id = aws_dms_replication_subnet_group.this.replication_subnet_group_id
  vpc_security_group_ids       = [aws_security_group.dms_sg.id]
  
  publicly_accessible = false
  tags = {
    Name = "MyDmsInstance"
  }
}

#####################################################
# (E) DMS Endpoints
#####################################################

# 1) Cloud SQL Endpoint (source)
resource "aws_dms_endpoint" "cloudsql_source" {
  endpoint_id   = "cloudsql-source-endpoint"
  endpoint_type = "source"  # or "target"
  engine_name   = "mysql"

  server_name = data.terraform_remote_state.gcp_cloudsql.outputs.cloud_sql_private_ip
  port        = 3306
  username    = data.terraform_remote_state.gcp_cloudsql.outputs.cloud_sql_user
  password    = var.cloudsql_password   # GCP 쪽 root 비밀번호 (민감정보)
  ssl_mode    = "none"
}

# 2) RDS MySQL Endpoint (target)
resource "aws_dms_endpoint" "rds_target" {
  endpoint_id   = "rds-target-endpoint"
  endpoint_type = "target"
  engine_name   = "mysql"

  server_name = var.rds_endpoint    # ex) aws_db_instance.mydb.endpoint
  port        = 3306
  username    = var.rds_user_name
  password    = var.rds_password
  ssl_mode    = "none"
}

# 3) Cloud SQL Endpoint (target)
resource "aws_dms_endpoint" "cloudsql_target" {
  endpoint_id   = "cloudsql-source-endpoint"
  endpoint_type = "target"
  engine_name   = "mysql"

  server_name = data.terraform_remote_state.gcp_cloudsql.outputs.cloud_sql_private_ip
  port        = 3306
  username    = data.terraform_remote_state.gcp_cloudsql.outputs.cloud_sql_user
  password    = var.cloudsql_password   # GCP 쪽 root 비밀번호 (민감정보)
  ssl_mode    = "none"
}

# 4) RDS MySQL Endpoint (source)
resource "aws_dms_endpoint" "rds_source" {
  endpoint_id   = "rds-target-endpoint"
  endpoint_type = "source"
  engine_name   = "mysql"

  server_name = var.rds_endpoint    # ex) aws_db_instance.mydb.endpoint
  port        = 3306
  username    = var.rds_user_name
  password    = var.rds_password
  ssl_mode    = "none"
}

#####################################################
# (F) Replication Task
#####################################################
# Cloud SQL -> RDS
# 참고: DMS는 '양방향 동기화' 시, 완벽한 동기화가 어려움(트랜잭션 처리 순서 문제 때문)
# 즉, Mirror Site를 포기하고, Hot Site를 시도해볼 예정
# Hot Site에서는 AWS를 주 인프라로, GCP를 DR로 하고 FailOver 방식으로 Route 53 설정 뒤, DMS는 단방향 동기화 예정(양방향이 필요하긴 하겠지만, GCP는 DR이므로 Mirror Site와 같은 트랜잭션 문제는 없을 것으로 예상)
resource "aws_dms_replication_task" "cloudsql_to_rds" {
  replication_task_id      = "cloudsql-to-rds-task"
  replication_instance_arn = aws_dms_replication_instance.dms_instance.id
  source_endpoint_arn      = aws_dms_endpoint.cloudsql_source.id
  target_endpoint_arn      = aws_dms_endpoint.rds_target.id

  migration_type           = "cdc"  # CDC or full-load-and-cdc
  table_mappings = <<EOF
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "include-all",
      "object-locator": {
        "schema-name": "mydb",  # 특정 데이터베이스(mydb)만 포함
        "table-name": "%"       # 모든 테이블 포함
      },
      "rule-action": "include"
    }
  ]
}
EOF

  cdc_start_position = "now" # CDC 즉시 시작

  replication_task_settings = <<EOF
{
  "TargetMetadata": {
    "TargetSchema": "mydb",
    "SupportLobs": true
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DO_NOTHING", # RDS의 테이블을 변경하지 않고 데이터만 동기화
    "StopTaskAfterFullLoad": false # 초기에 모든 데이터를 복제한 후 변경 사항까지 계속 동기화(CDC 사용을 위해선 무조건 false)
  },
  "ChangeProcessingTuning": {
    "BatchApplyEnabled": true, # batch 모드(트랜잭션을 모아서 한꺼번에 commit) 적용
    "BatchApplyPreserveTransaction": true, # 'batch 모드 적용 시'에 사용. batch 모드에서 트랜잭션을 모을 때 트랜잭션이 뒤섞이지 않도록 '트랜잭션의 경계'를 지켜줌.
    "CommitEachTransaction": true, # 병렬 처리 과정에서 먼저 끝난 트랜잭션은 즉시 commit 되도록 함.
    "TransactionConsistencyTimeoutInSeconds": 600 # 트랜잭션 batch(트랜잭션을 batch로 처리하는 것)를 기다려주는 시간
  },
  "ChangeProcessingDdlHandlingPolicy": {
    "HandleSourceTableDropped": true, # Cloud SQL에서 테이블 삭제 시, RDS에서도 삭제
    "HandleSourceTableTruncated": true # Cloud SQL에서 Truncate 발생 시, RDS에서도 반영
  }
}
EOF
  depends_on = [aws_dms_replication_instance.dms_instance]
}

# 반대방향(RDS -> Cloud SQL):
resource "aws_dms_replication_task" "rds_to_cloudsql" { 
  replication_task_id      = "rds-to-cloudsql-task"
  replication_instance_arn = aws_dms_replication_instance.dms_instance.id
  source_endpoint_arn      = aws_dms_endpoint.rds_source.id
  target_endpoint_arn      = aws_dms_endpoint.cloudsql_target.id

  migration_type           = "cdc"  # CDC or full-load-and-cdc
  table_mappings = <<EOF
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "include-all",
      "object-locator": {
        "schema-name": "mydb",  # 특정 데이터베이스(mydb)만 포함
        "table-name": "%"       # 모든 테이블 포함
      },
      "rule-action": "include"
    }
  ]
}
EOF

  cdc_start_position = "now" # CDC 즉시 시작

  replication_task_settings = <<EOF
{
  "TargetMetadata": {
    "TargetSchema": "mydb",
    "SupportLobs": true
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DO_NOTHING", # RDS의 테이블을 변경하지 않고 데이터만 동기화
    "StopTaskAfterFullLoad": false # 초기에 모든 데이터를 복제한 후 변경 사항까지 계속 동기화(CDC 사용을 위해선 무조건 false)
  },
  "ChangeProcessingDdlHandlingPolicy": {
    "HandleSourceTableDropped": true, # Cloud SQL에서 테이블 삭제 시, RDS에서도 삭제
    "HandleSourceTableTruncated": true # Cloud SQL에서 Truncate 발생 시, RDS에서도 반영
  }
}
EOF
  depends_on = [aws_dms_replication_instance.dms_instance]
}

#####################################################
# (G) Outputs
#####################################################
output "dms_instance_arn" {
  value = aws_dms_replication_instance.dms_instance.id
}

output "cloudsql_source_endpoint_arn" {
  value = aws_dms_endpoint.cloudsql_source.id
}

output "cloudsql_to_rds_task_id" {
  value = aws_dms_replication_task.cloudsql_to_rds.replication_task_id
}
