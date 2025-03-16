terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"  # 최신 버전 사용
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 4.0.0"  # 최신 버전 사용
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35.1"
    }
  }

  backend "gcs" {
    bucket = "my-terraform-db-info"    # 실제 GCS 버킷 이름
    prefix = "cloudsql-state"          # 이 모듈에 대한 state 파일 경로
  }

  required_version = ">= 1.3.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = module.gke.cluster_endpoint
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

data "google_client_config" "default" {}

####################################################
# 1) Network (VPC/Subnets/NAT)
####################################################
module "network" {
  source = "./modules/network"

  project_id = var.project_id
  region     = var.region
  vpc_name   = var.vpc_name
}

####################################################
# 2) Cloud SQL (MySQL)
####################################################
module "cloud_sql" {
  depends_on = [ module.network ]

  source     = "./modules/cloud_sql"
  project_id = var.project_id
  region     = var.region
  db_name    = var.db_name
  db_password = var.db_password

  vpc_self_link = module.network.vpc_self_link
}

####################################################
# 3) GKE Cluster
####################################################
module "gke" {
  depends_on = [ module.cloud_sql ]

  source = "./modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  network_name = var.vpc_name
  subnetwork_name = module.network.private_subnet_name
}

####################################################
# 4) Storage and LB Module
####################################################
module "storage_and_lb" {
  source = "./modules/storage_and_lb"

  project_id      = var.project_id
  region          = var.region
  vpc_self_link   = module.network.vpc_self_link
  subnet_self_link = module.network.subnet_self_link
  domain_name     = var.domain_name
  domain_name_www = var.domain_name_www
  gcs_bucket_name = var.gcs_bucket_name
  zones = ["${var.region}-a", "${var.region}-b"]
  cluster_name = var.cluster_name

  ingress_name      = module.k8s_deploy.app_ingress_name
  ingress_namespace = module.k8s_deploy.app_ingress_namespace
  neg_app_one       = module.k8s_deploy.neg_app_one
  neg_app_two       = module.k8s_deploy.neg_app_two

  # GKE 모듈의 MIG 정보를 전달
  mig_info = module.gke.mig_info

  depends_on = [module.gke, module.k8s_deploy]
}

module "k8s_deploy" {
  source = "./modules/k8s_deploy"

  project_id = var.project_id
  gke_cluster_endpoint      = module.gke.cluster_endpoint
  gke_cluster_ca_certificate = module.gke.cluster_ca_certificate
  cluster_name = var.cluster_name

  # DB Endpoint and Credentials
  db_endpoint   = module.cloud_sql.db_private_ip
  db_password   = var.db_password
  db_name       = var.db_name

  domain_name   = var.domain_name
  app_one_image = var.app_one_image
  app_two_image = var.app_two_image

  providers = {
    kubernetes = kubernetes
  }
}
/*
module "route53" {
  source = "./route53"

  lb_ip_address = module.storage_and_lb.lb_ip_address
  ingress_ip = module.k8s_deploy.ingress_ip
}
*/