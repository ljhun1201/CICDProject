terraform { #테라폼의 전역적 구성을 정의하는 블록
  backend "s3" {
    bucket = "terraformstorage3"  # S3 버킷 이름
    key    = "terraform/terraform.tfstate"  # S3 버킷 내에 저장될 경로
    region = "ap-northeast-2"              # S3 버킷이 있는 리전
    dynamodb_table = "terraform-lock"      # 이건 dynamodb 생성이 이미 되어있어야됨. 그래서 테라폼 resource 블록을 써서 dynamodb를 이거를 실행함과 동시에 실행하면 에러떠서 그냥 dynamodb는 aws cloudshell 명령어로 미리 생성해둠
  }
}

/*
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-lock-table"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
*/