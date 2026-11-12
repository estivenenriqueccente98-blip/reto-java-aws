# Reto tecnico: Java + Maven + Docker + AWS ECR + ECS + Terraform + GitHub Actions

Este repositorio es una solucion inicial completa para el reto de la imagen. Contiene una API REST Java, pruebas, Dockerfile multietapa, infraestructura con Terraform, CI/CD en GitHub Actions y una limpieza manual de los recursos de AWS.

## Arquitectura

```text
GitHub (push a main)
    |
    v
GitHub Actions -> mvn clean verify -> docker build (Maven dentro de Docker)
    |                                  |
    |                             imagen Docker
    v                                  |
AWS OIDC (credenciales temporales)     v
    |                                AWS ECR
    v                                  |
Terraform -> VPC + 2 subredes + ALB -> ECS Fargate (1 tarea Java:8080)
                                        |
Internet ---> http://DNS_PUBLICO_DEL_ALB/ -> GET / y GET /health
```

**Eleccion:** ECS Fargate en lugar de EKS, porque ambos satisfacen el enunciado y ECS exige menos configuracion. Se crea un **Application Load Balancer** para disponer de un nombre DNS publico estable. Para el laboratorio, la tarea se ejecuta en subred publica con IP publica y un security group que solo permite trafico entrante desde el ALB: se evita el costo de un NAT Gateway.

**Atencion a costos y seguridad:** ECS Fargate, Application Load Balancer, IPv4 publica, CloudWatch y ECR pueden generar cargos, aunque tu cuenta sea gratuita o sandbox. Verifica los permisos y los limites de tu sandbox. Este ejemplo usa HTTP sin TLS solo para el reto; para produccion, usa HTTPS, subredes privadas, menor privilegio, monitoreo y controles adicionales. El script de arranque crea un rol con **AdministratorAccess**, restringido por OIDC al repositorio y a la rama `main`, exclusivamente para un laboratorio aislado. **No utilizar esa politica en produccion.** Elimina el rol al terminar.

## Estructura

```text
reto-java-aws/
  pom.xml
  Dockerfile
  src/main/java/com/reto/demo/Application.java
  src/main/java/com/reto/demo/HolaController.java
  src/main/resources/application.properties
  src/test/java/com/reto/demo/HolaControllerTest.java
  infra/{versions,variables,main,outputs}.tf
  .github/workflows/deploy.yml
  .github/workflows/destroy.yml
  scripts/bootstrap.sh
  scripts/remove-access.sh
  README.md
```

## Paso 1. Preparar cuentas y herramientas

1. Crea una cuenta en https://github.com/ (plan gratis) y una cuenta de AWS sandbox con permisos IAM, EC2/VPC, ECS, ECR, Elastic Load Balancing, CloudWatch y S3. Si la sandbox restringe alguno, habla con el administrador.
2. En tu computadora instala **Git**, **Docker Desktop** (o Docker Engine), **AWS CLI v2** y **GitHub CLI (`gh`)**. Java 21 y Maven son opcionales para pruebas locales si usas Docker; GitHub Actions los instala para CI.
3. Configura acceso a AWS mediante `aws configure` (credenciales de laboratorio) o el metodo SSO de tu organizacion. Comprueba `aws sts get-caller-identity` y **nunca** subas claves de AWS al repositorio.
4. Autentica GitHub CLI con `gh auth login`. En Windows, usa Git Bash o WSL para ejecutar los scripts Bash.

## Paso 2. Probar Java y Docker localmente

Descomprime el proyecto, abre una terminal en `reto-java-aws` y ejecuta:

```bash
docker build -t reto-java-local .
docker run --rm -p 8080:8080 reto-java-local
```

En **otra terminal**:

```bash
curl http://localhost:8080/
# {"mensaje":"Hola, mundo desde AWS ECS"}
curl http://localhost:8080/health
# {"status":"ok"}
```

El `Dockerfile` tiene dos etapas: la primera compila y prueba con Maven dentro de un contenedor; la segunda contiene solamente Java Runtime y la aplicacion. Para correr Maven fuera de Docker, si ya lo tienes instalado: `mvn clean verify`.

## Paso 3. Crear el repositorio GitHub **vacio** (sin hacer push todavia)

En la web de GitHub, pulsa **New repository**, pon por ejemplo `reto-java-aws`, elige Public o Private y **NO** selecciones README, `.gitignore` ni licencia inicial. Copia tu nombre de usuario. El repositorio debe existir para que `bootstrap.sh` consulte sus identificadores inmutables.

Si necesitas compartir el proyecto para evaluacion, cambia la visibilidad a Public al finalizar o comparte acceso con el evaluador. Nunca incluyas credenciales.

## Paso 4. Preparar AWS S3 + IAM OIDC y variables GitHub

En la raiz del proyecto:

```bash
aws sts get-caller-identity
gh auth status
AWS_REGION=us-east-1 ./scripts/bootstrap.sh TU_USUARIO/reto-java-aws
```

Sustituye `TU_USUARIO` por tu cuenta real y adapta el nombre si cambiaste el repositorio. El script:

- Crea o reutiliza un **bucket S3** privado con versionado para el estado Terraform.
- Crea o reutiliza el proveedor OIDC de GitHub y un rol IAM confiando **solo en tu repositorio y rama `main`**.
- Obtiene el `OWNER_ID` y `REPO_ID` de GitHub. Desde el **15 de julio de 2026**, los repos nuevos usan esos IDs en el `sub` de OIDC.
- Concede permisos de laboratorio al rol y registra estas **GitHub Actions Variables**: `AWS_REGION`, `AWS_ROLE_ARN`, `TF_STATE_BUCKET`, `TF_STATE_KEY`.

**Importante:** si no tienes permisos para `iam:CreateRole`, `iam:CreateOpenIDConnectProvider`, `s3:CreateBucket` o adjuntar politicas IAM, la sandbox podria impedirlo. Necesitaras una sandbox con esos permisos o que el administrador prepare los recursos.

## Paso 5. Subir el repositorio y lanzar el CI/CD

En la raiz del proyecto, luego de completar el paso 4:

```bash
git init
git branch -M main
git add .
git commit -m "Reto Java AWS con Terraform y GitHub Actions"
git remote add origin https://github.com/TU_USUARIO/reto-java-aws.git
gh auth setup-git
git push -u origin main
```

Abre **GitHub > tu repositorio > Actions > CI/CD - Java a AWS ECS** y abre la ejecucion del `push`. Si GitHub pide habilitar los workflows, habilitalos. Tambien puedes ejecutarlo manualmente con `Run workflow`.

El flujo hace, en este orden:

1. Descarga codigo y ejecuta `mvn clean verify` con Java 21.
2. Autentica a AWS con **credenciales temporales OIDC**, no con claves permanentes.
3. Ejecuta `terraform init` con backend remoto en S3 y valida la configuracion.
4. Ejecuta **solo el recurso ECR** con un primer `terraform apply -target=...` para disponer del registro **antes** de subir la imagen (Terraform mostrara la advertencia esperada por uso de `-target`).
5. Construye el Dockerfile multietapa (Maven dentro de Docker), etiqueta la imagen de forma unica y la sube a ECR.
6. Ejecuta `terraform apply` completo para crear VPC, ALB, ECS Fargate, logs, rol de tarea y servicio con esa imagen.
7. Comprueba publicamente `/health` y publica la URL en el resumen de la ejecucion de Actions.

**Resultado esperado:**

```text
GET http://<DNS-DEL-BALANCEADOR>/
HTTP 200
{"mensaje":"Hola, mundo desde AWS ECS"}

GET http://<DNS-DEL-BALANCEADOR>/health
HTTP 200
{"status":"ok"}
```

No inventes un enlace de demostracion: el DNS real solo aparece despues de un despliegue exitoso en tu cuenta.

## Paso 6. Demostrar los entregables

Enviale al evaluador:

- **URL del repositorio GitHub** que contiene Java, Maven, Dockerfile, archivos `.tf` y workflows.
- **URL HTTP publica del ALB** y un ejemplo de respuesta (`/` o `/health`).
- **Capturas de GitHub Actions verde** (muestra prueba, push ECR y Terraform apply) y, opcionalmente, ECS Service con 1 tarea running, ECR con imagen y balanceador con target saludable.

### Relacion con los seis puntos del reto

| Requisito | Archivo o recurso |
|---|---|
| 1. Aplicacion Java | `src/main/java/.../HolaController.java` |
| 2. Compilacion Maven dockerizada | `pom.xml` + `Dockerfile` multietapa |
| 3. Imagen con runtime y codigo en ECR | `Dockerfile`, ECR en `infra/main.tf` y `deploy.yml` |
| 4. Cluster de contenedores con Terraform | `aws_ecs_cluster` + `aws_ecs_task_definition` |
| 5. Servicio desplegado con Terraform | `aws_ecs_service` + ALB en `infra/main.tf` |
| 6. Todo orquestado por GitHub Actions | `.github/workflows/deploy.yml` |

## Problemas frecuentes

- **`AccessDenied` o `UnauthorizedOperation`:** la cuenta sandbox no permite crear IAM, VPC, ECS, ALB, S3 o ECR. Revisa AWS IAM con el administrador. No evites la restriccion de forma insegura.
- **`Not authorized to perform sts:AssumeRoleWithWebIdentity`:** revisa la rama `main`, el ARN `AWS_ROLE_ARN` y vuelve a ejecutar `bootstrap.sh` si cambiaste de repositorio. El script reconoce los claims OIDC antiguos y los nuevos con IDs inmutables.
- **`Backend configuration changed` / S3 error:** revisa `TF_STATE_BUCKET`, `TF_STATE_KEY`, region y permisos del rol sobre el bucket. No borres manualmente el archivo de estado mientras la infraestructura esta activa.
- **`CannotPullContainerError`:** comprueba que la imagen exista en ECR y que la tarea tenga salida a Internet (subred publica y `assign_public_ip=true`) y el rol de ejecucion ECS configurado.
- **Balanceador responde 503/502:** entra a ECS > Cluster > Tasks para ver las razones de stop y a EC2 > Target Groups para verificar el health check `/health` en el puerto 8080. Revisa CloudWatch Logs (`/ecs/reto-java-ecs`).
- **No aparece un workflow:** comprueba que los `.yml` estan en `.github/workflows`, la rama es `main` y Actions esta habilitado.

## Paso 7. Evitar cargos al terminar

**Despues de guardar las evidencias**, abre GitHub > Actions > **Limpiar infraestructura AWS (manual)** > **Run workflow**, escribe exactamente `DESTROY` y ejecuta. Esto destruye recursos de Terraform, incluyendo ECR y la imagen, ECS, ALB, VPC y logs. No borres el backend S3 antes de terminar el `destroy`.

**Despues** de que el workflow indique exito, en tu computadora elimina el rol potente usado para el laboratorio:

```bash
AWS_REGION=us-east-1 ./scripts/remove-access.sh TU_USUARIO/reto-java-aws
```

El bucket S3 del backend y su historial de versiones no se eliminan automaticamente porque podrian ser compartidos; si ya no lo necesitas, vacialo **incluyendo versiones** y borrarlo desde la consola de S3. Revisa AWS Billing y Budget Alerts si tu sandbox permite usarlos. Si hubo un despliegue parcial, ejecuta primero el destroy y comprueba manualmente los recursos.

## Observaciones

- `AdministratorAccess` es una simplificacion intencional para una **cuenta sandbox dedicada**, con acceso limitado por rol OIDC al repositorio/branch. Para una implementacion empresarial se debe reemplazar por politicas IAM de minimo privilegio y aprobaciones.
- La arquitectura expone **HTTP, no HTTPS**; cumple el endpoint publico del reto pero no esta lista para produccion.
- No se ha desplegado en tu AWS real desde este paquete; tendras que ejecutar los pasos en tu cuenta y ver el resultado en Actions.
- Este proyecto es un punto de partida educativo reproducible. Los precios, permisos y servicios disponibles pueden variar segun region y tipo de sandbox.
