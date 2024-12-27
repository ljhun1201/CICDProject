resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "shoppingwebfrontend"
  
  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  # attribute 'acl' cannot be used if S3`s ObjectOwnerShip is BucketOwnerEnforced
  # Set the entire Get permission if you perform the terraform code.(Very complicated)
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
} # To change public set, you may set s3:PutBucketPublicAccessBlock permission in your role.(more)

# 배열로 파일 정보 관리
locals {
  files = [
    { key = "index.html",  source = "../html/login.html" },
    { key = "signup.html", source = "../html/signup.html" },
    { key = "main.html",   source = "../html/main.html" }
  ]
}

# for_each를 사용하여 여러 파일을 S3에 업로드
resource "aws_s3_bucket_object" "html_files" {
  for_each     = { for file in local.files : file.key => file }
  bucket       = aws_s3_bucket.frontend_bucket.bucket
  key          = each.value.key
  content_type = "text/html"  # HTML MIME type
  source       = each.value.source
}

# Route 53 호스팅 영역 조회(생성: resource)
data "aws_route53_zone" "ljhun_zone" {
  name = "ljhun.shop"  # 도메인 이름 설정
}

/*
# ACM 인증서 생성
resource "aws_acm_certificate" "ljhun_cert" {
  provider          = aws.us_east_1    # us-east-1 리전을 지정한 프로바이더 참조
  domain_name       = "www.ljhun.shop"
  validation_method = "DNS"
  subject_alternative_names = ["ljhun.shop"]

  lifecycle {
    create_before_destroy = true
  }
}

# DNS 검증 레코드 생성
resource "aws_route53_record" "ljhun_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ljhun_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      value  = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.ljhun_zone.id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

# 인증서 검증 완료 대기
resource "aws_acm_certificate_validation" "ljhun_cert_validation" {
  provider               = aws.us_east_1    # ACM 인증서 검증도 us-east-1 리전에서 수행
  certificate_arn         = aws_acm_certificate.ljhun_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.ljhun_cert_validation : record.fqdn]
}
*/

# 기존 ACM 인증서 조회 (동적 참조)
data "aws_acm_certificate" "ljhun_cert" {
  provider          = aws.us_east_1
  domain   = "www.ljhun.shop"     # 인증서에 등록된 도메인 이름
  statuses = ["ISSUED"]           # 발급 완료된 인증서만 조회
}

# CloudFront 배포 설정
resource "aws_cloudfront_distribution" "frontend_distribution" {
  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "S3-frontend"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_identity.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = var.alb_dns_name  # ALB의 DNS 이름
    origin_id   = "Ingress-ALB"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]   # CloudFront와 Origin 간 SSL 프로토콜
    }
  }

  # 나머지 설정은 이전과 동일...
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["ljhun.shop", "www.ljhun.shop"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-frontend"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  ordered_cache_behavior {
    path_pattern     = "/app-one/*"
    target_origin_id = "Ingress-ALB"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  ordered_cache_behavior {
    path_pattern     = "/app-two/*"
    target_origin_id = "Ingress-ALB"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.ljhun_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
}

# CloudFront의 S3 접근 권한 설정
resource "aws_cloudfront_origin_access_identity" "s3_identity" {
  comment = "OAI for S3 frontend bucket"                                      # OAI에 대한 설명
}

# CloudFront의 S3 접근 권한 설정
resource "aws_cloudfront_origin_access_identity" "alb_identity" {
  comment = "OAI for ALB"                                      # OAI에 대한 설명
}

# S3 버킷 정책 업데이트 (CloudFront에 접근 허용)
resource "aws_s3_bucket_policy" "frontend_bucket_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id                                   # S3 버킷 ID

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.s3_identity.iam_arn     # CloudFront OAI의 ARN
        },
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.frontend_bucket.arn}/*"                   # 버킷 내 모든 오브젝트 접근 허용
      }
    ]
  })
}


# Route 53 레코드 설정 (CloudFront를 가리킴)
resource "aws_route53_record" "frontend_alias" {
  zone_id = data.aws_route53_zone.ljhun_zone.zone_id   # Route 53 호스팅 영역 ID
  name    = "www.ljhun.shop"        # 도메인 이름
  type    = "A"                     # 레코드 타입 (A 레코드)

  alias {
    name                   = aws_cloudfront_distribution.frontend_distribution.domain_name  # CloudFront 도메인 이름
    zone_id                = aws_cloudfront_distribution.frontend_distribution.hosted_zone_id  # CloudFront 호스팅 영역 ID
    evaluate_target_health = false                    # 대상 상태 평가 여부 (false로 설정)
  }
}

# Route 53 레코드 설정 (CloudFront를 가리킴)
resource "aws_route53_record" "frontend_alias1" {
  zone_id = data.aws_route53_zone.ljhun_zone.zone_id   # Route 53 호스팅 영역 ID
  name    = "ljhun.shop"        # 도메인 이름
  type    = "A"                     # 레코드 타입 (A 레코드)

  alias {
    name                   = aws_cloudfront_distribution.frontend_distribution.domain_name  # CloudFront 도메인 이름
    zone_id                = aws_cloudfront_distribution.frontend_distribution.hosted_zone_id  # CloudFront 호스팅 영역 ID
    evaluate_target_health = false                    # 대상 상태 평가 여부 (false로 설정)
  }
}