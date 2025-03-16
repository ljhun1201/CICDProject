terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket         = "terraformstorage3"    # S3 버킷 이름
    key            = "terraform/terraform.tfstate"  # 저장된 state 파일 경로
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-lock"
  }
}

data "terraform_remote_state" "gcp" {
  backend = "gcs"
  config = {
    bucket = "my-terraform-db-info"  # gke/main.tf에서 선언한 것과 동일
    prefix = "cloudsql-state"        # gke/main.tf의 prefix와 동일
  }
}

# ----------------------------
# AWS VPN 설정
# ----------------------------

resource "aws_vpn_gateway" "vpn_gw" {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
  amazon_side_asn = 64512  # AWS 측 BGP ASN

  tags = {
    Name = "aws-vpn-gateway"
  }
}

# (1) GCP HA VPN의 인터페이스 0번 IP를 쓰는 Customer Gateway
resource "aws_customer_gateway" "gcp_ip" {
  bgp_asn    = 65000
  ip_address = google_compute_ha_vpn_gateway.gcp_vpn_gw.vpn_interfaces[0].ip_address
  type       = "ipsec.1"
 
  tags = {
    Name = "gcp-customer-gateway"
  }
}

# (2) CGW에 대해 aws_vpn_connection 생성
resource "aws_vpn_connection" "aws_gcp_vpn" {
  vpn_gateway_id      = aws_vpn_gateway.vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_ip.id
  type                = "ipsec.1"
  static_routes_only  = false # BGP 사용
  tags = {
    Name = "aws-to-gcp-vpn-interface"
  }
}

data "google_compute_subnetwork" "gcp_subnet" {
  name    = "private-subnet"  # GCP의 서브넷 이름
  region  = var.gcp_region
  project = "peppy-arcadia-432311-g5"
}

resource "aws_route" "vpn_route1" {
  route_table_id         = data.terraform_remote_state.network.outputs.private_route_table_id
  destination_cidr_block = "10.200.0.0/16"  # GCP 서브넷 CIDR 자동 입력
  gateway_id             = aws_vpn_gateway.vpn_gw.id
}

resource "aws_route" "vpn_route2" {
  route_table_id         = data.terraform_remote_state.network.outputs.private_route_table_id
  destination_cidr_block = "10.4.0.0/14" # GCP 서브넷 CIDR 자동 입력
  gateway_id             = aws_vpn_gateway.vpn_gw.id
}

# ----------------------------
# GCP VPN 설정
# ----------------------------

# 1️⃣ GCP VPN Gateway 생성
# 1. Classic VPN GateWay(google_compute_vpn_gateway), 2. HA VPN GateWay(google_compute_ha_vpn_gateway)
resource "google_compute_ha_vpn_gateway" "gcp_vpn_gw" {
  name    = "gcp-vpn-gateway"
  region  = var.gcp_region
  project = var.project_id
  network = data.terraform_remote_state.gcp.outputs.gcp_vpc_id

  vpn_interfaces {
    id = 0
  }
}

# 2️⃣ GCP Cloud Router (BGP 설정)
resource "google_compute_router" "gcp_router" {
  name    = "gcp-router"
  project = var.project_id
  region  = var.gcp_region
  network = data.terraform_remote_state.gcp.outputs.gcp_vpc_id

  bgp {
    asn = 65000  # GCP 측 BGP ASN (AWS와 일치해야 함)
  }
}

# AWS 쪽 "외부 VPN Gateway"를 GCP에서 정의
resource "google_compute_external_vpn_gateway" "aws_external_gw" {
  name            = "aws-external-gateway"
  project         = var.project_id
  redundancy_type = "TWO_IPS_REDUNDANCY"  # AWS는 터널 2개

  interface {
    id         = 0
    ip_address = aws_vpn_connection.aws_gcp_vpn.tunnel1_address #상대 터널의 public IP
  }
  interface {
    id         = 1
    ip_address = aws_vpn_connection.aws_gcp_vpn.tunnel2_address
  }
}

# 3️⃣ AWS의 첫 번째 VPN 터널과 연결
resource "google_compute_vpn_tunnel" "vpn_tunnel_1" {
  name                  = "aws-to-gcp-vpn-1"
  project = var.project_id
  region                = var.gcp_region

 # GCP쪽 HA VPN 게이트웨이
  vpn_gateway           = google_compute_ha_vpn_gateway.gcp_vpn_gw.id
  vpn_gateway_interface = 0  # interface 0 사용

  # AWS 쪽 External Gateway
  peer_external_gateway         = google_compute_external_vpn_gateway.aws_external_gw.id
  peer_external_gateway_interface = 0  # AWS IP(터널1)와 연결

  shared_secret         = aws_vpn_connection.aws_gcp_vpn.tunnel1_preshared_key
  ike_version           = 2
  router                = google_compute_router.gcp_router.id
}

# 4️⃣ AWS의 두 번째 VPN 터널과 연결
resource "google_compute_vpn_tunnel" "vpn_tunnel_2" {
  name                  = "aws-to-gcp-vpn-2"
  project = var.project_id
  region                = var.gcp_region
  
  vpn_gateway           = google_compute_ha_vpn_gateway.gcp_vpn_gw.id
  vpn_gateway_interface = 0  # interface 0 사용

  peer_external_gateway         = google_compute_external_vpn_gateway.aws_external_gw.id
  peer_external_gateway_interface = 1  # AWS IP(터널2)와 연결

  shared_secret         = aws_vpn_connection.aws_gcp_vpn.tunnel2_preshared_key
  ike_version           = 2
  router                = google_compute_router.gcp_router.id
}

# 5️⃣ 첫 번째 터널을 위한 Cloud Router 인터페이스
resource "google_compute_router_interface" "aws_router_interface_1" {
  name       = "aws-router-interface-1"
  project = var.project_id
  router     = google_compute_router.gcp_router.name
  region     = var.gcp_region
  vpn_tunnel = google_compute_vpn_tunnel.vpn_tunnel_1.id
  ip_range   = "${aws_vpn_connection.aws_gcp_vpn.tunnel1_cgw_inside_address}/30"  # AWS 터널 1과 동일한 내부 IP 범위
}

# 6️⃣ 두 번째 터널을 위한 Cloud Router 인터페이스
resource "google_compute_router_interface" "aws_router_interface_2" {
  name       = "aws-router-interface-2"
  project = var.project_id
  router     = google_compute_router.gcp_router.name
  region     = var.gcp_region
  vpn_tunnel = google_compute_vpn_tunnel.vpn_tunnel_2.id
  ip_range   = "${aws_vpn_connection.aws_gcp_vpn.tunnel2_cgw_inside_address}/30"  # AWS 터널 2와 동일한 내부 IP 범위
}

# 7️⃣ 첫 번째 터널 BGP 피어링 (AWS 터널 1과 연결)
resource "google_compute_router_peer" "aws_bgp_peer_1" {
  name         = "aws-bgp-peer-1"
  project = var.project_id
  router       = google_compute_router.gcp_router.name
  region       = var.gcp_region

  peer_ip_address = aws_vpn_connection.aws_gcp_vpn.tunnel1_vgw_inside_address  # AWS 터널 1의 내부 IP
  peer_asn        = 64512  # AWS 측 BGP ASN
  advertised_route_priority = 100
  interface    = google_compute_router_interface.aws_router_interface_1.name 

   # 광고 모드 CUSTOM으로 바꿔야 수동 입력이 가능
  advertise_mode = "CUSTOM"

  # GCP → AWS 쪽으로 광고할 IP 목록
  advertised_ip_ranges {
    range = "10.200.0.0/16"
  }
  # 필요 시 다른 subnet도 추가
  advertised_ip_ranges {
    range = "10.10.0.0/24"
  }
  advertised_ip_ranges {
    range = "10.10.1.0/24"
  }
  advertised_ip_ranges {
    range = "10.4.0.0/14"
  }
}

# 8️⃣ 두 번째 터널 BGP 피어링 (AWS 터널 2와 연결)
resource "google_compute_router_peer" "aws_bgp_peer_2" {
  name         = "aws-bgp-peer-2"
  project = var.project_id
  router       = google_compute_router.gcp_router.name
  region       = var.gcp_region

  peer_ip_address = aws_vpn_connection.aws_gcp_vpn.tunnel2_vgw_inside_address  # AWS 터널 2의 내부 IP
  peer_asn        = 64512  # AWS 측 BGP ASN
  advertised_route_priority = 100
  interface    = google_compute_router_interface.aws_router_interface_2.name 

   # 광고 모드 CUSTOM으로 바꿔야 수동 입력이 가능
  advertise_mode = "CUSTOM"

  # GCP → AWS 쪽으로 광고할 IP 목록
  advertised_ip_ranges {
    range = "10.200.0.0/16"
  }
  # 필요 시 다른 subnet도 추가
  advertised_ip_ranges {
    range = "10.10.0.0/24"
  }
  advertised_ip_ranges {
    range = "10.10.1.0/24"
  }
  advertised_ip_ranges {
    range = "10.4.0.0/14"
  }
}

# AWS VPC 정보 가져오기
data "aws_vpc" "eks_vpc" {
  id = data.terraform_remote_state.network.outputs.vpc_id
}

resource "google_compute_route" "aws_routes" {
  project = var.project_id
  name        = "gcp-to-aws-route"  # CIDR마다 다른 이름 설정
  network = data.terraform_remote_state.gcp.outputs.gcp_vpc_id
  dest_range  = "10.0.0.0/16"  # 각 Private Subnet CIDR을 dest_range로 설정
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.vpn_tunnel_1.id
  priority    = 1000
}

resource "google_compute_route" "aws_routes_backup" {
  project = var.project_id
  name        = "gcp-to-aws-route-backup"  # CIDR마다 다른 이름 설정
  network = data.terraform_remote_state.gcp.outputs.gcp_vpc_id
  dest_range  = "10.0.0.0/16"  # 각 Private Subnet CIDR을 dest_range로 설정
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.vpn_tunnel_2.id
  priority    = 2000
}

/*
# 9️⃣ AWS로 가는 트래픽 라우팅 (BGP 경로를 사용)
resource "google_compute_route" "aws_routes" {
  project = var.project_id
  for_each    = toset(data.terraform_remote_state.network.outputs.private_subnet_cidrs)  # 모든 Private Subnet CIDR 사용
  name        = "gcp-to-aws-route-${replace(replace(each.value, "/", "-"), ".", "-")}"  # CIDR마다 다른 이름 설정
  network = data.terraform_remote_state.gcp.outputs.gcp_vpc_id
  dest_range  = each.value  # 각 Private Subnet CIDR을 dest_range로 설정
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.vpn_tunnel_1.id
  priority    = 1000
}

#  🔟 두 번째 터널을 예비 경로로 설정
resource "google_compute_route" "aws_routes_backup" {
  project = var.project_id
  for_each    = toset(data.terraform_remote_state.network.outputs.private_subnet_cidrs)  # 모든 Private Subnet CIDR 사용
  name        = "gcp-to-aws-route-backup-${replace(replace(each.value, "/", "-"), ".", "-")}"  # CIDR마다 다른 이름 설정
  network = data.terraform_remote_state.gcp.outputs.gcp_vpc_id
  dest_range  = each.value  # 각 Private Subnet CIDR을 dest_range로 설정
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.vpn_tunnel_2.id
  priority    = 2000
}
*/