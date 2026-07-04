#!/usr/bin/env bash
# Provisiona TODA a infraestrutura do Trabalho Final (fase 0, automatizada).
# O aluno roda este script uma vez; ele descobre o bucket de estado, inicializa
# e aplica os 3 stacks Terraform na ordem certa. Nada de copiar ARN ou nome de
# bucket a mao. stdout = resultado; progresso e status vao para stderr.
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$RAIZ/terraform"

log "==> Validando credenciais AWS..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  log "ERRO: credenciais invalidas/expiradas. Renove as credenciais da AWS Academy e rode de novo."
  exit 1
fi

log "==> Descobrindo o bucket de estado (prefixo base-config-)..."
BUCKET_STATE="$(aws s3 ls | awk '/base-config-/ {print $3; exit}')"
if [ -z "${BUCKET_STATE:-}" ]; then
  log "ERRO: nenhum bucket base-config- encontrado. Rode o setup da aula (Preparando Credenciais) e tente de novo."
  exit 1
fi
log "    bucket de estado: $BUCKET_STATE"

aplica() {
  local dir="$1" chave="$2"
  log ""
  log "==> [$dir] terraform init + apply"
  terraform -chdir="$TF/$dir" init -reconfigure \
    -backend-config="bucket=$BUCKET_STATE" \
    -backend-config="key=trabalho-final/$chave/terraform.tfstate" \
    -backend-config="region=us-east-1" >&2
  terraform -chdir="$TF/$dir" apply -auto-approve >&2
}

# Ordem obrigatoria: storage cria o bucket que os outros dois referenciam.
aplica "01-storage"  "01-storage"
aplica "02-processa" "02-processa"
aplica "03-api"      "03-api"

# Resultado (stdout): os valores que o aluno vai usar nos proximos passos.
API_URL="$(terraform -chdir="$TF/03-api" output -raw api_url)"
BUCKET="$(terraform -chdir="$TF/01-storage" output -raw bucket_datalake)"
INSTANCE="$(terraform -chdir="$TF/01-storage" output -raw instance_id)"

log ""
log "==> Provisionamento concluido. Guarde os valores abaixo:"
echo "BUCKET=$BUCKET"
echo "INSTANCE_ID=$INSTANCE"
echo "API_URL=$API_URL"
