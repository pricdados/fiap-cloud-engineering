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

# Roda um comando shell na EC2 via SSM e devolve o stdout dele (aguardando terminar).
ssm_exec() {
  local instance="$1" cmd="$2" cid saida estado
  cid=$(aws ssm send-command --instance-ids "$instance" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="$cmd" \
    --query "Command.CommandId" --output text 2>/dev/null) || return 1
  for _ in $(seq 1 20); do
    sleep 3
    estado=$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$instance" \
      --query "Status" --output text 2>/dev/null)
    case "$estado" in Success|Failed|Cancelled|TimedOut) break ;; esac
  done
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$instance" \
    --query "StandardOutputContent" --output text 2>/dev/null
}

# Garante que o EFS esta REALMENTE montado em /efs na EC2 antes de liberar o aluno.
# Sem isso, se o mount do user-data falhar, os pedidos vao para o disco local e o
# lab "funciona" sem nunca tocar o EFS — a licao (migrar de file storage) fica vazia.
garante_efs_montado() {
  local instance efs_ip
  instance="$(terraform -chdir="$TF/01-storage" output -raw instance_id)"
  efs_ip="$(terraform -chdir="$TF/01-storage" output -raw efs_mount_ip)"

  log ""
  log "==> Aguardando a EC2 registrar no SSM (user-data monta o EFS e planta os pedidos)..."
  for _ in $(seq 1 30); do
    ping=$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$instance" \
      --query "InstanceInformationList[0].PingStatus" --output text 2>/dev/null)
    [ "$ping" = "Online" ] && break
    sleep 10
  done

  # Monta via IP do mount target (NFS 4.1). No Learner Lab o DNS do EFS nao
  # resolve e o fallback do amazon-efs-utils depende de botocore (ausente),
  # entao montar por IP e o caminho robusto.
  local mnt="mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${efs_ip}:/ /efs"
  log "==> Verificando se /efs esta montado como EFS (nao disco local)..."
  for tentativa in $(seq 1 6); do
    montado=$(ssm_exec "$instance" "mountpoint -q /efs && echo MONTADO || echo NAO" | tr -d '[:space:]')
    if [ "$montado" = "MONTADO" ]; then
      log "    /efs montado. OK."
      break
    fi
    log "    ainda nao montado (tentativa $tentativa/6) — tentando montar via IP ${efs_ip}..."
    ssm_exec "$instance" "sudo mkdir -p /efs && sudo $mnt && sudo mkdir -p /efs/pedidos" >/dev/null
    sleep 20
  done

  # Confirmacao final: /efs montado E com os 10 pedidos dentro. Se o mount subiu
  # DEPOIS de o user-data plantar, os arquivos foram para o disco local e o /efs
  # (agora montado) esta vazio — entao replantamos a partir do dataset que o
  # user-data deixou em /tmp/pedidos.json na propria EC2.
  n=$(ssm_exec "$instance" "ls /efs/pedidos 2>/dev/null | wc -l" | tr -d '[:space:]')
  if [ "${n:-0}" != "10" ]; then
    log "    /efs tem '${n:-0}' pedidos (esperado 10) — replantando no EFS montado..."
    ssm_exec "$instance" "sudo mkdir -p /efs/pedidos; jq -c '.[]' /tmp/pedidos.json | while read -r p; do id=\$(echo \"\$p\" | jq -r '.pedido_id'); echo \"\$p\" | sudo tee /efs/pedidos/\$id.json >/dev/null; done; ls /efs/pedidos | wc -l" >/dev/null
    n=$(ssm_exec "$instance" "ls /efs/pedidos 2>/dev/null | wc -l" | tr -d '[:space:]')
  fi

  if [ "${n:-0}" = "10" ]; then
    log "==> EFS montado e com 10 pedidos. Pronto para a migracao do Bloco 1."
  else
    log "==> ATENCAO: /efs tem '${n:-0}' pedidos apos as tentativas. Verifique manualmente na EC2 (df -hT /efs)."
  fi
}

# Ordem obrigatoria: storage cria o bucket que os outros dois referenciam.
aplica "01-storage"  "01-storage"
garante_efs_montado
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
