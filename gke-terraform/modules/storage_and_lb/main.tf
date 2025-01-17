resource "google_storage_bucket" "frontend_bucket" {
  name           = var.gcs_bucket_name
  project        = var.project_id
  location       = var.region
  force_destroy  = true

  website {
    main_page_suffix = "login.html"
    not_found_page   = "error.html"
  }
}

resource "google_storage_bucket_iam_binding" "all_users_read" {
  bucket = google_storage_bucket.frontend_bucket.name
  role   = "roles/storage.objectViewer"
  members = ["allUsers"]
}

locals {
  files = [
    { key = "login.html",  source = "../html/login.html" },
    { key = "signup.html", source = "../html/signup.html" },
    { key = "main.html",   source = "../html/main.html" }
  ]
}

resource "google_storage_bucket_object" "html_files" {
  for_each = { for file in local.files : file.key => file }

  bucket       = google_storage_bucket.frontend_bucket.name
  name         = each.value.key
  source       = each.value.source
  content_type = "text/html"
}

resource "google_compute_backend_bucket" "gcs_backend" {
  name        = "gcs-backend"
  bucket_name = google_storage_bucket.frontend_bucket.name
  enable_cdn  = true
}

# App One NEG 탐지
data "google_compute_network_endpoint_group" "app_one_neg" {
  for_each = toset(var.zones) # 클러스터의 모든 Zone

  name    = var.neg_app_one
  zone    = each.value
  project = var.project_id
}

# App Two NEG 탐지
data "google_compute_network_endpoint_group" "app_two_neg" {
  for_each = toset(var.zones) # 클러스터의 모든 Zone

  name    = var.neg_app_two
  zone    = each.value
  project = var.project_id
}

resource "google_compute_health_check" "gke_http_health_check" {
  name                = "gke-http-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port = 80
    request_path = "/healthz"
  }
}

resource "google_compute_backend_service" "app_one_backend" {
  name            = "app-one-backend"
  protocol        = "HTTP"
  timeout_sec     = 30
  health_checks   = [google_compute_health_check.gke_http_health_check.self_link]
  
  dynamic "backend" {
    for_each = data.google_compute_network_endpoint_group.app_one_neg
    content {
      group = backend.value.id
      balancing_mode = "RATE"
      max_rate_per_endpoint = 50
    }
  }

  depends_on = [data.google_compute_network_endpoint_group.app_one_neg]
}

resource "google_compute_backend_service" "app_two_backend" {
  name            = "app-two-backend"
  protocol        = "HTTP"
  timeout_sec     = 30
  health_checks   = [google_compute_health_check.gke_http_health_check.self_link]
  
  dynamic "backend" {
    for_each = data.google_compute_network_endpoint_group.app_one_neg
    content {
      group = backend.value.id
      balancing_mode = "RATE"
      max_rate_per_endpoint = 50
    }
  }

  depends_on = [data.google_compute_network_endpoint_group.app_two_neg]
}

resource "google_compute_url_map" "lb_url_map" {
  name            = "lb-url-map"
  default_service = google_compute_backend_bucket.gcs_backend.self_link

  host_rule {
    hosts        = [var.domain_name, var.www_domain_name]
    path_matcher = "web-paths"
  }

  path_matcher {
    name            = "web-paths"
    default_service = google_compute_backend_bucket.gcs_backend.self_link

    path_rule {
      paths   = ["/app-one/*"]
      service = google_compute_backend_service.app_one_backend.self_link
    }

    path_rule {
      paths   = ["/app-two/*"]
      service = google_compute_backend_service.app_two_backend.self_link
    }

    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_bucket.gcs_backend.self_link
    }
  }
}

resource "google_compute_managed_ssl_certificate" "lb_cert" {
  name = "lb-managed-cert"

  managed {
    domains = [
      var.domain_name,
      var.www_domain_name
    ]
  }
}

resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "lb-https-proxy"
  url_map          = google_compute_url_map.lb_url_map.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.lb_cert.self_link]
}

resource "google_compute_global_forwarding_rule" "https_rule" {
  name                = "lb-https-forwarding-rule"
  target              = google_compute_target_https_proxy.https_proxy.self_link
  port_range          = "443"
  load_balancing_scheme = "EXTERNAL"
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "lb-http-proxy"
  url_map = google_compute_url_map.lb_url_map.self_link
}

resource "google_compute_global_forwarding_rule" "http_rule" {
  name                = "lb-http-forwarding-rule"
  target              = google_compute_target_http_proxy.http_proxy.self_link
  port_range          = "80"
  load_balancing_scheme = "EXTERNAL"
}

output "lb_ip_address" {
  value = google_compute_global_forwarding_rule.https_rule.ip_address
}
