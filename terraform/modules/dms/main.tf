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
# Create IAM Role and permission
#####################################################

resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# AWS에서 기본적으로 요구하는 DMS VPC Management 정책 추가
resource "aws_iam_role_policy_attachment" "dms_vpc_management_role" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# DMS VPC 연동을 위한 추가 정책
resource "aws_iam_policy" "dms_vpc_custom_policy" {
  name        = "DMSVPCCustomPolicy"
  description = "Custom policy for AWS DMS to access VPC resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DescribeVpcEndpoints"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:vpc/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:security-group/*"
        ]
      }
    ]
  })
}

# DMS IAM Role에 커스텀 정책 추가
resource "aws_iam_role_policy_attachment" "dms_vpc_custom_policy_attach" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = aws_iam_policy.dms_vpc_custom_policy.arn
}

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

  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc_custom_policy_attach
  ]
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

  lifecycle {
    prevent_destroy = false
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
  endpoint_id   = "cloudsql-target-endpoint"
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
  endpoint_id   = "rds-source-endpoint"
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
  replication_instance_arn = aws_dms_replication_instance.dms_instance.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.cloudsql_source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.rds_target.endpoint_arn

  migration_type           = "cdc"  # CDC or full-load-and-cdc
  table_mappings = <<EOF
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "include-all",
      "object-locator": {
        "schema-name": "mydb", 
        "table-name": "%"     
      },
      "rule-action": "include"
    }
  ]
}
EOF

  replication_task_settings = <<EOF
{
  "Logging": {
    "EnableLogging": true
  },
  "TargetMetadata": {
    "TargetSchema": "",
    "SupportLobs": true
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DO_NOTHING",
    "StopTaskAfterFullLoad": false 
  },
  "ChangeProcessingTuning": {
    "BatchApplyEnabled": true,
    "BatchApplyPreserveTransaction": true,
    "CommitEachTransaction": true, 
    "TransactionConsistencyTimeoutInSeconds": 600 
  },
  "ChangeProcessingDdlHandlingPolicy": {
    "HandleSourceTableDropped": true,
    "HandleSourceTableTruncated": true 
  }
}
EOF
  depends_on = [
    aws_iam_role.dms_vpc_role, 
    aws_iam_role_policy_attachment.dms_vpc_custom_policy_attach,
    aws_dms_replication_subnet_group.this,
    aws_dms_replication_instance.dms_instance
  ]
}

# 반대방향(RDS -> Cloud SQL):
resource "aws_dms_replication_task" "rds_to_cloudsql" { 
  replication_task_id      = "rds-to-cloudsql-task"
  replication_instance_arn = aws_dms_replication_instance.dms_instance.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.rds_source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.cloudsql_target.endpoint_arn

  migration_type           = "cdc"  # CDC or full-load-and-cdc
  table_mappings = <<EOF
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "include-all",
      "object-locator": {
        "schema-name": "mydb",  
        "table-name": "%"      
      },
      "rule-action": "include"
    }
  ]
}
EOF

  replication_task_settings = <<EOF
{
  "Logging": {
    "EnableLogging": true
  },
  "TargetMetadata": {
    "TargetSchema": "",
    "SupportLobs": true
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DO_NOTHING", 
    "StopTaskAfterFullLoad": false 
  },
  "ChangeProcessingDdlHandlingPolicy": {
    "HandleSourceTableDropped": true,
    "HandleSourceTableTruncated": true 
  }
}
EOF
  depends_on = [
    aws_iam_role.dms_vpc_role, 
    aws_iam_role_policy_attachment.dms_vpc_custom_policy_attach,
    aws_dms_replication_subnet_group.this,
    aws_dms_replication_instance.dms_instance
  ]
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
