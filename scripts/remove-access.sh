#!/usr/bin/env bash
# Ejecutar solamente DESPUES de terraform destroy, para no dejar Admin en la sandbox.
set -euo pipefail
if [[ $# -ne 1 || "$1" != */* ]]; then
  echo "Uso: ./scripts/remove-access.sh USUARIO/REPOSITORIO" >&2
  exit 1
fi
for command_name in aws gh; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Falta instalar: $command_name" >&2
    exit 1
  fi
done
REPO="$1"
ROLE_ARN="$(gh variable get AWS_ROLE_ARN --repo "$REPO")"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ "$ROLE_ARN" != "arn:aws:iam::${ACCOUNT_ID}:role/reto-java-"* ]]; then
  echo "El rol no parece corresponder a este proyecto o cuenta AWS: $ROLE_ARN" >&2
  exit 1
fi
ROLE_NAME="${ROLE_ARN##*/}"
echo "Se eliminara el rol IAM: ${ROLE_NAME}"
read -r -p "Confirma escribiendo BORRAR: " CONFIRM
if [[ "$CONFIRM" != "BORRAR" ]]; then
  echo "Cancelado"
  exit 1
fi
aws iam detach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-role --role-name "$ROLE_NAME"
gh variable delete AWS_ROLE_ARN --repo "$REPO"
echo "Rol IAM de acceso al laboratorio eliminado."
