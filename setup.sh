#!/bin/bash

echo "=== Setup Completo: Gitea + LocalStack + PostgreSQL ==="

# 1. Iniciar infraestructura (sin runner)
echo "[1/5] Iniciando LocalStack, PostgreSQL y Gitea..."
docker compose up -d localstack postgres gitea

# 2. Esperar a que LocalStack esté listo
echo "[2/5] Esperando que LocalStack inicie..."
until curl -s http://localhost:4566/_localstack/health | grep -q '"dynamodb": "available"' 2>/dev/null; do
    sleep 2
    echo "  Esperando LocalStack..."
done
echo "  LocalStack está listo!"

# 3. Esperar a que PostgreSQL esté listo
echo "[3/5] Esperando que PostgreSQL inicie..."
until docker exec postgres-dev pg_isready -U admin -d myapp > /dev/null 2>&1; do
    sleep 2
    echo "  Esperando PostgreSQL..."
done
echo "  PostgreSQL está listo!"

# 4. Esperar a que Gitea esté listo
echo "[4/5] Esperando que Gitea inicie..."
until curl -s http://localhost:3000/api/v1/version > /dev/null 2>&1; do
    sleep 2
    echo "  Esperando Gitea..."
done
echo "  Gitea está listo!"

# 5. Mostrar estado
echo "[5/5] Verificando servicios..."
echo ""
docker compose ps
echo ""

echo "=============================================="
echo "         SERVICIOS INICIADOS"
echo "=============================================="
echo ""
echo "LocalStack:  http://localhost:4566"
echo "PostgreSQL:  localhost:5432 (admin/secretpass123/myapp)"
echo "Gitea:       http://localhost:3000"
echo ""
echo "=============================================="
echo "         PASOS MANUALES REQUERIDOS"
echo "=============================================="
echo ""
echo "1. Abre http://localhost:3000 en tu navegador"
echo "2. Completa la instalación inicial (usa valores por defecto)"
echo "3. Crea una cuenta de administrador"
echo "4. Ve a: Site Administration > Actions > Runners"
echo "5. Clic en 'Create new Runner' y copia el token"
echo "6. Ejecuta: ./register-runner.sh <TOKEN>"
echo ""
