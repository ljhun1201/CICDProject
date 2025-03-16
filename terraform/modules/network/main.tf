# VPC 생성
resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "eks-vpc"
  }
}

# 퍼블릭 서브넷 생성 (ALB용)
resource "aws_subnet" "public_subnets" {
  count                   = 2
  
  # 서브넷이 생성될 vpc 지정
  vpc_id                  = aws_vpc.eks_vpc.id
  
  # vpc의 cidr block(첫 번째 인자)의 넷마스크에서 (두 번째 인자) 만큼 더한 규모의 서브넷을 차례대로 생성(count.index = 0 --> 10.0.0.0/24, count.index = 1 --> 10.0.1.0/24)
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index) 
  
  # element 함수: 배열의 요소를 index 차례대로 가져옴(배열의 길이: 2 --> count.index = 0, 1 --> arr[0], arr[1])
  availability_zone       = element(["ap-northeast-2a", "ap-northeast-2c"], count.index)

  # map_public_ip_launch: true일 경우, public subnet에 할당되는 인스턴스에는 '자동으로 public IP 할당'
  map_public_ip_on_launch = true
  
  tags = {
    Name = "eks-public-subnet-${count.index}"
    "kubernetes.io/role/elb" = "1" # eks가 Ingress 기반 public LB를 배포할 때 할당될 subnet으로 자동 선택됨.
  }
}

# 프라이빗 서브넷 생성 (EKS용)
resource "aws_subnet" "private_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index + 2)
  availability_zone       = element(["ap-northeast-2a", "ap-northeast-2c"], count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "eks-private-subnet-${count.index}"
  }
}

# 인터넷 게이트웨이 생성
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  }
}

# 퍼블릭 라우팅 테이블 생성 및 연결
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  # route 블록: 라우팅 테이블에 특정 목적지에 대해 Internet Gateway를 중간 경로로 지정
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }
  
  tags = {
    Name = "eks-public-route-table"
  }
}

# 생성한 route table을 vpc의 각 public subnet에 할당
resource "aws_route_table_association" "public_subnet_associations" {
  count          = length(aws_subnet.public_subnets[*].id) # aws_subnet.public_subnets[*].id --> 모든 public subnet의 id들을 배열로 불러와서 그 배열의 길이를 출력
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index) # 각 count.index 마다 나온 public subnet의 id 마다 
  route_table_id = aws_route_table.public_route_table.id # public route table을 할당
}

# Elastic IP(고정된 IP)
resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "eks-nat-eip"
  }
}

# NAT 게이트웨이 생성 (프라이빗 서브넷의 인터넷 액세스용, 여기서는 aws.-_subnet.publicsubnets[0]에 생성)
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat.id
  subnet_id     = element(aws_subnet.public_subnets[*].id, 0)

  tags = {
    Name = "eks-nat-gateway"
  }
}

# 프라이빗 라우팅 테이블 생성 및 연결
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "eks-private-route-table"
  }
}

resource "aws_route_table_association" "private_subnet_associations" {
  count          = length(aws_subnet.private_subnets[*].id)
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = aws_route_table.private_route_table.id
}

# ALB 보안 그룹 생성
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 20000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 이 보안그룹은 나가는 트래픽에 대해서는 모든 포트번호와 모든 protocol을 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

# EKS 노드 그룹용 보안 그룹 생성
resource "aws_security_group" "eks_node_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 20000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-node-sg"
  }
}

# EKS 클러스터
resource "aws_eks_cluster" "eks_cluster" {
  name     = "eks-cluster"
  role_arn = "arn:aws:iam::481665107235:role/eks-cluster-role"

  vpc_config {

    # eks 클러스터의 영향을 받는 subnet 들
    subnet_ids = concat(
      aws_subnet.private_subnets[*].id
    )
    security_group_ids = [aws_security_group.eks_node_sg.id]
  }

  tags = {
    Name = "eks-cluster"
  }
}

# terraform에 생성된 aws eks에 관한 정보를 인식시킴
resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.eks_cluster.name} --region ap-northeast-2"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

# aws eks의 클러스터의 인증 정보를 가져옴(나중에 eks 클러스터 안에 deployment나 pod 등의 자원을 조작하기 위해 클러스터에 접속할 때 사용)
data "aws_eks_cluster_auth" "eks_auth" {
  name = aws_eks_cluster.eks_cluster.name
}

resource "aws_launch_template" "eks_launch_template" {
  name_prefix   = "eks-node-launch-template"
  image_id      = "ami-0ea66fbd857bd1152"
  instance_type = "t3.medium"
  key_name      = "mykey"

  # network_interfaces 블록은 제거

  # 새로운 리소스 생성 후, 기존 리소스 삭제
  lifecycle {
    create_before_destroy = true
  }
  
  # eks 클러스터 '노드'에 한해서 public ip를 할당하지 않음
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.eks_node_sg.id]
  }

  # 태그 설정에 클러스터 이름 추가
  # 이 리소스(노드)는 특정 이름을 가진 eks cluster에 '종속된' 리소스임을 Ingress LB와 EKS가 감지
  # (이것을 지정해야 Ingress LB와 Auto Scaling(오케스트레이션)이 해당 리소스를 감지하고 작동함)
  tags = {
    Name = "eks-node-launch-template"
    "kubernetes.io/cluster/${aws_eks_cluster.eks_cluster.name}" = "owned"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    /etc/eks/bootstrap.sh ${aws_eks_cluster.eks_cluster.name} \
      --apiserver-endpoint '${aws_eks_cluster.eks_cluster.endpoint}' \
      --b64-cluster-ca '${aws_eks_cluster.eks_cluster.certificate_authority[0].data}'
    EOF
  )
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks-node-group"
  node_role_arn   = "arn:aws:iam::481665107235:role/eks-node-role"
  subnet_ids      = aws_subnet.private_subnets[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3 
    min_size     = 1
  }

  launch_template {
    id      = aws_launch_template.eks_launch_template.id
    version = "$Latest"
  }

  # 기본 보안 설정 허용
  depends_on = [
    aws_eks_cluster.eks_cluster
  ]

  tags = {
    Name = "eks-node-group"
    "kubernetes.io/cluster/${aws_eks_cluster.eks_cluster.name}" = "owned"
  }
}

# ----------------------------
# 1) RDS용 Subnet Group
# ----------------------------
resource "aws_db_subnet_group" "this" {
  name        = "mydb-subnet-group"
  description = "Subnet group for my RDS"

  subnet_ids = aws_subnet.private_subnets[*].id  # private 서브넷들
  tags = {
    Name = "mydb-subnet-group"
  }
}

# ----------------------------
# 2) RDS 보안그룹
# ----------------------------
resource "aws_security_group" "rds_sg" {
  name   = "rds-sg"
  vpc_id = aws_vpc.eks_vpc.id

  # EKS Node SG에서만 접근 허용 (MySQL: 3306)
  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # security_groups  = [aws_security_group.eks_node_sg.id]
    description      = "Allow MySQL from EKS node group"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# ----------------------------
# 3) db 파라미터 그룹 생성
# ----------------------------

# 1) MySQL 8.0용 Custom Parameter Group
resource "aws_db_parameter_group" "mydb_custom" {
  name   = "mydb-custom-params"
  family = "mysql8.0"
  description = "Custom parameter group for MySQL 8, enabling ROW binlog"

  parameter {
    name         = "binlog_format"
    value        = "ROW"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "binlog_row_image"
    value        = "FULL"
    apply_method = "pending-reboot"
  }

  # 필요 시, DMS 3.4.7 이하 버전 호환 위해 binlog_checksum=NONE 설정
  # parameter {
  #   name         = "binlog_checksum"
  #   value        = "NONE"
  #   apply_method = "pending-reboot"
  # }

  # 함수/트리거 등 binlog에 필요한 경우
  # parameter {
  #  name         = "log_bin_trust_function_creators"
  #  value        = "1"
  #  apply_method = "pending-reboot"
  # }
}

# ----------------------------
# 4) RDS 인스턴스
# ----------------------------

resource "aws_db_instance" "mydb" {
  identifier             = "mydb-instance"
  allocated_storage      = 20 # (GB) 단위
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name            # 실제 DB 스키마 이름(RDS 인스턴스 생성 시 자동으로 "mydb" 데이터베이스 생성)
  username               = var.user_name     # 
  password               = var.db_password   # Terraform 변수 사용 (예: -var="db_password=비밀번호")
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true

  # 자동 백업 활성화 (Retention = 1일), log_bin 활성화에 필요
  backup_retention_period = 1

  # 커스텀 파라미터 그룹 할당
  parameter_group_name = aws_db_parameter_group.mydb_custom.name

  tags = {
    Name = "mydb-instance"
  }

  depends_on = [
    aws_db_subnet_group.this,
    aws_security_group.rds_sg,
    aws_db_parameter_group.mydb_custom
  ]
}