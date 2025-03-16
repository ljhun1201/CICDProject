resource "google_compute_network" "main_vpc" {
  name                    = var.vpc_name
  project                 = var.project_id
  auto_create_subnetworks = false
}

# 예시로 public-subnet, private-subnet 을 나누어 만듦
resource "google_compute_subnetwork" "public_subnet" {
  name                  = "public-subnet"
  ip_cidr_range         = "10.10.0.0/24"
  network               = google_compute_network.main_vpc.self_link
  region                = var.region
  # 모든 외부 IP 허용(AWS의 igw 같은 것. 실제로 igw가 만들어짐)
  private_ip_google_access = false
}

resource "google_compute_subnetwork" "private_subnet" {
  name                  = "private-subnet"
  ip_cidr_range         = "10.10.1.0/24"
  network               = google_compute_network.main_vpc.self_link
  region                = var.region
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Cloud NAT (Private Subnet에서 Internet Access 필요 시)
resource "google_compute_router" "nat_router" {
  name    = "nat-router"
  network = google_compute_network.main_vpc.self_link
  region  = var.region
}

resource "google_compute_router_nat" "nat_config" {
  name                               = "cloud-nat"
  router                             = google_compute_router.nat_router.name # NAT를 연결할 Cloud Router를 지정
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY" # 외부 IP를 자동 할당(에페머럴 IP)하도록 설정
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS" # 특정 서브넷(들)에 대해서만 NAT 적용
  
  subnetwork { # 어떤 서브넷에 NAT을 적용시킬 것인가 에 대한 블록
    name                  = google_compute_subnetwork.private_subnet.name 
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"] # 해당 서브넷 내의 모든 내부 IP(사설 IP)에 대해 NAT 적용
  }

  lifecycle {
    prevent_destroy = false  # Router 삭제 허용
  }
}

# 1) Global Address: 내부 IP 범위 예약 (예: 10.200.0.0/16)
resource "google_compute_global_address" "private_ip_range" {
  name          = "cloudsql-private-ip-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main_vpc.self_link
  address       = "10.200.0.0"
}

# 2) Service Networking Connection (VPC Peering) --> 이제, 어떤 관리형 리소스에서 
# google_compute_network.main_vpc.self_link라는 vpc와 peering 하겠다고 선언하면
# 자동으로 그 vpc와 peering 된 '예약된 IP 대역 범위 내'에서 IP 주소를 할당 
resource "google_service_networking_connection" "private_vpc_connection" { 

  network = google_compute_network.main_vpc.self_link
  service = "servicenetworking.googleapis.com"

  # reserved_peering_ranges는 위에서 만든 global address의 name
  reserved_peering_ranges = [
    google_compute_global_address.private_ip_range.name
  ]
}

resource "google_compute_network_peering_routes_config" "gcp_servicenetworking_routes" {
  peering = "servicenetworking-googleapis-com"
  network = "gcp-dr-vpc"

  import_custom_routes = true # Peering된 vpc의 routing 정보를 자신의 대역으로 모두 가져옴. 이게 없으면 GCP Cloud SQL이 AWS에서 온 네트워크(10.0.0.0/16)를 학습하지 못함(모르는 트래픽이라 간주하여 차단.) → AWS에서 Cloud SQL 접근 불가능
  export_custom_routes = true # sql 자신에게 오는 올바른 경로를 내보냄(다른 곳에서 이 경로를 인식 가능)
  
  depends_on = [google_compute_network.main_vpc, google_service_networking_connection.private_vpc_connection]
}

resource "google_compute_firewall" "allow_vpn_ipsec" {
  name    = "allow-vpn-ipsec"
  project = var.project_id
  network = google_compute_network.main_vpc.self_link

  direction = "INGRESS"

  allow {
    protocol = "udp"
    ports    = ["500", "4500"]
  }

  source_ranges = ["0.0.0.0/0"] 

  depends_on = [google_compute_network.main_vpc]
}

resource "google_compute_firewall" "allow_aws_to_cloudsql" {
  name    = "allow-aws-to-cloudsql"
  network = google_compute_network.main_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }

  source_ranges = ["10.0.0.0/16"]  # AWS VPC CIDR
}

resource "google_compute_firewall" "allow_http" { 
  name    = "allow-http-to-https"
  network = google_compute_network.main_vpc.self_link

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

output "gcp_vpc_id" {
  value = google_compute_network.main_vpc.id
}

output "vpc_self_link" {
  value = google_compute_network.main_vpc.self_link
}

output "subnet_self_link" {
  value = google_compute_subnetwork.private_subnet.self_link
}

output "private_subnet_name" {
  value = google_compute_subnetwork.private_subnet.name
}