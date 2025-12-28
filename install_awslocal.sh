#!/usr/bin/env bash
set -e

echo "🚀 Instalando dependencias base..."
sudo apt update
sudo apt install -y \
  python3 \
  python3-full \
  python3-venv \
  curl \
  ca-certificates \
  gnupg \
  lsb-release

echo "📦 Instalando pipx..."
sudo apt install -y pipx
pipx ensurepath

# Recargar PATH
export PATH="$PATH:$HOME/.local/bin"

echo "📦 Instalando awslocal con pipx..."
pipx install awscli-local || echo "awslocal ya instalado"


BUCKET_NAME="test-bucket-awslocal-$(date +%s)"

awslocal s3 mb "s3://$BUCKET_NAME"

echo "📂 Listando buckets S3:"
awslocal s3 ls

if awslocal s3 ls | grep -q "$BUCKET_NAME"; then
  echo "✅ VALIDACIÓN EXITOSA"
  echo "awslocal funciona correctamente"
else
  echo "❌ ERROR: No se pudo validar awslocal"
  exit 1
fi

echo "🎉 Instalación completa"
