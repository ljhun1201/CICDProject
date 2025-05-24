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
        image_pull_secrets {
          name = "artifact-registry-key"
        }

        container {
          name  = "app-one-container"
          image = "asia-northeast3-docker.pkg.dev/peppy-arcadia-432311-g5/app-images/user-registration-service:latest"
          port {
            container_port = 8080
          }
          env {
            name  = "DB_HOST"
            value = var.db_endpoint
          }
          env {
            name  = "DB_USER"
            value = "root"
          }
          env {
            name  = "DB_PASSWORD"
            value = var.db_password
          }
          env {
            name  = "DB_NAME"
            value = var.db_name
          }

          # Health Check 설정
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
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
        image_pull_secrets {
          name = "artifact-registry-key"
        }

        container {
          name  = "app-two-container"
          image = "asia-northeast3-docker.pkg.dev/peppy-arcadia-432311-g5/app-images/user-login-service:latest"
          port {
            container_port = 8080
          }
          env {
            name  = "DB_HOST"
            value = var.db_endpoint
          }
          env {
            name  = "DB_USER"
            value = "root"
          }
          env {
            name  = "DB_PASSWORD"
            value = var.db_password
          }
          env {
            name  = "DB_NAME"
            value = var.db_name
          }

          # Health Check 설정
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
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
  metadata {
    name      = "db-init-job"
    namespace = "default"
  }
  spec {
    backoff_limit = 3
    template {
      metadata {
        labels = {
          job = "db-init"
        }
      }
      spec {
        restart_policy = "Never"
        container {
          name  = "db-init-container"
          image = "mysql:8.0"
          command = [
            "sh", "-c",
            <<EOT
              mysql -h ${var.db_endpoint} -u root -p${var.db_password} -e "
              CREATE DATABASE IF NOT EXISTS ${var.db_name};
              USE ${var.db_name};
              CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(50) NOT NULL,
                password VARCHAR(100) NOT NULL,
                email VARCHAR(100) NOT NULL
              );
              "
            EOT
          ]
        }
      }
    }
  }
}

resource "kubernetes_service" "app_one_service" {
  metadata {
    name      = "app-one-service"
    namespace = "default"
    annotations = {
      "cloud.google.com/neg" = "{\"exposed_ports\": {\"80\":{}}}" # NEG는 AWS Target Group과 비슷하기때문에, 그것과 비슷하게 생각하면 됨. 즉, 이 NEG 포트도 k8s service랑 맞춰야함
    }
  }
  spec {
    selector = {
      app = "app-one"
    }
    port {
      port        = 80
      target_port = 8080
    }
    type = "NodePort"
  }
}

resource "kubernetes_service" "app_two_service" {
  metadata {
    name      = "app-two-service"
    namespace = "default"
    annotations = {
      "cloud.google.com/neg" = "{\"exposed_ports\": {\"80\":{}}}"
    }
  }
  spec {
    selector = {
      app = "app-two"
    }
    port {
      port        = 80
      target_port = 8080
    }
    type = "NodePort"
  }
}

# cert-manager CRD + controller 설치를 오직 여기서만 함
resource "null_resource" "install_cert_manager" {

  depends_on = [
    kubernetes_deployment.app_one,
    kubernetes_deployment.app_two,
    kubernetes_job.db_init_job,
    kubernetes_service.app_one_service,
    kubernetes_service.app_two_service
  ]

  provisioner "local-exec" {
    command = <<EOT
      set -e  # 에러 발생 시 스크립트 종료

      echo "[INFO] cert-manager Helm repo 설정"
      helm repo add jetstack https://charts.jetstack.io || true
      helm repo update

      echo "[INFO] 기존 cert-manager 제거 (있을 경우)"
      helm uninstall cert-manager -n cert-manager || true
      kubectl delete ns cert-manager --ignore-not-found

      echo "[INFO] cert-manager 재설치 및 CRD 포함"
      helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true

      echo "[INFO] CRD가 정상적으로 등록될 때까지 대기"
      for i in {1..30}; do
        kubectl get crd clusterissuers.cert-manager.io && break || sleep 2
      done

      echo "[INFO] CRD 상태 확인"
      kubectl wait --for=condition=Established --timeout=60s crd/clusterissuers.cert-manager.io
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

# 이후 ClusterIssuer, Certificate 등의 리소스 정의는 기존과 동일하게 유지

# 예시로 이어지는 ClusterIssuer 및 Certificate 정의
resource "kubernetes_secret" "route53_secret" {
  depends_on = [
    null_resource.install_cert_manager
  ]

  metadata {
    name      = "route53-secret"
    namespace = "cert-manager"
  }

  data = {
    access_key_id     = var.access_key_id
    secret_access_key = var.secret_access_key
  }

  type = "Opaque"
}

resource "kubernetes_secret" "route53_secret_default" {
  depends_on = [
    null_resource.install_cert_manager
  ]

  metadata {
    name      = "route53-secret"
    namespace = "default"
  }

  data = {
    access_key_id     = var.access_key_id
    secret_access_key = var.secret_access_key
  }

  type = "Opaque"
}

resource "kubernetes_manifest" "letsencrypt_prod_issuer" {
  depends_on = [
    null_resource.install_cert_manager,
    kubernetes_secret.route53_secret,
    kubernetes_secret.route53_secret_default
  ]

  manifest = yamldecode(<<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: "1201ljhun@gmail.com"
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - dns01:
          route53:
            region: "us-east-1"
            hostedZoneID: "Z003422921ZWRSU9KTPP7"
            accessKeyIDSecretRef:
              name: route53-secret
              key: access_key_id
            secretAccessKeySecretRef:
              name: route53-secret
              key: secret_access_key
EOF
  )
}

resource "kubernetes_manifest" "app_ingress_certificate" {
  depends_on = [
    kubernetes_manifest.letsencrypt_prod_issuer
  ]

  manifest = yamldecode(<<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-ingress-certificate
  namespace: default
spec:
  secretName: app-ingress-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: api.ljhun.shop
  dnsNames:
    - api.ljhun.shop
    - healthcheck.ljhun.shop
  privateKey:
    rotationPolicy: Always
  usages:
    - digital signature
    - key encipherment
    - server auth
EOF
  )
}

resource "google_compute_global_address" "ingress_static_ip" {
  name       = "my-ingress-ip"
  project    = var.project_id
  ip_version = "IPV4"
}

resource "kubernetes_ingress_v1" "app_ingress" {
  depends_on = [
    kubernetes_service.app_one_service,                 # 백엔드 서비스 존재해야 연결 가능
    kubernetes_service.app_two_service,
    kubernetes_manifest.app_ingress_certificate         # TLS Secret 먼저 생성돼야 ingress에서 참조 가능
  ]

  metadata {
    name      = "app-ingress"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class" = "gce"
      "kubernetes.io/ingress.allow-http" = "true"
      # "cert-manager.io/cluster-issuer" = "letsencrypt-staging" --> 제거: 어차피 수동으로 만든 cert-manager 인증서 때문에 이것은 할 필요 없음
      "cloud.google.com/neg" = "{\"ingress\": true}"
      "ingress.kubernetes.io/backends"    = "true" # 디버깅 용도
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.ingress_static_ip.name # 필요 시, 고정 IP 할당(추가로 global_address를 만들어서 설정)

      /*
      "nginx.ingress.kubernetes.io/cors-allow-origin" = "*"
      "nginx.ingress.kubernetes.io/cors-allow-methods" = "GET, POST, OPTIONS"
      "nginx.ingress.kubernetes.io/cors-allow-headers" = "Content-Type"
      "nginx.ingress.kubernetes.io/cors-allow-credentials" = "true"
      */
    }
  }
  spec {
    ingress_class_name = "gce"
    tls {
      hosts      = ["api.ljhun.shop", "healthcheck.ljhun.shop"]
      secret_name = "app-ingress-tls"
    }
    rule {
      host = "api.ljhun.shop"
      http {
        path {
          path     = "/app-one/register"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.app_one_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
        path {
          path     = "/app-two/login"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.app_two_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
        path {
          path     = "/healthz"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.app_one_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "healthcheck.ljhun.shop"
      http {
        path {
          path     = "/app-one/register"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.app_one_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
        path {
          path     = "/app-two/login"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.app_two_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
        path {
          path     = "/healthz"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.app_two_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

output "app_ingress_name" {
  value = kubernetes_ingress_v1.app_ingress.metadata[0].name
}

output "app_ingress_namespace" {
  value = kubernetes_ingress_v1.app_ingress.metadata[0].namespace
}

output "neg_app_one" {
  value = "k8s1-${var.cluster_name}-default-app-one-service-8080"
}

output "neg_app_two" {
  value = "k8s1-${var.cluster_name}-default-app-two-service-8080"
}

output "ingress_ip" {
  value = google_compute_global_address.ingress_static_ip.address
}

output "ingress_dns" {
  value = "healthcheck.ljhun.shop"
}