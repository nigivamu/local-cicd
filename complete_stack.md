# Stack Completo de CI/CD Local con Gitea, LocalStack y PostgreSQL

## Tabla de Contenidos

1. [Introducción](#introducción)
2. [Arquitectura](#arquitectura)
3. [Prerrequisitos](#prerrequisitos)
4. [Estructura del Proyecto](#estructura-del-proyecto)
5. [Configuración del Stack](#configuración-del-stack)
   - [Docker Compose](#docker-compose)
   - [Configuración del Runner](#configuración-del-runner)
6. [Workflow de Despliegue](#workflow-de-despliegue)
7. [Scripts de Automatización](#scripts-de-automatización)
8. [Puesta en Marcha](#puesta-en-marcha)
9. [Pruebas del Pipeline](#pruebas-del-pipeline)
10. [Verificación de Recursos](#verificación-de-recursos)
11. [Tips y Mejores Prácticas](#tips-y-mejores-prácticas)
12. [Troubleshooting](#troubleshooting)

---

## Introducción

Este tutorial describe cómo construir un stack completo de CI/CD local que emula un entorno cloud-native sin depender de servicios externos. El stack permite:

- **Control de versiones**: Gitea como servidor Git self-hosted
- **CI/CD**: Gitea Actions (compatible con sintaxis GitHub Actions)
- **Servicios AWS emulados**: LocalStack para DynamoDB, EC2, S3, SQS, etc.
- **Base de datos relacional**: PostgreSQL para datos transaccionales

### Casos de Uso

- Desarrollo local sin costos de cloud
- Testing de infraestructura como código
- Prototipado rápido de arquitecturas AWS
- Entornos de CI/CD air-gapped
- Capacitación en tecnologías cloud

> **Importante**: LocalStack está diseñado para desarrollo y testing, no para producción. Los servicios emulan las APIs de AWS pero no replican su arquitectura distribuida ni garantías de disponibilidad.

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DEVELOPER WORKSTATION                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────┐     git push [deploy]     ┌─────────────────────────┐    │
│   │   Git CLI   │ ─────────────────────────►│        Gitea            │    │
│   │             │                           │      :3000              │    │
│   └─────────────┘                           └───────────┬─────────────┘    │
│                                                         │                   │
│                                                         │ trigger           │
│                                                         ▼                   │
│                                             ┌─────────────────────────┐    │
│                                             │     Gitea Runner        │    │
│                                             │    (act_runner)         │    │
│                                             └───────────┬─────────────┘    │
│                                                         │                   │
│                        ┌────────────────────────────────┼──────────────┐   │
│                        │                                │              │   │
│                        ▼                                ▼              ▼   │
│            ┌───────────────────┐          ┌─────────────────┐  ┌──────────┐│
│            │    LocalStack     │          │   PostgreSQL    │  │  Otros   ││
│            │      :4566        │          │     :5432       │  │ Services ││
│            │                   │          │                 │  │          ││
│            │  ┌─────────────┐  │          │  ┌───────────┐  │  │          ││
│            │  │  DynamoDB   │  │          │  │  users    │  │  │          ││
│            │  │  EC2        │  │          │  │app_config │  │  │          ││
│            │  │  S3, SQS... │  │          │  └───────────┘  │  │          ││
│            │  └─────────────┘  │          │                 │  │          ││
│            └───────────────────┘          └─────────────────┘  └──────────┘│
│                                                                             │
│                         Docker Network: cicd-network                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Flujo de Despliegue

1. El desarrollador hace `git push` con `[deploy]` en el mensaje del commit
2. Gitea recibe el push y dispara el workflow de Actions
3. El Runner ejecuta los jobs en contenedores conectados a `cicd-network`
4. Los jobs pueden acceder a LocalStack y PostgreSQL por nombre de servicio
5. Se crean/actualizan los recursos de infraestructura

---

## Prerrequisitos

### Software Requerido

| Herramienta | Versión Mínima | Verificación |
|-------------|----------------|--------------|
| Docker | 24.0+ | `docker --version` |
| Docker Compose | 2.20+ | `docker compose version` |
| Git | 2.30+ | `git --version` |
| AWS CLI (opcional) | 2.0+ | `aws --version` |
| LocalStack CLI (opcional) | 3.0+ | `localstack --version` |

### Recursos del Sistema

- **CPU**: 4 cores recomendados
- **RAM**: 8 GB mínimo (LocalStack consume ~2GB)
- **Disco**: 10 GB libres para imágenes y volúmenes

### Verificación del Entorno

```bash
# Verificar Docker
docker info | grep -E "Server Version|Operating System"

# Verificar que Docker Compose V2 esté disponible
docker compose version

# Verificar conectividad de red de Docker
docker network ls
```

---

## Estructura del Proyecto

```
local-cicd/
├── docker-compose.yml          # Definición de todos los servicios
├── runner-config.yaml          # Configuración del Gitea Runner
├── setup.sh                    # Script de inicialización del stack
├── register-runner.sh          # Script para registrar el runner
├── complete_stack.md           # Este documento
└── example-repo/
    └── .gitea/
        └── workflows/
            └── deploy.yml      # Workflow de despliegue
```

---

## Configuración del Stack

### Docker Compose

Crear el archivo `docker-compose.yml`:

```yaml
services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=sqlite3
      - GITEA__server__ROOT_URL=http://localhost:3000
      - GITEA__server__HTTP_PORT=3000
      - GITEA__actions__ENABLED=true
    volumes:
      - gitea-data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
      - "2222:22"
    restart: unless-stopped
    networks:
      - cicd-network

  gitea-runner:
    image: gitea/act_runner:latest
    container_name: gitea-runner
    depends_on:
      - gitea
      - localstack
      - postgres
    environment:
      - GITEA_INSTANCE_URL=http://gitea:3000
      - GITEA_RUNNER_REGISTRATION_TOKEN=${RUNNER_TOKEN}
      - GITEA_RUNNER_NAME=local-runner
      - CONFIG_FILE=/config.yaml
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - runner-data:/data
      - ./runner-config.yaml:/config.yaml:ro
    restart: unless-stopped
    networks:
      - cicd-network

  postgres:
    image: postgres:16-alpine
    container_name: postgres-dev
    environment:
      - POSTGRES_USER=admin
      - POSTGRES_PASSWORD=secretpass123
      - POSTGRES_DB=myapp
    volumes:
      - postgres-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: unless-stopped
    networks:
      - cicd-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin -d myapp"]
      interval: 10s
      timeout: 5s
      retries: 5

  localstack:
    image: localstack/localstack:latest
    container_name: localstack
    environment:
      - SERVICES=dynamodb,ec2,s3,sqs,sns,lambda,secretsmanager,iam,sts,cloudwatch,logs
      - DEBUG=0
      - DOCKER_HOST=unix:///var/run/docker.sock
      - LOCALSTACK_HOST=localstack
    volumes:
      - localstack-data:/var/lib/localstack
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "4566:4566"
      - "4510-4560:4510-4560"
    restart: unless-stopped
    networks:
      - cicd-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4566/_localstack/health"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  gitea-data:
  runner-data:
  postgres-data:
  localstack-data:

networks:
  cicd-network:
    driver: bridge
```

> **Tip**: La variable `SERVICES` en LocalStack define qué servicios AWS estarán disponibles. Agrega solo los que necesites para reducir el consumo de memoria.

### Configuración del Runner

Crear el archivo `runner-config.yaml`:

```yaml
log:
  level: info

runner:
  file: .runner
  capacity: 1
  timeout: 3h
  insecure: false
  fetch_timeout: 5s
  fetch_interval: 2s

cache:
  enabled: true
  dir: ""

container:
  network: local-cicd_cicd-network
  privileged: false
  options: ""
  workdir_parent: ""
  valid_volumes: []
  docker_host: ""
  force_pull: false
```

> **Importante**: El valor de `container.network` debe coincidir con el nombre real de la red Docker, que sigue el patrón `{directorio}_{nombre_red}`. Docker Compose antepone el nombre del directorio al nombre de la red definida en el archivo.

---

## Workflow de Despliegue

Crear el archivo `.gitea/workflows/deploy.yml` en tu repositorio:

```yaml
name: Deploy to LocalStack + PostgreSQL

on:
  push:
    branches:
      - main

jobs:
  check-deploy:
    runs-on: ubuntu-latest
    outputs:
      should_deploy: ${{ steps.check.outputs.deploy }}
    steps:
      - name: Check commit message for [deploy]
        id: check
        run: |
          if echo "${{ github.event.head_commit.message }}" | grep -q "\[deploy\]"; then
            echo "deploy=true" >> $GITHUB_OUTPUT
            echo "Detectado [deploy] en el mensaje de commit"
          else
            echo "deploy=false" >> $GITHUB_OUTPUT
            echo "No se detectó [deploy], saltando despliegue"
          fi

  deploy:
    needs: check-deploy
    if: needs.check-deploy.outputs.should_deploy == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup tools
        run: |
          apt-get update && apt-get install -y postgresql-client curl unzip
          curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          unzip -q awscliv2.zip
          ./aws/install
          aws --version

      - name: Setup PostgreSQL Schema
        run: |
          echo "=== Configurando PostgreSQL ==="

          # Esperar a que PostgreSQL esté listo
          until PGPASSWORD=secretpass123 psql -h postgres -U admin -d myapp -c '\q' 2>/dev/null; do
            echo "Esperando PostgreSQL..."
            sleep 2
          done

          # Crear schema de la aplicación
          PGPASSWORD=secretpass123 psql -h postgres -U admin -d myapp << 'EOF'
          -- Tabla de usuarios
          CREATE TABLE IF NOT EXISTS users (
              id SERIAL PRIMARY KEY,
              email VARCHAR(255) UNIQUE NOT NULL,
              name VARCHAR(255),
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          );

          -- Tabla de configuración
          CREATE TABLE IF NOT EXISTS app_config (
              key VARCHAR(255) PRIMARY KEY,
              value TEXT,
              updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          );

          -- Insertar configuración inicial
          INSERT INTO app_config (key, value) VALUES ('version', '1.0.0')
          ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP;

          SELECT 'Schema PostgreSQL configurado correctamente' as status;
          EOF

          echo "=== Verificando tablas PostgreSQL ==="
          PGPASSWORD=secretpass123 psql -h postgres -U admin -d myapp -c '\dt'

      - name: Deploy DynamoDB Tables to LocalStack
        env:
          AWS_ACCESS_KEY_ID: test
          AWS_SECRET_ACCESS_KEY: test
          AWS_DEFAULT_REGION: us-east-1
        run: |
          echo "=== Creando tabla DynamoDB para sesiones ==="
          aws --endpoint-url=http://localstack:4566 dynamodb create-table \
            --table-name sessions \
            --attribute-definitions \
              AttributeName=sessionId,AttributeType=S \
            --key-schema \
              AttributeName=sessionId,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            2>/dev/null || echo "Tabla sessions ya existe"

          echo "=== Creando tabla DynamoDB para cache ==="
          aws --endpoint-url=http://localstack:4566 dynamodb create-table \
            --table-name cache \
            --attribute-definitions \
              AttributeName=cacheKey,AttributeType=S \
            --key-schema \
              AttributeName=cacheKey,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            2>/dev/null || echo "Tabla cache ya existe"

          echo "=== Verificando tablas DynamoDB ==="
          aws --endpoint-url=http://localstack:4566 dynamodb list-tables

      - name: Deploy EC2 Instance to LocalStack
        env:
          AWS_ACCESS_KEY_ID: test
          AWS_SECRET_ACCESS_KEY: test
          AWS_DEFAULT_REGION: us-east-1
        run: |
          echo "=== Creando instancia EC2 ==="
          INSTANCE_ID=$(aws --endpoint-url=http://localstack:4566 ec2 run-instances \
            --image-id ami-0123456789abcdef0 \
            --instance-type t2.micro \
            --count 1 \
            --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=myapp-server},{Key=Environment,Value=dev}]' \
            --query 'Instances[0].InstanceId' \
            --output text)

          echo "Instancia creada: $INSTANCE_ID"

          echo "=== Verificando EC2 ==="
          aws --endpoint-url=http://localstack:4566 ec2 describe-instances \
            --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
            --output table

      - name: Deployment Summary
        run: |
          echo ""
          echo "=========================================="
          echo "        DESPLIEGUE COMPLETADO"
          echo "=========================================="
          echo ""
          echo "PostgreSQL (datos relacionales):"
          echo "  Host: postgres:5432"
          echo "  DB:   myapp"
          echo "  User: admin"
          echo "  Tablas: users, app_config"
          echo ""
          echo "DynamoDB en LocalStack (cache/sesiones):"
          echo "  Endpoint: localstack:4566"
          echo "  Tablas: sessions, cache"
          echo ""
          echo "EC2 en LocalStack:"
          echo "  Instance: myapp-server"
          echo "=========================================="
```

> **Tip**: El workflow usa `CREATE TABLE IF NOT EXISTS` y manejo de errores con `|| echo` para ser idempotente. Puedes ejecutar el pipeline múltiples veces sin errores.

---

## Scripts de Automatización

### setup.sh

```bash
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
```

### register-runner.sh

```bash
#!/bin/bash

if [ -z "$1" ]; then
    echo "Uso: ./register-runner.sh <RUNNER_TOKEN>"
    exit 1
fi

RUNNER_TOKEN=$1

echo "[1/2] Registrando runner con token..."
export RUNNER_TOKEN
docker compose up -d gitea-runner

echo "[2/2] Verificando runner..."
sleep 5
docker logs gitea-runner 2>&1 | tail -5

echo ""
echo "Runner registrado. Verifica en Gitea > Site Administration > Actions > Runners"
```

Hacer los scripts ejecutables:

```bash
chmod +x setup.sh register-runner.sh
```

---

## Puesta en Marcha

### Paso 1: Iniciar el Stack

```bash
cd local-cicd
./setup.sh
```

### Paso 2: Configurar Gitea

1. Abrir http://localhost:3000
2. En la página de instalación inicial:
   - **Database Type**: SQLite3 (ya configurado)
   - **Site Title**: Tu preferencia
   - **Repository Root Path**: Dejar por defecto
   - Crear cuenta de administrador
3. Hacer clic en "Install Gitea"

### Paso 3: Habilitar Actions y Registrar Runner

1. Ir a **Site Administration** (icono de llave inglesa)
2. Navegar a **Actions > Runners**
3. Clic en **"Create new Runner"**
4. Copiar el token de registro
5. Ejecutar:

```bash
./register-runner.sh <TOKEN_COPIADO>
```

### Paso 4: Verificar el Runner

En Gitea, el runner debe aparecer como "Online" con labels:
- `ubuntu-latest`
- `ubuntu-24.04`
- `ubuntu-22.04`

---

## Pruebas del Pipeline

### Crear Repositorio de Prueba

1. En Gitea, crear nuevo repositorio (ej: `myapp`)
2. Clonar localmente:

```bash
git clone http://localhost:3000/<usuario>/myapp.git
cd myapp
```

3. Agregar el workflow:

```bash
mkdir -p .gitea/workflows
cp /path/to/local-cicd/example-repo/.gitea/workflows/deploy.yml .gitea/workflows/
```

4. Commit inicial:

```bash
git add .
git commit -m "Add deploy workflow"
git push origin main
```

### Disparar el Despliegue

```bash
echo "# MyApp" >> README.md
git add .
git commit -m "[deploy] Despliegue inicial de infraestructura"
git push origin main
```

### Monitorear Ejecución

- **Gitea UI**: http://localhost:3000/<usuario>/myapp/actions
- **Logs del Runner**: `docker logs gitea-runner -f`

---

## Verificación de Recursos

### LocalStack - DynamoDB

```bash
# Usando awslocal (si está instalado)
awslocal dynamodb list-tables

# O usando AWS CLI con endpoint
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
```

Resultado esperado:
```json
{
    "TableNames": [
        "cache",
        "sessions"
    ]
}
```

### LocalStack - EC2

```bash
awslocal ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

Resultado esperado:
```
----------------------------------------------------
|                 DescribeInstances                |
+----------------------+----------+----------------+
|  i-xxxxxxxxxxxx      |  running |  myapp-server  |
+----------------------+----------+----------------+
```

### PostgreSQL

```bash
docker exec postgres-dev psql -U admin -d myapp -c '\dt'
```

Resultado esperado:
```
          List of relations
 Schema |    Name    | Type  | Owner
--------+------------+-------+-------
 public | app_config | table | admin
 public | users      | table | admin
(2 rows)
```

---

## Tips y Mejores Prácticas

### Gestión de Secretos

- **Nunca** commitear credenciales reales en el workflow
- Para desarrollo local, las credenciales dummy (`test/test`) son suficientes
- En producción, usar Gitea Secrets o integración con vault

### Optimización del Pipeline

```yaml
# Cachear instalación de herramientas
- name: Cache AWS CLI
  uses: actions/cache@v3
  with:
    path: ~/aws-cli
    key: aws-cli-v2
```

### Networking

- Los servicios se comunican por nombre dentro de `cicd-network`
- Desde el host, usar `localhost` con el puerto mapeado
- Desde los jobs del runner, usar el nombre del servicio (ej: `localstack`, `postgres`)

### Persistencia de Datos

Los datos persisten en volúmenes Docker:

```bash
# Ver volúmenes
docker volume ls | grep local-cicd

# Backup de PostgreSQL
docker exec postgres-dev pg_dump -U admin myapp > backup.sql

# Limpiar todo (incluye datos)
docker compose down -v
```

### Múltiples Entornos

Puedes crear variantes del workflow para diferentes entornos:

```yaml
# .gitea/workflows/deploy-staging.yml
on:
  push:
    branches:
      - staging

# Usar diferentes tablas/recursos con prefijos
--table-name staging-sessions
```

---

## Troubleshooting

### El Runner no se registra

**Síntoma**: Error "unregistered runner" en logs

**Solución**:
```bash
# Limpiar y re-registrar
docker compose stop gitea-runner
docker compose rm -f gitea-runner
docker volume rm local-cicd_runner-data

# Obtener nuevo token en Gitea y re-registrar
./register-runner.sh <NUEVO_TOKEN>
```

### Jobs no pueden conectar a LocalStack/PostgreSQL

**Síntoma**: "Connection refused" o "Could not resolve host"

**Verificar**:
1. Que `runner-config.yaml` tenga la red correcta:
   ```yaml
   container:
     network: local-cicd_cicd-network
   ```

2. Que la red existe:
   ```bash
   docker network ls | grep cicd
   ```

3. Que los servicios estén en la misma red:
   ```bash
   docker network inspect local-cicd_cicd-network
   ```

### Error "externally-managed-environment" al instalar pip packages

**Síntoma**: pip falla con PEP 668 error

**Solución**: Usar el instalador oficial de AWS CLI v2 en lugar de pip:
```yaml
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
```

### LocalStack no inicia correctamente

**Síntoma**: Health check falla o servicios no disponibles

**Verificar**:
```bash
# Ver logs
docker logs localstack

# Verificar salud
curl http://localhost:4566/_localstack/health | jq .

# Reiniciar con logs
docker compose restart localstack && docker logs -f localstack
```

### Puerto 3000/4566/5432 ya en uso

**Síntoma**: "Bind: address already in use"

**Solución**:
```bash
# Identificar proceso
lsof -i :3000

# O cambiar puerto en docker-compose.yml
ports:
  - "3001:3000"  # Gitea en puerto 3001
```

### Workflow no se dispara

**Verificar**:
1. Que Actions esté habilitado en Gitea (Site Administration > Actions)
2. Que el archivo esté en `.gitea/workflows/` (no `.github/workflows/`)
3. Que el runner esté online y tenga el label correcto (`ubuntu-latest`)

### Limpiar y empezar de nuevo

```bash
# Detener todo
docker compose down

# Eliminar volúmenes (borra datos)
docker compose down -v

# Eliminar imágenes descargadas
docker compose down --rmi all

# Iniciar limpio
./setup.sh
```

---

## Referencias

- [Gitea Documentation](https://docs.gitea.io/)
- [Gitea Actions](https://docs.gitea.io/en-us/actions/)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [LocalStack AWS Service Coverage](https://docs.localstack.cloud/references/coverage/)
- [Docker Compose Specification](https://docs.docker.com/compose/compose-file/)
- [GitHub Actions Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)

---

## Conclusión

Este stack proporciona un entorno completo de CI/CD local que permite:

- Desarrollar y probar pipelines sin conexión a internet
- Emular servicios AWS para testing de infraestructura
- Mantener un flujo de trabajo similar al de producción
- Reducir costos de desarrollo y experimentación

El patrón `[deploy]` en los mensajes de commit permite control granular sobre cuándo ejecutar despliegues, evitando ejecuciones innecesarias en commits de desarrollo regular.

Para extender este stack, considera agregar:

- **SonarQube**: Análisis de calidad de código
- **Vault**: Gestión de secretos
- **MinIO**: S3-compatible para producción local
- **Prometheus/Grafana**: Monitoreo del stack
