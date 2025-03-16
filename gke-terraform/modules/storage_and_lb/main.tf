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

resource "google_compute_url_map" "lb_url_map" {
  name            = "lb-url-map"
  # default_service = google_compute_backend_bucket.gcs_backend.self_link

  host_rule {
    hosts        = [var.domain_name, var.www_domain_name]
    path_matcher = "web-paths"
  }

  path_matcher {
    name            = "web-paths"
    default_service = google_compute_backend_bucket.gcs_backend.self_link

    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_bucket.gcs_backend.self_link
    }
  }

  # HTTP 요청을 HTTPS로 리디렉션
  default_url_redirect {
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    https_redirect         = true
    strip_query            = false 
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
