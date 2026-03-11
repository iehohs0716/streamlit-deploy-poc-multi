# Terraform Backend設定
# bootstrap/で作成したS3バケットとDynamoDBテーブルを使用

terraform {
  backend "s3" {
    # bucket / key は backend.tfbackend で管理（git管理外）
    # terraform init -backend-config=backend.tfbackend
    region         = "ap-northeast-1"
    use_lockfile   = true
    encrypt        = true
  }

  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

provider "snowflake" {
  role                       = "ACCOUNTADMIN"
  private_key                = file(var.snowflake_private_key_path)
  preview_features_enabled   = ["snowflake_stage_resource"]
}

provider "aws" {
  region = var.aws_region
  # profile指定はaws-vault使用時には不要
  # aws-vaultが環境変数経由で認証情報を提供します
  # profile = var.aws_profile

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Owner     = var.owner
      CreatedBy = var.owner
    }
  }
}
