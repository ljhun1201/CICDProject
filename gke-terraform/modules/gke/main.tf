resource "google_container_cluster" "gke_cluster" {
  name               = var.cluster_name
  project            = var.project_id
  location           = var.region
  network            = var.network_name
  subnetwork         = var.subnetwork_name

  remove_default_node_pool = false
  initial_node_count       = 1
  deletion_protection      = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name           = "${var.cluster_name}-nodepool"
  project        = var.project_id
  cluster        = google_container_cluster.gke_cluster.name
  location       = var.region
  node_locations = var.zones
  node_count     = 2

  node_config {
    machine_type = "e2-medium"
    image_type   = "COS_CONTAINERD"
    disk_size_gb = 20
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "null_resource" "delete_default_node_pool" {
  provisioner "local-exec" {
    command = <<EOT
      gcloud container node-pools delete default-pool \
      --cluster ${google_container_cluster.gke_cluster.name} \
      --region ${var.region} --quiet
    EOT
  }
  triggers = {
    cluster_name = google_container_cluster.gke_cluster.name
  }
  depends_on = [google_container_cluster.gke_cluster, google_container_node_pool.primary_nodes]
}

output "cluster_endpoint" {
  value = google_container_cluster.gke_cluster.endpoint
}

output "cluster_ca_certificate" {
  value = google_container_cluster.gke_cluster.master_auth.0.cluster_ca_certificate
}

output "cluster_name" {
  value = google_container_cluster.gke_cluster.name
}

# MIG 정보를 수동으로 추출 (이름과 zone)
output "mig_info" {
  value = [
    {
      name = "${google_container_node_pool.primary_nodes.name}-grp"
      zone = "${var.region}-a"
    },
    {
      name = "${google_container_node_pool.primary_nodes.name}-grp"
      zone = "${var.region}-b"
    }
  ]
}