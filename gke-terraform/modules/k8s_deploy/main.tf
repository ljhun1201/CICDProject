provider "kubernetes" {
  host                   = var.gke_cluster_endpoint
  cluster_ca_certificate = base64decode(var.gke_cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

data "google_client_config" "default" {}

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
          image = var.app_one_image
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
          image = var.app_two_image
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
      "cloud.google.com/neg" = "{\"exposed_ports\": {\"5000\":{}}}"
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
      "cloud.google.com/neg" = "{\"exposed_ports\": {\"5000\":{}}}"
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

resource "kubernetes_ingress" "app_ingress" {
  metadata {
    name      = "app-ingress"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class" = "gce"
      "kubernetes.io/ingress.allow-http" = "false"
      "cloud.google.com/neg" = "{\"ingress\": true}"
    }
  }
  spec {
    rule {
      host = "www.ljhun.shop"
      http {
        path {
          path     = "/app-one/*"
          backend {
            service_name = kubernetes_service.app_one_service.metadata[0].name
            service_port = 80
          }
        }
        path {
          path     = "/app-two/*"
          backend {
            service_name = kubernetes_service.app_one_service.metadata[0].name
            service_port = 80
          }
        }
      }
    }
  }
}

output "app_ingress_name" {
  value = kubernetes_ingress.app_ingress.metadata[0].name
}

output "app_ingress_namespace" {
  value = kubernetes_ingress.app_ingress.metadata[0].namespace
}

output "neg_app_one" {
  value = "k8s1-${var.cluster_name}-default-app-one-service-5000"
}

output "neg_app_two" {
  value = "k8s1-${var.cluster_name}-default-app-two-service-5000"
}