provider "aws" {
  region = "ap-northeast-2"
}

# CloudFront용 ACM을 위한 us-east-1 리전 프로바이더 설정
provider "aws" {
  alias  = "us_east_1"     # 별칭을 지정하여 us-east-1 리전 분리
  region = "us-east-1"
}

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

  # restrictions 블록 추가
  restrictions {
    geo_restriction {
      restriction_type = "none"  # 지역 제한 없음 ("whitelist"나 "blacklist"로 변경 가능)
    }
  }

  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name  # S3 버킷의 도메인 이름
    origin_id   = "S3-frontend"                                              # CloudFront에서 식별하기 위한 원본 ID

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_identity.cloudfront_access_identity_path
    }

    
  }

  enabled             = true                                                 # CloudFront 배포 활성화
  is_ipv6_enabled     = true                                                 # IPv6 지원
  default_root_object = "index.html"                                         # 기본 루트 오브젝트 설정

  aliases = ["ljhun.shop", "www.ljhun.shop"]                                 # 사용할 도메인 별칭

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]                               # 허용할 HTTP 메서드
    cached_methods   = ["GET", "HEAD"]                               # 캐시할 메서드
    target_origin_id = "S3-frontend"                                         # 대상 원본 ID 설정

    forwarded_values {
      query_string = false                                                   # 쿼리 문자열 전달 여부
      cookies {
        forward = "none"                                                     # 쿠키 전달 안 함
      }
    }

    viewer_protocol_policy = "redirect-to-https"                             # HTTP 요청을 HTTPS로 리다이렉트
    min_ttl                = 0                                               # 최소 TTL 설정
    default_ttl            = 3600                                            # 기본 TTL 설정
    max_ttl                = 86400                                           # 최대 TTL 설정
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.ljhun_cert.arn                # ACM 인증서 ARN
    ssl_support_method  = "sni-only"                                         # SNI 기반 SSL 지원
    minimum_protocol_version = "TLSv1.2_2019"                                # 최소 TLS 버전 설정
  }
}

# CloudFront의 S3 접근 권한 설정
resource "aws_cloudfront_origin_access_identity" "s3_identity" {
  comment = "OAI for S3 frontend bucket"                                      # OAI에 대한 설명
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

resource "aws_ecr_repository" "user_registration_repo" {
  name = "user-registration-service"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "user_login_repo" {
  name = "user-login-service"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

# -----------------------------------------------------------
# VPC 생성
resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "eks-vpc"
  }
}

# 퍼블릭 서브넷 생성 (ALB용)
resource "aws_subnet" "public_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["ap-northeast-2a", "ap-northeast-2c"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet-${count.index}"
  }
}

# 프라이빗 서브넷 생성 (EKS용)
resource "aws_subnet" "private_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index + 2)
  availability_zone       = element(["ap-northeast-2a", "ap-northeast-2c"], count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "eks-private-subnet-${count.index}"
  }
}

# 인터넷 게이트웨이 생성
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  }
}

# 퍼블릭 라우팅 테이블 생성 및 연결
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "eks-public-route-table"
  }
}

resource "aws_route_table_association" "public_subnet_associations" {
  count          = length(aws_subnet.public_subnets[*].id)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "eks-nat-eip"
  }
}

# NAT 게이트웨이 생성 (프라이빗 서브넷의 인터넷 액세스용)
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat.id
  subnet_id     = element(aws_subnet.public_subnets[*].id, 0)

  tags = {
    Name = "eks-nat-gateway"
  }
}

# 프라이빗 라우팅 테이블 생성 및 연결
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "eks-private-route-table"
  }
}

resource "aws_route_table_association" "private_subnet_associations" {
  count          = length(aws_subnet.private_subnets[*].id)
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = aws_route_table.private_route_table.id
}

# ALB 보안 그룹 생성
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "alb-sg"
  }
}

# EKS 노드 그룹용 보안 그룹 생성
resource "aws_security_group" "eks_node_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
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
    Name = "eks-node-sg"
  }
}

#----------------------------------------------------------------------------

# EKS 클러스터
resource "aws_eks_cluster" "eks_cluster" {
  name     = "eks-cluster"
  role_arn = "arn:aws:iam::481665107235:role/eks-cluster-role"

  vpc_config {
    subnet_ids = concat(
      aws_subnet.private_subnets[*].id
    )
  }

  tags = {
    Name = "eks-cluster"
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks_auth.token
  config_path = "~/.kube/config"
}

data "aws_eks_cluster_auth" "eks_auth" {
  name = aws_eks_cluster.eks_cluster.name
}

# EKS Node Group
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks-node-group"
  node_role_arn   = "arn:aws:iam::481665107235:role/eks-node-role"
  subnet_ids      = aws_subnet.private_subnets[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  tags = {
    Name = "eks-node-group"
  }
}

#--------------------------------------------------------------------------------

resource "kubernetes_deployment" "app_one" {
  metadata {
    name      = "app-one"
    namespace = "default"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "app-one"
      }
    }

    template {
      metadata {
        labels = {
          app = "app-one"
        }
      }

      spec {
        container {
          name  = "app-one-container"
          image = aws_ecr_repository.user_registration_repo.repository_url
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "app_two" {
  metadata {
    name      = "app-two"
    namespace = "default"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "app-two"
      }
    }

    template {
      metadata {
        labels = {
          app = "app-two"
        }
      }

      spec {
        container {
          name  = "app-two-container"
          image = aws_ecr_repository.user_login_repo.repository_url
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "app_one_service" {
  metadata {
    name      = "app-one-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "app-one"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_service" "app_two_service" {
  metadata {
    name      = "app-two-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "app-two"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

#-------------------------------------------------------------------

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks_auth.token
  }
}

# ALB Controller Helm 설치
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  chart      = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.eks_cluster.name
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  set {
    name  = "vpcId"
    value = aws_vpc.eks_vpc.id
  }
}

/*
resource "kubernetes_manifest" "app_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "app-ingress"
      namespace = "default"
      annotations = {
        "kubernetes.io/ingress.class"        = "alb"
        "alb.ingress.kubernetes.io/scheme"  = "internet-facing"
        "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}]"
        "alb.ingress.kubernetes.io/target-type"  = "ip"
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [
        {
          host = "ljhun.shop"
          http = {
            paths = [
              {
                path     = "/app-one"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = kubernetes_service.app_one_service.metadata[0].name
                    port = {
                      number = 80
                    }
                  }
                }
              },
              {
                path     = "/app-two"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = kubernetes_service.app_two_service.metadata[0].name
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}
*/


#-----------------------------------------------------------------