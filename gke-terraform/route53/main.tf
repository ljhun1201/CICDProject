provider "aws" {
  region = "us-east-1"  # Route 53은 특정 리전과 무관하지만, us-east-1로 설정
}

# Hosted Zone 가져오기 (이미 존재하는 Hosted Zone ID를 사용)
data "aws_route53_zone" "main_zone" {
  name         = "ljhun.shop."
  private_zone = false
}

# A 레코드 설정: GCP HTTP(S) LB의 Static IP로 설정
resource "aws_route53_record" "a_record" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "ljhun.shop"
  type    = "A"
  ttl     = 300
  records = [var.lb_ip_address]  # GCP LB Static IP를 변수로 설정
}

resource "aws_route53_record" "www_a_record" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "www.ljhun.shop"
  type    = "A"
  ttl     = 300
  records = [var.lb_ip_address]
}

resource "aws_route53_record" "api_a_record" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "api.ljhun.shop"
  type    = "A"
  ttl     = 300
  records = [var.ingress_ip] 
}