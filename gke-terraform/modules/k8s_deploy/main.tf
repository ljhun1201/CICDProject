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
            container_port = 5000
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
            container_port = 5000
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
      target_port = 5000
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
      target_port = 5000
    }
    type = "NodePort"
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.12.3"  # 원하는 버전
  namespace  = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  # 추가 세팅이 필요하면 values.yml이든 inline set이든 설정
}

resource "kubernetes_secret" "route53_secret" {
  metadata {
    name      = "route53-secret"
    namespace = "cert-manager"
  }

  data = {
    access-key-id     = var.access-key-id   # AWS Access Key ID
    secret-access-key = var.secret-access-key  # AWS Secret Access Key
  }
}

resource "kubernetes_manifest" "letsencrypt_prod_issuer" {
  depends_on = [
    helm_release.cert_manager
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
            region: "us-east-1"  # Route 53은 글로벌이지만, IAM 설정은 특정 리전 필요
            hostedZoneID: "Z003422921ZWRSU9KTPP7"  # Route 53 Hosted Zone ID
            accessKeyIDSecretRef:
              name: route53-secret
              key: access-key-id
            secretAccessKeySecretRef:
              name: route53-secret
              key: secret-access-key
EOF
  )
}

resource "kubernetes_manifest" "app_ingress_certificate" {
  depends_on = [kubernetes_manifest.letsencrypt_prod_issuer]

  manifest = yamldecode(<<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-ingress-certificate
  namespace: default
spec:
  secretName: app-ingress-tls   # Ingress의 spec.tls.secretName와 동일
  issuerRef:
    name: letsencrypt-prod      # 위에서 만든 ClusterIssuer
    kind: ClusterIssuer
  dnsNames:
    - "api.ljhun.shop"
    - "healthcheck.ljhun.shop"
EOF
  )
}

resource "google_compute_global_address" "ingress_static_ip" {
  name       = "my-ingress-ip"
  project    = var.project_id
  ip_version = "IPV4"
}

resource "kubernetes_ingress_v1" "app_ingress" {
  metadata {
    name      = "app-ingress"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class" = "gce"
      "kubernetes.io/ingress.allow-http" = "true"
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
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
              name = kubernetes_service.app_two_service.metadata[0].name
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
  value = "k8s1-${var.cluster_name}-default-app-one-service-5000"
}

output "neg_app_two" {
  value = "k8s1-${var.cluster_name}-default-app-two-service-5000"
}

output "ingress_ip" {
  value = google_compute_global_address.ingress_static_ip.address
}

output "ingress_dns" {
  value = "healthcheck.ljhun.shop"
}
