#!/usr/bin/env bash
# Uso: AWS_REGION=us-east-1 ./scripts/bootstrap.sh TU_USUARIO/NOMBRE_REPO
# Requiere: aws CLI con sesion iniciada y gh CLI autenticado (gh auth login).
set -euo pipefail

if [[ $# -ne 1 || "$1" != */* ]]; then
  echo "Uso: AWS_REGION=us-east-1 ./scripts/bootstrap.sh USUARIO/REPOSITORIO" >&2
  exit 1
fi
for command_name in aws gh; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Falta instalar: $command_name" >&2
    exit 1
  fi
done

INPUT_REPO="$1"
AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
OWNER="$(gh api "repos/${INPUT_REPO}" --jq '.owner.login')"
REPO="$(gh api "repos/${INPUT_REPO}" --jq '.name')"
OWNER_ID="$(gh api "repos/${INPUT_REPO}" --jq '.owner.id')"
REPO_ID="$(gh api "repos/${INPUT_REPO}" --jq '.id')"
GITHUB_REPO="${OWNER}/${REPO}"

# Un bucket S3 por cuenta y region; el key se separa por proyecto.
STATE_BUCKET="tfstate-reto-${ACCOUNT_ID}-${AWS_REGION}"
STATE_KEY="reto-java-${REPO}/terraform.tfstate"
if ! aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; then
  echo "Creando bucket S3 privado: $STATE_BUCKET"
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi
fi
aws s3api put-public-access-block --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
if ! aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url 'https://token.actions.githubusercontent.com' \
    --client-id-list 'sts.amazonaws.com' >/dev/null
fi

# GitHub 2026: los repos nuevos incluyen IDs inmutables en el claim sub.
# Se aceptan ambas formas EXCLUSIVAMENTE para este repositorio y rama main.
TRUST_FILE="$(mktemp)"
trap 'rm -f "$TRUST_FILE"' EXIT
cat > "$TRUST_FILE" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "$OIDC_ARN"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": [
          "repo:${OWNER}/${REPO}:ref:refs/heads/main",
          "repo:${OWNER}@${OWNER_ID}/${REPO}@${REPO_ID}:ref:refs/heads/main"
        ]
      }
    }
  }]
}
JSON

# El lab usa AdministratorAccess en la cuenta sandbox para simplificar IAM
# de VPC/ALB/ECS/ECR. NUNCA usar este permiso para un entorno productivo.
SAFE_REPO="$(printf '%s' "$REPO" | tr -c 'A-Za-z0-9-_' '-')"
ROLE_NAME="reto-java-${SAFE_REPO:0:35}-deploy"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" \
    --policy-document "file://${TRUST_FILE}"
else
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${TRUST_FILE}" >/dev/null
fi
aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn 'arn:aws:iam::aws:policy/AdministratorAccess'
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

gh variable set AWS_REGION --repo "$GITHUB_REPO" --body "$AWS_REGION"
gh variable set AWS_ROLE_ARN --repo "$GITHUB_REPO" --body "$ROLE_ARN"
gh variable set TF_STATE_BUCKET --repo "$GITHUB_REPO" --body "$STATE_BUCKET"
gh variable set TF_STATE_KEY --repo "$GITHUB_REPO" --body "$STATE_KEY"

cat <<MSG

BOOTSTRAP OK
Repositorio GitHub: $GITHUB_REPO
Region AWS:         $AWS_REGION
Cuenta AWS:         $ACCOUNT_ID
Bucket Terraform:   $STATE_BUCKET
Key Terraform:      $STATE_KEY
Rol OIDC:           $ROLE_ARN

Siguiente paso: publica el proyecto en la rama main y revisa Actions > CI/CD.
IMPORTANTE: este rol tiene AdministratorAccess SOLO para la sandbox.
MSG
