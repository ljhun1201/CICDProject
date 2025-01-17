resource "google_compute_network" "main_vpc" {
  name                    = var.vpc_name
  project                 = var.project_id
  auto_create_subnetworks = false
}

# 예시로 public-subnet, private-subnet 을 나누어 만듦
resource "google_compute_subnetwork" "public_subnet" {
  name                  = "public-subnet"
  ip_cidr_range         = "10.0.0.0/24"
  network               = google_compute_network.main_vpc.self_link
  region                = var.region
  # 모든 외부 IP 허용(AWS의 igw 같은 것. 실제로 igw가 만들어짐)
  private_ip_google_access = false
}

resource "google_compute_subnetwork" "private_subnet" {
  name                  = "private-subnet"
  ip_cidr_range         = "10.0.1.0/24"
  network               = google_compute_network.main_vpc.self_link
  region                = var.region
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
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
}

# 1) Global Address: 내부 IP 범위 예약 (예: 10.3.0.0/16)
resource "google_compute_global_address" "private_ip_range" {
  name          = "cloudsql-private-ip-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main_vpc.self_link
  address       = "10.3.0.0"
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

output "vpc_self_link" {
  value = google_compute_network.main_vpc.self_link
}

output "subnet_self_link" {
  value = google_compute_subnetwork.private_subnet.self_link
}

output "private_subnet_name" {
  value = google_compute_subnetwork.private_subnet.name
}