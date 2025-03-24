# 기존 ECR 리포지토리 조회 (user-registration-service)
data "aws_ecr_repository" "user_registration_repo" {
  name = "user-registration-service"
}

# 기존 ECR 리포지토리 조회 (user-login-service)
data "aws_ecr_repository" "user_login_repo" {
  name = "user-login-service"
}

provider "kubernetes" {
  host                   = var.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(var.eks_cluster_ca)
  token                  = var.eks_auth

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name]
    env = {
      AWS_ROLE_ARN = aws_iam_role.eks_oidc_role.arn
    }
  }
}

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
          image = data.aws_ecr_repository.user_registration_repo.repository_url
          port {
            container_port = 5000
          }

          env {
            name  = "DB_HOST"
            value = var.db_endpoint
          }
          env {
            name  = "DB_USER"
            value = "admin"       # 예: 하드코딩 or 별도 변수
          }
          env {
            name  = "DB_PASSWORD"
            value = var.db_password
          }
          env {
            name  = "DB_NAME"
            value = "mydb"        # aws_db_instance.mydb.db_name에 맞춤
          }

          # Health Check 설정
          # liveness_probe: k8s가 내부적으로 해당 deployment의 해당 path에 가서 해당 자원이 살아있는지를 검토
          # 실패 시, 해당 container를 강제 종료 후 재시작
          # 중요: Ingress LB자체가 내부 자원을 검토하는 것이 아님, LB는 단지 트래픽을 보내 본 후 OK 응답을 받으면 healthy로 처리하는 것 뿐.
          # 자체 자원을 검토하는 것은 deployment의 liveness_probe, readiness_probe임.
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          
          # 해당 deployment의 pod가 외부 트래픽을 받을 준비가 되었는지를 검토.
          # 실패 시, 해당 container는 성공할 때까지 ALB의 Target Group에서 제외됨.
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
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
          image = data.aws_ecr_repository.user_login_repo.repository_url
          port {
            container_port = 5000
          }

          env {
            name  = "DB_HOST"
            value = var.db_endpoint
          }
          env {
            name  = "DB_USER"
            value = "admin"       # 예: 하드코딩 or 별도 변수
          }
          env {
            name  = "DB_PASSWORD"
            value = var.db_password
          }
          env {
            name  = "DB_NAME"
            value = "mydb"        # aws_db_instance.mydb.db_name에 맞춤
          }

          # Health Check 설정
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_job" "db_init_job" {
  depends_on = [
    kubernetes_deployment.app_one,
    kubernetes_deployment.app_two
  ]

  metadata {
    name      = "db-init-job"
    namespace = "default"
  }

  spec {
    backoff_limit = 3  # 실패 시 최대 3번까지 재시도

    template {
      metadata {
        labels = {
          job = "db-init"
        }
      }

      spec {
        restart_policy = "Never"  # Pod 실패 시 재시작하지 않음

        container {
          name  = "db-init-container"
          image = "mysql:8.0"  # 데이터베이스 초기화를 위한 MySQL 이미지 사용
          command = [
            "sh", "-c",
            <<EOT
              mysql -h ${var.db_endpoint} -u admin -p${var.db_password} -e "
              CREATE DATABASE IF NOT EXISTS mydb;
              USE mydb;
              CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(50) NOT NULL,
                password VARCHAR(100) NOT NULL,
                email VARCHAR(100) NOT NULL
              );
              "
            EOT
          ]

          env {
            name  = "DB_HOST"
            value = var.db_endpoint
          }

          env {
            name  = "DB_USER"
            value = "admin"
          }

          env {
            name  = "DB_PASSWORD"
            value = var.db_password
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
      target_port = 5000
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
      target_port = 5000
    }

    type = "ClusterIP"
  }
}

provider "helm" {
  kubernetes {
    host                   = var.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(var.eks_cluster_ca)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name]
      env         = {
        AWS_ROLE_ARN = aws_iam_role.eks_oidc_role.arn
      }
    }
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
    value = var.eks_cluster_name
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.eks_oidc_role.arn
  }
}

# OIDC Provider URL에서 https:// 제거
locals {
  oidc_provider_url = replace(var.oidc_issuer_url, "https://", "")
}

# EKS OIDC Provider 생성
resource "aws_iam_openid_connect_provider" "eks_oidc" {
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"  # AWS에서 사용하는 표준 thumbprint
  ]
  url = var.oidc_issuer_url
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "eks_oidc_role" {
  name = "eks-oidc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider_url}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

# ALB Controller를 위한 IAM 정책 생성
resource "aws_iam_policy" "alb_controller_policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for AWS Load Balancer Controller"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole",
                "ec2:Describe*",
                "ec2:Get*",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:CreateSecurityGroup",
                "ec2:DeleteSecurityGroup",
                "ec2:CreateTags",
                "ec2:DeleteTags",
                "elasticloadbalancing:*",
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "waf-regional:GetWebACL",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:GetSubscriptionState",
                "shield:DescribeProtection",
                "shield:CreateProtection",
                "shield:DeleteProtection"
            ],
            "Resource": "*"
        }
    ]
  })
}

# CloudFront용 ACM을 위한 us-east-1 리전 프로바이더 설정
provider "aws" {
  region = "ap-northeast-2"
}

# 기존 ACM 인증서 조회 (동적 참조)
data "aws_acm_certificate" "ljhun_cert" {
  domain   = "api.ljhun.shop"     # 인증서에 등록된 도메인 이름
  statuses = ["ISSUED"]           # 발급 완료된 인증서만 조회
}

# 생성한 정책을 OIDC 역할에 연결
resource "aws_iam_role_policy_attachment" "alb_controller_policy_attachment" {
  policy_arn = aws_iam_policy.alb_controller_policy.arn
  role       = aws_iam_role.eks_oidc_role.name
}

resource "kubernetes_manifest" "app_ingress" {
  depends_on = [
    helm_release.alb_controller,
    kubernetes_service.app_one_service,
    kubernetes_service.app_two_service,
    data.aws_acm_certificate.ljhun_cert
  ]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "app-ingress"
      namespace = "default"
      annotations = {
        "kubernetes.io/ingress.class"              = "alb"
        "alb.ingress.kubernetes.io/scheme"        = "internet-facing"
        "alb.ingress.kubernetes.io/listen-ports"  = "[{\"HTTP\":80}, {\"HTTPS\":443}]" # ALB의 포트
        "alb.ingress.kubernetes.io/certificate-arn" = "arn:aws:acm:ap-northeast-2:481665107235:certificate/d2e40628-5ff5-466a-a818-14b2d9b2475f"
        "alb.ingress.kubernetes.io/target-type"   = "ip"  # ip: svc를 거치지 않고 pod로 직접 라우팅, NodePort 사용 X, 이것으로 인한 svc 사용 X, 이것을 지정하면 CNI 플러그인 형식에 따라 POD의 IP가 노드 밖으로 나오므로, NodePort 사용이 안 되는 것임(즉, ALB가 svc를 거치지 않고도 POD로 직접 라우팅 가능, clusterIP의 PORT는 무시됨), instance: NodePort 사용, 즉, svc를 거침
        "alb.ingress.kubernetes.io/security-groups" = var.alb_security_group_id
        "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"  # Health Check 경로 설정(이 경우, 모든 TG로, /healthz 경로로 헬스체크 트래픽을 전송. listener 정책이랑은 관련이 없음.)
        "alb.ingress.kubernetes.io/healthcheck-port" = "5000"  # Health Check 포트
        "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "30"  # Health Check 간격
        "alb.ingress.kubernetes.io/healthcheck-timeout-seconds" = "5"    # Health Check 타임아웃
        "alb.ingress.kubernetes.io/success-codes" = "200"                # 성공 응답 코드
        # ALB 액세스 로그 활성화
        "alb.ingress.kubernetes.io/load-balancer-attributes" = "access_logs.s3.enabled=true, access_logs.s3.bucket=alb-log-file"

        # CORS 설정 추가
        "alb.ingress.kubernetes.io/allow-headers" = "*"
        "alb.ingress.kubernetes.io/allow-methods" = "GET,POST,PUT,DELETE,OPTIONS"
        "alb.ingress.kubernetes.io/allow-origin"  = "*"
        "alb.ingress.kubernetes.io/expose-headers" = "Authorization,Content-Type"
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [
        {
          host = "api.ljhun.shop" # 리스너 정책이 지정한 host
          http = {
            paths = [
              {
                path     = "/app-one/register" # 리스너 정책이 지정한 경로
                pathType = "Prefix"
                backend = {
                  service = {
                    name = kubernetes_service.app_one_service.metadata[0].name # 타깃 그룹
                    port = {
                      number = 80  # ClusterIP 서비스의 포트
                    }
                  }
                }
              },
              {
                path     = "/app-two/login"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = kubernetes_service.app_two_service.metadata[0].name
                    port = {
                      number = 80
                    }
                  }
                }
              },
              {
                path     = "/healthz"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = kubernetes_service.app_one_service.metadata[0].name
                    port = {
                      number = 80  # ClusterIP 서비스의 포트
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
