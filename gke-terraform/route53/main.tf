provider "aws" {
  region = "us-east-1"  # Route 53은 특정 리전과 무관하지만, us-east-1로 설정
}

terraform { #테라폼의 전역적 구성을 정의하는 블록
  backend "s3" {
    bucket = "terraformstorage3"  # S3 버킷 이름
    key    = "terraform/terraform.tfstate"  # S3 버킷 내에 저장될 경로
    region = "ap-northeast-2"              # S3 버킷이 있는 리전
    dynamodb_table = "terraform-lock"      # 이건 dynamodb 생성이 이미 되어있어야됨. 그래서 테라폼 resource 블록을 써서 dynamodb를 이거를 실행함과 동시에 실행하면 에러떠서 그냥 dynamodb는 aws cloudshell 명령어로 미리 생성해둠
  }
}

# Hosted Zone 가져오기 (이미 존재하는 Hosted Zone ID를 사용)
data "aws_route53_zone" "main_zone" {
  name         = "ljhun.shop."
  private_zone = false
}

resource "aws_route53_record" "frontend_alias_gcp_www" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "www.ljhun.shop"
  type    = "A"

  # GCP LB IP 가져오기 (Remote State)
  records = [var.lb_ip_address]
  ttl     = 300
}

resource "aws_route53_record" "frontend_alias_gcp" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "ljhun.shop"
  type    = "A"

  # GCP LB IP 가져오기 (Remote State)
  records = [var.lb_ip_address]
  ttl     = 300
}

resource "aws_route53_record" "api_a_record" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "api.ljhun.shop"
  type    = "A"
  ttl     = 300
  records = [var.ingress_ip] 
}