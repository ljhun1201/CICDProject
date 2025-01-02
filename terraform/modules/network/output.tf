output "vpc_id" {
  value = aws_vpc.eks_vpc.id
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

output "db_endpoint" {
  description = "RDS Endpoint"
  value       = aws_db_instance.mydb.endpoint
}

output "db_password" {
  description = "RDS Password"
  value       = var.db_password
}