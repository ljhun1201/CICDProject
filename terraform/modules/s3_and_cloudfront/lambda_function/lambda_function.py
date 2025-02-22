import boto3
import os

route53 = boto3.client("route53")
health = boto3.client("route53")

# 환경 변수에서 값 로드
ALB_HEALTH_CHECK_ID = os.environ["ALB_HEALTH_CHECK_ID"]
EKS_HEALTH_CHECK1_ID = os.environ["EKS_HEALTH_CHECK1_ID"]
EKS_HEALTH_CHECK2_ID = os.environ["EKS_HEALTH_CHECK2_ID"]
RDS_HEALTH_CHECK_ID = os.environ["RDS_HEALTH_CHECK_ID"]
ROUTE53_ZONE_ID = os.environ["ROUTE53_ZONE_ID"]

# ✅ 백엔드 API (api.ljhun.shop) - 가중치 변경 대상
AWS_API_RECORD_ID = os.environ["AWS_API_RECORD_ID"]
GCP_API_RECORD_ID = os.environ["GCP_API_RECORD_ID"]
ROUTE53_API_DOMAIN = os.environ["ROUTE53_API_DOMAIN"]

# GCP 백엔드 API IP 주소
GCP_API_IP = os.environ["GCP_API_IP"]

AWS_WEIGHT = 50  # 정상 상태 시 AWS 가중치
GCP_WEIGHT = 50  # 정상 상태 시 GCP 가중치
FAILOVER_WEIGHT = 0  # AWS 장애 시 AWS 가중치
RECOVERY_WEIGHT = 50  # 복구 시 원래 값

def check_health(health_check_id):
    """Route 53 헬스 체크 상태 확인"""
    response = health.get_health_check_status(HealthCheckId=health_check_id)
    return response["HealthCheckObservations"][0]["StatusReport"]["Status"]

def update_route53_weight(weight_aws, weight_gcp):
    """Route 53 레코드의 가중치를 업데이트"""
    changes = [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": ROUTE53_API_DOMAIN,
                "Type": "A",
                "SetIdentifier": AWS_API_RECORD_ID,
                "Weight": weight_aws,
                "AliasTarget": {
                    "HostedZoneId": os.environ["CLOUDFRONT_HOSTED_ZONE_ID"],
                    "DNSName": os.environ["CLOUDFRONT_DNS_NAME"],
                    "EvaluateTargetHealth": False,
                },
            },
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": ROUTE53_API_DOMAIN,
                "Type": "A",
                "SetIdentifier": GCP_API_RECORD_ID,
                "Weight": weight_gcp,
                "TTL": 300,
                "ResourceRecords": [{"Value": GCP_API_IP}],
            },
        },
    ]

    # 변경 요청 실행
    route53.change_resource_record_sets(
        HostedZoneId=ROUTE53_ZONE_ID,
        ChangeBatch={"Changes": changes}
    )

    print(f"✅ Route 53 업데이트 완료: AWS {weight_aws}, GCP {weight_gcp}")

def lambda_handler(event, context):
    alb_status = check_health(ALB_HEALTH_CHECK_ID)
    eks1_status = check_health(EKS_HEALTH_CHECK1_ID)
    eks2_status = check_health(EKS_HEALTH_CHECK2_ID)
    rds_status = check_health(RDS_HEALTH_CHECK_ID)

    print(f"ALB 상태: {alb_status}, EKS1 상태: {eks1_status}, EKS2 상태: {eks2_status}, RDS 상태: {rds_status}")

    if "Unhealthy" in [alb_status, eks1_status, eks2_status, rds_status]:
        print("🚨 AWS 장애 감지 → GCP로 트래픽 이동")
        update_route53_weight(FAILOVER_WEIGHT, 100)
    else:
        print("✅ AWS 정상 → 가중치 복구")
        update_route53_weight(RECOVERY_WEIGHT, RECOVERY_WEIGHT)

    return {"statusCode": 200, "body": "Route 53 weights updated successfully"}
