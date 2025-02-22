output "vpc_id" {
  value = aws_vpc.eks_vpc.id
}

output "private_route_table_id" {
  value = aws_route_table.private_route_table.id
}

output "rds_endpoint" {
  value = aws_db_instance.mydb.endpoint
}

output "private_subnet_cidrs" {
  description = "AWS Private Subnet CIDRs"
  value       = aws_subnet.private_subnets[*].cidr_block  # Private 서브넷들의 CIDR
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnets[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public_subnets[*].id
}

output "eks_cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "eks_cluster_ca" {
  value = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}

output "eks_auth" {
  value = data.aws_eks_cluster_auth.eks_auth.token
}

output "oidc_issuer_url" {
  value = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

output "alb_security_group_id" {
  value = aws_security_group.alb_sg.id
}

output "db_name" {
  value       = var.db_name
}

output "db_endpoint" {
  description = "RDS Endpoint"
  value       = replace(aws_db_instance.mydb.endpoint, ":3306", "")
}

output "db_password" {
  description = "RDS Password"
  value       = var.db_password
}

output "user_name" {
  value     = var.user_name
}