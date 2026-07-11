#!/bin/bash
set -euo pipefail

# Restaura golden image do S3 e converte em template no Proxmox
# O download é feito diretamente no host (evita encher o runner)

PROXMOX_HOST="${PROXMOX_HOST:-10.0.0.80}"
TEMPLATE_VMID="${TEMPLATE_VMID:-105}"
S3_PATH="s3://radinlab-backups/templates/zimaos-base.vma.zst"
REMOTE_TMP="/var/lib/vz/dump/zimaos-base.vma.zst"

# Verificar se template já existe
if ssh -o StrictHostKeyChecking=accept-new root@"$PROXMOX_HOST" "qm status $TEMPLATE_VMID" 2>/dev/null | grep -q "status:"; then
  echo "Template $TEMPLATE_VMID já existe, seguindo..."
  exit 0
fi

echo "Template $TEMPLATE_VMID não encontrado. Restaurando do S3..."

# Instalar AWS CLI no host se não existir, e baixar direto
ssh root@"$PROXMOX_HOST" "
  export AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID'
  export AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY'
  export AWS_DEFAULT_REGION='${AWS_REGION:-us-east-1}'

  # Baixar do S3
  /usr/local/bin/aws s3 cp $S3_PATH $REMOTE_TMP

  # Restaurar e converter em template
  qmrestore $REMOTE_TMP $TEMPLATE_VMID --storage local-lvm
  qm template $TEMPLATE_VMID
  rm $REMOTE_TMP
"

echo "Template $TEMPLATE_VMID restaurado e convertido com sucesso."
