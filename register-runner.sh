#!/bin/bash

if [ -z "$1" ]; then
    echo "Uso: ./register-runner.sh <RUNNER_TOKEN>"
    exit 1
fi

RUNNER_TOKEN=$1

echo "[3/4] Registrando runner con token..."
export RUNNER_TOKEN
docker compose up -d gitea-runner

echo "[4/4] Verificando runner..."
sleep 5
docker logs gitea-runner 2>&1 | tail -5

echo ""
echo "Runner registrado. Verifica en Gitea > Site Administration > Actions > Runners"
