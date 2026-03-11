#!/bin/bash

# 文字コード設定
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .envファイルから環境変数を読み込む
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env"
  set +a
else
  echo "Error: .envファイルが見つかりません。.env.sampleを参考に.envファイルを作成してください。"
  exit 1
fi

cd $SCRIPT_DIR/../infra/env/dev

# aws-vaultの使用を確認
USE_AWS_VAULT=false
if command -v aws-vault &> /dev/null; then
    echo "🔐 aws-vaultが検出されました"
    read -p "aws-vault (MFA認証) を使用しますか？ (yes/no): " use_vault
    if [ "$use_vault" = "yes" ]; then
        USE_AWS_VAULT=true
        : "${AWS_VAULT_PROFILE:?aws-vault使用時はAWS_VAULT_PROFILEを.envに設定してください}"
        echo "✅ aws-vaultを使用します (プロファイル: $AWS_VAULT_PROFILE)"
        echo "📱 Google Authenticatorの6桁コードが必要になります"
    fi
else
    echo "ℹ️  aws-vaultが見つかりません。通常のAWSプロファイルを使用します"
fi

if [ "$USE_AWS_VAULT" = false ]; then
    export AWS_PROFILE="${AWS_PROFILE:?AWS_PROFILEを.envに設定してください}"
    echo "🔑 使用するAWSプロファイル: $AWS_PROFILE"
fi

echo ""

# AWS認証情報を確認
echo "📋 AWS認証情報を確認中..."
if [ "$USE_AWS_VAULT" = true ]; then
    aws-vault exec "$AWS_VAULT_PROFILE" -- aws sts get-caller-identity || {
        echo "❌ aws-vault認証に失敗しました"
        exit 1
    }
else
    aws sts get-caller-identity --profile "$AWS_PROFILE" || {
        echo "❌ AWS認証に失敗しました"
        exit 1
    }
fi
echo ""

# Terraform初期化
BACKEND_CONFIG="-backend-config=backend.tfbackend"

echo "🔧 Terraform初期化中..."
if [ "$USE_AWS_VAULT" = true ]; then
    aws-vault exec "$AWS_VAULT_PROFILE" -- terraform init $BACKEND_CONFIG
else
    terraform init $BACKEND_CONFIG
fi
echo ""

# Terraformプランの表示
echo "📝 Terraformプランを確認中..."
if [ "$USE_AWS_VAULT" = true ]; then
    aws-vault exec "$AWS_VAULT_PROFILE" -- terraform plan -out=tfplan
else
    terraform plan -out=tfplan
fi
echo ""

# 確認プロンプト
read -p "上記の内容でリソースを作成しますか？ (yes/no): " response
if [ "$response" != "yes" ]; then
    echo "❌ デプロイをキャンセルしました"
    rm -f tfplan
    exit 0
fi

# Terraform適用
echo ""
echo "🚀 リソースを作成中..."
if [ "$USE_AWS_VAULT" = true ]; then
    aws-vault exec "$AWS_VAULT_PROFILE" -- terraform apply tfplan
else
    terraform apply tfplan
fi
rm -f tfplan
echo ""

# 出力値の表示
echo "========================================="
echo "✅ デプロイ完了"
echo "========================================="
echo ""
if [ "$USE_AWS_VAULT" = true ]; then
    aws-vault exec "$AWS_VAULT_PROFILE" -- terraform output
else
    terraform output
fi
echo ""
