#!/bin/bash
set -euo pipefail

# Restaura golden image do S3 e converte em template no Proxmox
# Requer: SSH do runner para o host Proxmox + AWS credentials

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

# Baixar do S3 para o host Proxmox via runner como intermediário
aws s3 cp "$S3_PATH" /tmp/zimaos-base.vma.zst
scp /tmp/zimaos-base.vma.zst root@"$PROXMOX_HOST":"$REMOTE_TMP"
rm /tmp/zimaos-base.vma.zst

# Restaurar e converter em template
ssh root@"$PROXMOX_HOST" "
  qmrestore $REMOTE_TMP $TEMPLATE_VMID --storage local-lvm
  qm template $TEMPLATE_VMID
  rm $REMOTE_TMP
"

echo "Template $TEMPLATE_VMID restaurado e convertido com sucesso."
