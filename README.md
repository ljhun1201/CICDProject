# 🧭 마이크로서비스 기반의 멀티클라우드 장애 대응 솔루션 및 CI/CD 프로젝트

이 프로젝트는 **AWS와 GCP의 멀티클라우드 환경**에서 **Kubernetes 기반 백엔드 마이크로서비스**를 배포하고,  
**Site-to-Site VPN**, **데이터 실시간 복제**, **정적 웹 프론트엔드 배포**, **CI/CD 자동화**를 구현한 인프라 프로젝트입니다.

---

## 🌐 프로젝트 구성 개요

### ✅ 인프라 구성

#### 🔸 AWS
- **Route 53**: 도메인 이름 관리
- **CloudFront + ACM**: HTTPS 인증 및 글로벌 콘텐츠 전송
- **ALB**: k8s deployment에 따른른 트래픽 라우팅(ingress)
- **S3**: 정적 웹 프론트엔드 배포
- **EKS**: 백엔드 서비스 배포
- **RDS**: 사용자 데이터 저장
- **DMS**: 데이터 복제, 동기화
- **Site-to-Site VPN Gateway**: GCP와 연결

#### 🔹 GCP
- **Cloud CDN + Google-managed SSL Certificates**: 글로벌 콘텐츠 전송
- **Cloud LoadBalancer**: 프론트엔드와 백엔드(ingress)로의 트래픽 라우팅
- **GCS**: GCP 프론트엔드 코드 저장소
- **GKE**: 백엔드 서비스 미러 배포
- **Cloud SQL**: 백엔드 데이터베이스
- **Cloud VPN + Router**: AWS와 VPN 연결

---

## 📦 애플리케이션 구성

### 🔧 백엔드 마이크로서비스 (Docker 기반)
- `user-registration-service` (Flask)
- `user-login-service` (Flask)

### 🖼️ 프론트엔드
- `html/` 디렉토리 내 정적 리소스 (S3 + CloudFront 통해 배포)

---

## ⚙️ CI/CD 파이프라인 (GitHub Actions)

### 🔄 동작 흐름
1. 코드 Push 시 GitHub Actions workflow 트리거
2. Docker 이미지 빌드 (`user-registration-service`, `user-login-service`)
3. ECR / GCR에 이미지 푸시
4. `kubectl apply`로 EKS / GKE에 자동 배포

### 🔐 보안
- AWS OIDC → IAM Role 연결
- GCP 서비스 계정 키 → GitHub Secrets에 저장

---

## 📁 디렉토리 구조

```
CICDProject/
├── .github/workflows/        # GitHub Actions 워크플로우
├── backend-root/             # 2개의 백엔드 서비스 (Flask 기반)
├── html/                     # 프론트엔드 정적 리소스
├── terraform/                # AWS 인프라 (EKS, RDS 등)
├── gke-terraform/            # GCP 인프라 (GKE, Cloud SQL 등)
├── vpn-terraform/            # AWS -- GCP VPN 구성
```

---

## 🛠 사용 기술 스택

### ☁️ 인프라 & 클라우드
- **AWS**: Route 53, CloudFront, ACM, S3, EKS, RDS, DMS, Site-to-Site VPN
- **GCP**: Cloud CDN, Google-managed SSL Certificates, GCS, GKE, Cloud SQL, Cloud VPN

### 🧱 인프라 코드 (IaC)
- **Terraform**: AWS, GCP 전체 인프라 구성 및 모듈화

### 🔄 CI/CD 자동화
- **GitHub Actions**: CI/CD 파이프라인 구성
- **Docker**: 백엔드 이미지 빌드 및 배포
- **ECR / GCR**: AWS/GCP 이미지 저장소
- **EKS / GKE**: AWS/GCP 이미지를 각 deployment에 배포

### 🔒 인증 & 보안
- **AWS OIDC 연동 IAM Role**: GitHub Actions에서 안전한 권한 부여
- **GCP Service Account + Secrets**: GitHub Secrets를 통한 인증 키 관리

### 🌐 네트워크
- **Site-to-Site VPN**: AWS VPC ↔ GCP VPC 간 프라이빗 네트워크 연결
- **Cloud Router / VPN Gateway**: 클라우드 간 동기화 및 DB 통신 지원

### 🧩 백엔드 & 앱
- **Python (Flask)**: `user-registration-service`, `user-login-service` 구현
- **정적 웹 (HTML/CSS)**: S3 + CloudFront로 배포되는 프론트엔드

---

## 🙋 작업 요약

- 전체 멀티클라우드 인프라 설계 및 구축 (Terraform 기반)
- CI/CD 자동화 파이프라인 구축 (GitHub Actions + Docker + EKS/GKE)
- VPN 기반 실시간 DB 동기화 및 보조 백업 경로 구성
- 백엔드 마이크로서비스 컨테이너화 및 클라우드 배포
- 보안, 인증, 시크릿 관리 최적화
