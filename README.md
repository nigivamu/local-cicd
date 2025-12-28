# CI/CD Local con Gitea + LocalStack

Pipeline local que despliega RDS PostgreSQL y EC2 en LocalStack cuando detecta `[deploy]` en el mensaje de commit.

## Arquitectura

```
┌─────────────────┐     push [deploy]     ┌─────────────────┐
│   Git Local     │ ──────────────────►   │     Gitea       │
│   (tu código)   │                       │   :3000         │
└─────────────────┘                       └────────┬────────┘
                                                   │
                                                   ▼
                                          ┌─────────────────┐
                                          │  Gitea Runner   │
                                          │  (Actions)      │
                                          └────────┬────────┘
                                                   │
                                                   ▼
                                          ┌─────────────────┐
                                          │   LocalStack    │
                                          │   :4566         │
                                          │  ┌───────────┐  │
                                          │  │ RDS (PG)  │  │
                                          │  │ EC2       │  │
                                          │  └───────────┘  │
                                          └─────────────────┘
```

## Requisitos

- Docker y Docker Compose
- LocalStack corriendo en `localhost:4566`

## Instalación

### 1. Iniciar Gitea

```bash
cd local-cicd
./setup.sh
```

### 2. Configurar Gitea (manual en navegador)

1. Abre http://localhost:3000
2. Completa la instalación inicial (valores por defecto)
3. Crea una cuenta de administrador
4. Ve a: **Site Administration > Actions > Runners**
5. Clic en **"Create new Runner"**
6. Copia el token de registro

### 3. Registrar el Runner

```bash
./register-runner.sh <TOKEN_COPIADO>
```

### 4. Crear repositorio de prueba

```bash
# En Gitea web: crea un repositorio "myapp"

# Clona e inicializa
git clone http://localhost:3000/<tu-usuario>/myapp.git
cd myapp

# Copia el workflow
mkdir -p .gitea/workflows
cp ../example-repo/.gitea/workflows/deploy.yml .gitea/workflows/

# Commit inicial
git add .
git commit -m "Setup inicial"
git push origin main
```

### 5. Probar el despliegue

```bash
# Este commit NO desplegará (sin [deploy])
echo "cambio normal" >> README.md
git add . && git commit -m "Cambio sin deploy" && git push

# Este commit SÍ desplegará (con [deploy])
echo "feature lista" >> README.md
git add . && git commit -m "[deploy] Nueva feature lista para producción" && git push
```

## Verificar recursos en LocalStack

```bash
# Ver instancias RDS
aws --endpoint-url=http://localhost:4566 rds describe-db-instances

# Ver instancias EC2
aws --endpoint-url=http://localhost:4566 ec2 describe-instances

# Ver logs del runner
docker logs gitea-runner -f
```

## Estructura de archivos

```
local-cicd/
├── docker-compose.yml      # Gitea + Runner
├── setup.sh                # Script de instalación
├── register-runner.sh      # Registrar runner
├── README.md               # Este archivo
└── example-repo/
    └── .gitea/
        └── workflows/
            └── deploy.yml  # Workflow de despliegue
```

## Personalización

Edita `example-repo/.gitea/workflows/deploy.yml` para:

- Cambiar el trigger (rama, tag, mensaje)
- Agregar más recursos AWS
- Cambiar configuración de RDS/EC2
- Agregar pasos de build/test antes del deploy

## Instalación de awslocal en ubuntu moderno

Para instalar aws local ejecutar los comandos.
Localstack ya debe estar en ejecución.
Por defecto se crea un s3 para hacer la validación de la correcta instlación de awslocal

```bash
chmod +x install_awslocal.sh
./install_awslocal.sh

```
