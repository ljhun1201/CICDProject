# 마이크로서비스 기반의 멀티클라우드 환경에서의 장애대응 솔루션 및 CICD Project

멀티 클라우드 기반 인프라와 CI/CD 파이프라인을 구축한 프로젝트입니다.  
AWS와 GCP 인프라를 모두 구성하고, GitHub Actions를 통해 ECR 및 GCR에 Docker 이미지를 빌드/푸시하는 자동화된 배포 파이프라인을 포함하고 있습니다.
또한, ECR 및 GCR에 자동으로 배포한 Docker 이미지를 EKS 및 GKE에 set 하는 자동화 파이프라인도 포함되어있습니다.

---

## 🌐 프로젝트 개요

- **하이브리드 클라우드 구성**
  - `vpn-terraform/`: AWS RDS와 Cloud SQL의 데이터 동기화를 위해서, AWS Site-to-Site VPN을 통한 **AWS VPC와 GCP VPC를 연결**하는 설정을 포함합니다.
  - `terraform/`: AWS에 구성한 k8s 마이크로서비스 기반 인프라를 위한 코드입니다.
  - `gke-terraform/`: AWS 인프라와 똑같은 환경을 GCP GKE 기반 인프라로 정의한 Terraform 코드입니다.

- **백엔드 애플리케이션**
  - `backend-root/` 하위에 2개의 백엔드 서비스 존재:
    - `user-registration-service`: 사용자 등록 API
    - `user-login-service`: 사용자 로그인 API

---

## ⚙️ CI/CD 파이프라인

CI/CD는 GitHub Actions를 활용하며, `main` 브랜치에 push 이벤트가 발생할 때 자동으로 실행됩니다.

### 주요 기능

1. AWS 및 GCP 인증
2. Docker 이미지 빌드
3. ECR 및 GCR에 이미지 푸시
4. GKE 및 EKS 클러스터에 자동 배포

### GitHub Actions Workflow 요약

- AWS OIDC로 IAM 역할 연결
- GCP 서비스 계정 인증 (Secrets 사용)
- Docker 이미지 빌드 및 태깅
- Amazon ECR & Google GCR 이미지 푸시
- GKE, EKS 배포 업데이트
