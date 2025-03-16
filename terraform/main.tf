provider "aws" {
  region = "ap-northeast-2"
}

# CloudFront용 ACM을 위한 us-east-1 리전 프로바이더 설정
provider "aws" {
  alias  = "us_east_1"     # 별칭을 지정하여 us-east-1 리전 분리
  region = "us-east-1"
}

module "s3_and_cloudfront" {
  source = "./modules/s3_and_cloudfront"

  providers = {
    aws       = aws
    aws.us_east_1 = aws.us_east_1
  }
  
  alb_dns_name = data.local_file.alb_dns_name.content
  rds_endpoint = module.network.rds_endpoint
  
  depends_on = [null_resource.deploy_kubernetes_resources]
}

module "network" {
  source = "./modules/network"
}

resource "null_resource" "deploy_kubernetes_resources" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
cd modules/alb_ingress && terraform apply -auto-approve \
  -var "vpc_id=${module.network.vpc_id}" \
  -var "private_subnet_ids=[${join(",", module.network.private_subnet_ids)}]" \
  -var "public_subnet_ids=[${join(",", module.network.public_subnet_ids)}]" \
  -var "eks_cluster_name=${module.network.eks_cluster_name}" \
  -var "eks_cluster_endpoint=${module.network.eks_cluster_endpoint}" \
  -var "eks_cluster_ca=${module.network.eks_cluster_ca}" \
  -var "eks_auth=${module.network.eks_auth}" \
  -var "oidc_issuer_url=${module.network.oidc_issuer_url}" \
  -var "alb_security_group_id=${module.network.alb_security_group_id}" \
  -var "db_endpoint=${module.network.db_endpoint}" \
  -var "db_password=${module.network.db_password}" \
  && \

# ALB 생성 대기
echo "Waiting for ALB to be created..."
aws elbv2 wait load-balancer-available --region ap-northeast-2

# ALB DNS 가져오기
ALB_DNS=$(aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query 'LoadBalancers[*].DNSName' --output text | head -n 1)

if [[ -z "$ALB_DNS" ]]; then
  echo "Error: ALB DNS not found!" && exit 1
fi

echo "ALB DNS: $ALB_DNS"

# ALB ARN 가져오기
ALB_ARN=$(aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query 'LoadBalancers[?DNSName==`'$ALB_DNS'`].LoadBalancerArn' --output text)

if [[ -z "$ALB_ARN" ]]; then
  echo "Error: ALB ARN not found!" && exit 1
fi

echo "ALB ARN: $ALB_ARN"

# ALB 리스너 ARN 가져오기
LISTENER_ARN=$(aws elbv2 describe-listeners --region ap-northeast-2 \
  --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[?Port==`443`].ListenerArn' --output text)

if [[ -z "$LISTENER_ARN" ]]; then
  echo "Error: ALB Listener not found!" && exit 1
fi

echo "ALB Listener ARN: $LISTENER_ARN"

# ✅ ALB에 연결된 Target Group을 직접 조회
TG_ARNS=$(aws elbv2 describe-target-groups --region ap-northeast-2 \
  --query 'TargetGroups[*].{Name:TargetGroupName, Arn:TargetGroupArn}' --output json)

if [[ -z "$TG_ARNS" ]]; then
  echo "Error: No Target Groups found!" && exit 1
fi

APP_ONE_TG_ARN=$(echo $TG_ARNS | jq -r '.[] | select(.Name | contains("appone")) | .Arn')
APP_TWO_TG_ARN=$(echo $TG_ARNS | jq -r '.[] | select(.Name | contains("apptwo")) | .Arn')

if [[ -z "$APP_ONE_TG_ARN" || -z "$APP_TWO_TG_ARN" ]]; then
  echo "Error: Target Groups not found!" && exit 1
fi

echo "Found Target Groups:"
echo "APP_ONE_TG_ARN=$APP_ONE_TG_ARN"
echo "APP_TWO_TG_ARN=$APP_TWO_TG_ARN"

# ALB 라우팅 규칙 생성
echo "Creating ALB Routing Rules..."

# /app-one/register 요청 -> app_one_service로 라우팅
aws elbv2 create-rule \
  --listener-arn $LISTENER_ARN \
  --priority 100 \
  --conditions '[{"Field":"host-header","HostHeaderConfig":{"Values":["'$ALB_DNS'"]}}, {"Field":"path-pattern","PathPatternConfig":{"Values":["/app-one/register"]}}]' \
  --actions '[{"Type":"forward","TargetGroupArn":"'$APP_ONE_TG_ARN'"}]'

# /app-two/login 요청 -> app_two_service로 라우팅
aws elbv2 create-rule \
  --listener-arn $LISTENER_ARN \
  --priority 110 \
  --conditions '[{"Field":"host-header","HostHeaderConfig":{"Values":["'$ALB_DNS'"]}}, {"Field":"path-pattern","PathPatternConfig":{"Values":["/app-two/login"]}}]' \
  --actions '[{"Type":"forward","TargetGroupArn":"'$APP_TWO_TG_ARN'"}]'

# /healthz 요청 -> app_one_service로 라우팅
aws elbv2 create-rule \
  --listener-arn $LISTENER_ARN \
  --priority 120 \
  --conditions '[{"Field":"host-header","HostHeaderConfig":{"Values":["'$ALB_DNS'"]}}, {"Field":"path-pattern","PathPatternConfig":{"Values":["/healthz"]}}]' \
  --actions '[{"Type":"forward","TargetGroupArn":"'$APP_ONE_TG_ARN'"}]'

echo "ALB Routing Rules Successfully Created!"

# 모든 ALB 리스트를 가져와서 파일에 저장
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[*].DNSName' \
  --output text | head -n 1 | sed -z 's/\n//g' > ../../alb_dns_name.txt && \
if [ -s ../../alb_dns_name.txt ]; then
  echo "ALB DNS successfully written to alb_dns_name.txt"
else
  echo "Failed to retrieve ALB DNS name" && exit 1
fi

EOT
  }

  depends_on = [module.network]
}

#자체적으로 provider를 가지고 있는 경우, module 블록으로 하면 depends_on 설정이 허용되지 않고, provider를 여기에서 정의하자니 그 provider의 속성 값이 이 리소스의 tf 파일의 변수값을 참조해야하므로 그냥 null_resource로 함.
data "local_file" "alb_dns_name" {
  filename = "${path.root}/alb_dns_name.txt"
  depends_on = [null_resource.deploy_kubernetes_resources]
}

module "dms" {
  source = "./modules/dms"

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  gcs_bucket_name    = "my-terraform-db-info"
  gcs_state_prefix   = "cloudsql-state"

  # Cloud SQL root password (민감정보는 TF var or SSM 등에서)
  cloudsql_password  = var.cloudsql_password

  # RDS endpoint & creds
  rds_endpoint = module.network.db_endpoint    # 예: aws_db_instance.mydb.endpoint (만약에 output 했으면)
  rds_password = module.network.db_password    # RDS password
  rds_name = module.network.db_name
  rds_user_name = module.network.user_name

  depends_on = [module.s3_and_cloudfront]
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "private_route_table_id" {
  value = module.network.private_route_table_id
}

output "rds_endpoint" {
  value = module.network.rds_endpoint
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "private_subnet_cidrs" {
  value = module.network.private_subnet_cidrs
}