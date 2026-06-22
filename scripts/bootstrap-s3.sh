#!/bin/bash
set -euo pipefail

BUCKET="radinlab-terraform-state"
REGION="${AWS_REGION:-sa-east-1}"

# Verifica se o bucket já existe
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket $BUCKET já existe, seguindo..."
else
  echo "Criando bucket $BUCKET na região $REGION..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi

  # Habilitar versionamento (para recuperar states anteriores)
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled

  # Habilitar criptografia server-side
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'

  echo "Bucket $BUCKET criado com versionamento e criptografia."
fi
