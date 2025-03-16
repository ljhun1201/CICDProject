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
data "terraform_remote_state" "gcp" {
  backend = "gcs"
  config = {
    bucket = "my-terraform-db-info"  # gke/main.tf에서 선언한 것과 동일
    prefix = "cloudsql-state"        # gke/main.tf의 prefix와 동일
  }
}

#####################################################

#####################################################

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
    { key = "login.html",  source = "../html/login.html" },
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

# 기존 ACM 인증서 조회 (동적 참조)
data "aws_acm_certificate" "ljhun_cert" {
  provider          = aws.us_east_1
  domain   = "www.ljhun.shop"     # 인증서에 등록된 도메인 이름
  statuses = ["ISSUED"]           # 발급 완료된 인증서만 조회
}

# 기존 ACM 인증서 조회 (동적 참조)
data "aws_acm_certificate" "ljhun_api" {
  provider          = aws.us_east_1
  domain   = "api.ljhun.shop"     # 인증서에 등록된 도메인 이름
  statuses = ["ISSUED"]           # 발급 완료된 인증서만 조회
}

# CloudFront Cache Policy 리소스 생성
resource "aws_cloudfront_cache_policy" "cache_policy_with_default" {
  name = "cache-policy-with-default"

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip = true
    enable_accept_encoding_brotli = true

    headers_config {
      header_behavior = "none"
    }

    cookies_config {
      cookie_behavior = "all"
    }

    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

# CloudFront Origin Request Policy 리소스 생성
resource "aws_cloudfront_origin_request_policy" "origin_request_policy_with_host" {
  name = "origin-request-policy-with-host"

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = ["Host"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }

  cookies_config {
    cookie_behavior = "all"
  }
}

resource "aws_cloudfront_distribution" "frontend_distribution" {
  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "S3-frontend"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_identity.cloudfront_access_identity_path
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  default_root_object = "login.html"
  aliases             = ["ljhun.shop", "www.ljhun.shop"]

  default_cache_behavior {
    target_origin_id = "S3-frontend"

    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    
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

  # 추가 path-based rule이 필요 없으면 ordered_cache_behavior는 생략
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

resource "aws_cloudfront_distribution" "backend_distribution" {
  origin {
    # ALB 오리진 (백엔드 Pod/Ingress)
    domain_name = var.alb_dns_name  # ALB DNS
    origin_id   = "ALB"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  aliases = ["api.ljhun.shop"]

  # (1) Default behavior: 
  #   - 나머지 경로(/), /admin/*, /random/* 등은 여기로 매핑
  #   - ALB가 404 또는 API 응답
  default_cache_behavior {
    target_origin_id = "ALB"

    allowed_methods  = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods   = ["GET","HEAD"]

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # (2) ordered_cache_behavior: "/app-one/*" → ALB
  ordered_cache_behavior {
    path_pattern     = "/app-one/*"
    target_origin_id = "ALB"

    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods         = ["GET","HEAD"]

    # 캐시/오리진 요청 정책
    cache_policy_id          = aws_cloudfront_cache_policy.cache_policy_with_default.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.origin_request_policy_with_host.id

    min_ttl    = 0
    default_ttl = 3600
    max_ttl    = 86400
  }

  # (3) ordered_cache_behavior: "/app-two/*" → ALB
  ordered_cache_behavior {
    path_pattern     = "/app-two/*"
    target_origin_id = "ALB"

    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods         = ["GET","HEAD"]

    cache_policy_id          = aws_cloudfront_cache_policy.cache_policy_with_default.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.origin_request_policy_with_host.id

    min_ttl    = 0
    default_ttl = 3600
    max_ttl    = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  ordered_cache_behavior {
    path_pattern     = "/healthz"
    target_origin_id = "ALB"

    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods         = ["GET","HEAD"]

    # 캐시/오리진 요청 정책
    cache_policy_id          = aws_cloudfront_cache_policy.cache_policy_with_default.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.origin_request_policy_with_host.id

    min_ttl    = 0
    default_ttl = 3600
    max_ttl    = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.ljhun_api.arn
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

  set_identifier = "www-aws-front-endpoint"
  allow_overwrite = true
  
  weighted_routing_policy {
    weight = 50
  }

  alias {
    name                   = aws_cloudfront_distribution.frontend_distribution.domain_name  # CloudFront 도메인 이름
    zone_id                = aws_cloudfront_distribution.frontend_distribution.hosted_zone_id  # CloudFront 호스팅 영역 ID
    evaluate_target_health = false                    # 대상 상태 평가 여부 (false로 설정)
  }
}

resource "aws_route53_record" "frontend_alias_gcp" {
  zone_id = data.aws_route53_zone.ljhun_zone.zone_id
  name    = "www.ljhun.shop"
  type    = "A"

  set_identifier = "www-gcp-lb"
  allow_overwrite = true
  
  weighted_routing_policy {
    weight = 50 
  }


  # GCP LB IP 가져오기 (Remote State)
  records = [data.terraform_remote_state.gcp.outputs.lb_ip_address]
  ttl     = 300
}

# Route 53 레코드 설정 (CloudFront를 가리킴)
resource "aws_route53_record" "frontend_alias1" {
  zone_id = data.aws_route53_zone.ljhun_zone.zone_id   # Route 53 호스팅 영역 ID
  name    = "ljhun.shop"        # 도메인 이름
  type    = "A"                     # 레코드 타입 (A 레코드)
  
  set_identifier = "aws-front-endpoint"
  allow_overwrite = true
  
  weighted_routing_policy {
    weight = 50
  }


  alias {
    name                   = aws_cloudfront_distribution.frontend_distribution.domain_name  # CloudFront 도메인 이름
    zone_id                = aws_cloudfront_distribution.frontend_distribution.hosted_zone_id  # CloudFront 호스팅 영역 ID
    evaluate_target_health = false                    # 대상 상태 평가 여부 (false로 설정)
  }
}

resource "aws_route53_record" "frontend_alias1_gcp" {
  zone_id = data.aws_route53_zone.ljhun_zone.zone_id
  name    = "ljhun.shop"
  type    = "A"

  set_identifier = "gcp-lb"
  allow_overwrite = true
  
  weighted_routing_policy {
    weight = 50
  }


  # GCP LB IP 가져오기 (Remote State)
  records = [data.terraform_remote_state.gcp.outputs.lb_ip_address]
  ttl     = 300
}

resource "aws_route53_record" "backend_api_alias" {
  zone_id = data.aws_route53_zone.ljhun_zone.zone_id
  name    = "api.ljhun.shop"
  type    = "A"

  set_identifier = "aws-endpoint"
  allow_overwrite = true
  
  weighted_routing_policy {
    weight = 50
  }

  alias {
    name                   = aws_cloudfront_distribution.backend_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.backend_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "backend_api_alias_gcp" {
  zone_id = data.aws_route53_zone.ljhun_zone.id
  name    = "api.ljhun.shop"
  type    = "A"

  set_identifier = "gcp-endpoint"
  allow_overwrite = true

  weighted_routing_policy {
    weight = 50
  }


  records = [data.terraform_remote_state.gcp.outputs.ingress_ip]
  ttl     = 60
}

resource "aws_route53_record" "health_api_alias_gcp" {
  zone_id = data.aws_route53_zone.ljhun_zone.id
  name    = "healthcheck.ljhun.shop"
  type    = "A"
  allow_overwrite = true
  records = [data.terraform_remote_state.gcp.outputs.ingress_ip]
  ttl     = 60
}

# -------------------------------------------------------------------------

# ALB 헬스 체크
resource "aws_route53_health_check" "alb_health_check" {
  fqdn              = var.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/healthz"
  request_interval  = 30
  failure_threshold = 3
}

# EKS 헬스 체크 (ALB를 통해 EKS 서비스 확인)
resource "aws_route53_health_check" "eks_health_check1" {
  fqdn              = var.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/app-one/register"
  request_interval  = 30
  failure_threshold = 3
}

# EKS 헬스 체크 (ALB를 통해 EKS 서비스 확인)
resource "aws_route53_health_check" "eks_health_check2" {
  fqdn              = var.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/app-two/login"
  request_interval  = 30
  failure_threshold = 3
}

resource "aws_route53_health_check" "gcp_alb_health_check" {
  fqdn              = "healthcheck.ljhun.shop"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/healthz"
  request_interval  = 30
  failure_threshold = 3
}

# EKS 헬스 체크 (ALB를 통해 EKS 서비스 확인)
resource "aws_route53_health_check" "gcp_gke_health_check1" {
  fqdn              = "healthcheck.ljhun.shop"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/app-one/register"
  request_interval  = 30
  failure_threshold = 3
}

# EKS 헬스 체크 (ALB를 통해 EKS 서비스 확인)
resource "aws_route53_health_check" "gcp_gke_health_check2" {
  fqdn              = "healthcheck.ljhun.shop"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/app-two/login"
  request_interval  = 30
  failure_threshold = 3
}

# Terraform이 lambda_function.py를 ZIP 파일로 자동 압축하도록 설정.
# path.module: 현재 실행 중인 Terraform 코드 파일이 있는 디렉터리
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_function" # lambda_function 폴더를 ZIP으로 압축
  output_path = "${path.module}/lambda_function.zip" # 이것으로 압축
}

# Lambda가 Route 53 가중치를 변경하도록 헬스 체크 정보를 주입
resource "aws_lambda_function" "update_route53_lambda" {
  function_name = "update-route53-weights"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 10
  memory_size   = 128
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # GUI에서 코드 업로드 → Terraform은 환경 변수만 관리
  environment {
    variables = {
      ALB_HEALTH_CHECK_ID   = aws_route53_health_check.alb_health_check.id
      EKS_HEALTH_CHECK1_ID  = aws_route53_health_check.eks_health_check1.id
      EKS_HEALTH_CHECK2_ID  = aws_route53_health_check.eks_health_check2.id
      GCP_HEALTH_CHECK_ID   = aws_route53_health_check.gcp_alb_health_check.id
      GKE_HEALTH_CHECK1_ID   = aws_route53_health_check.gcp_gke_health_check1.id
      GKE_HEALTH_CHECK2_ID   = aws_route53_health_check.gcp_gke_health_check2.id
      ROUTE53_ZONE_ID       = data.aws_route53_zone.ljhun_zone.id

       # ✅ CLOUDFRONT 관련 환경 변수 추가
      CLOUDFRONT_HOSTED_ZONE_ID = aws_cloudfront_distribution.backend_distribution.hosted_zone_id # "Z2FDTNDATAQYW2"  # CloudFront 기본 Hosted Zone ID
      CLOUDFRONT_DNS_NAME       = aws_cloudfront_distribution.backend_distribution.domain_name

      # ✅ 백엔드 API (api.ljhun.shop) - 가중치 변경 대상
      AWS_API_RECORD_ID     = "aws-endpoint"
      GCP_API_RECORD_ID     = "gcp-endpoint"

      ROUTE53_API_DOMAIN    = "api.ljhun.shop"

      GCP_API_IP            = data.terraform_remote_state.gcp.outputs.ingress_ip
    }
  }
}

# Lambda 실행을 위한 IAM Role
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Lambda 실행을 위한 정책
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_route53_policy"
  description = "Allow Lambda to update Route 53 and allow logs"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "route53:ChangeResourceRecordSets",
          "route53:GetHealthCheckStatus"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = "lambda:InvokeFunction",
        Resource = aws_lambda_function.update_route53_lambda.arn
      }
    ]
  })
}

# IAM Role과 정책 연결
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# EventBridge Scheduler 그룹 생성
resource "aws_scheduler_schedule_group" "lambda_schedule_group" {
  name = "route53-healthcheck-group"
}

# EventBridge Scheduler 생성 (1분마다 실행)
resource "aws_scheduler_schedule" "lambda_schedule" {
  name                = "route53-healthcheck-schedule"
  group_name          = aws_scheduler_schedule_group.lambda_schedule_group.name
  schedule_expression = "rate(1 minute)"
  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.update_route53_lambda.arn
    role_arn = aws_iam_role.lambda_exec.arn
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_route53_lambda.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.lambda_schedule.arn
}