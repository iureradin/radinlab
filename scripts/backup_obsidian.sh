#!/bin/bash
# backup_obsidian.sh
# Realiza backup incremental do vault Obsidian via SMB para o share de backup.
# Salva status em /tmp/backup-status.json para consolidação com outros backups.

set -uo pipefail

# Configurações
SMB_HOST="10.0.0.50"
SMB_SHARE="obsidian"
SMB_USER="jarvis"
SMB_PASS="Radin10@@@"
SMB_DOMAIN="KAKASHI-PC"

MOUNT_POINT="/mnt/smb-obsidian"
BACKUP_DEST="/mnt/hd1tb/backup/obsidian"
STATUS_FILE="/tmp/backup-status.json"

log() {
    echo "[$(date '+%d/%m/%Y %H:%M:%S')] $1"
}

cleanup() {
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log "Desmontando share SMB..."
        umount "$MOUNT_POINT" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Inicializa status como falha (será sobrescrito em caso de sucesso)
update_status() {
    local status="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%d/%m/%Y %H:%M:%S')

    # Lê status existente (snapshot) ou inicializa
    local snapshot_status="unknown"
    local snapshot_message=""
    if [[ -f "$STATUS_FILE" ]]; then
        snapshot_status=$(python3 -c "import json,sys; d=json.load(open('$STATUS_FILE')); print(d.get('snapshot',{}).get('status','unknown'))" 2>/dev/null || echo "unknown")
        snapshot_message=$(python3 -c "import json,sys; d=json.load(open('$STATUS_FILE')); print(d.get('snapshot',{}).get('message',''))" 2>/dev/null || echo "")
    fi

    cat > "$STATUS_FILE" <<EOF
{
  "snapshot": {
    "status": "$snapshot_status",
    "message": "$snapshot_message"
  },
  "obsidian": {
    "status": "$status",
    "message": "$message",
    "timestamp": "$timestamp"
  }
}
EOF
}

log "=== Iniciando backup do Obsidian ==="

# Cria diretórios necessários
mkdir -p "$MOUNT_POINT" "$BACKUP_DEST"

# Monta share SMB
log "Montando share //${SMB_HOST}/${SMB_SHARE}..."
if ! mount -t cifs "//${SMB_HOST}/${SMB_SHARE}" "$MOUNT_POINT" \
    -o "username=${SMB_USER},password=${SMB_PASS},domain=${SMB_DOMAIN},uid=0,gid=0,ro" 2>&1; then
    log "✗ ERRO: falha ao montar share SMB"
    update_status "error" "Falha ao montar share SMB //${SMB_HOST}/${SMB_SHARE}"
    exit 1
fi
log "✓ Share montado com sucesso"

# Executa rsync incremental
log "Iniciando rsync para ${BACKUP_DEST}..."
RSYNC_OUTPUT=$(rsync -av --delete \
    --exclude=".obsidian/workspace.json" \
    --exclude=".obsidian/workspace-mobile.json" \
    --exclude=".trash/" \
    "$MOUNT_POINT/" \
    "$BACKUP_DEST/" 2>&1)
RSYNC_EXIT=$?

if [[ $RSYNC_EXIT -eq 0 ]]; then
    FILES_TRANSFERRED=$(echo "$RSYNC_OUTPUT" | grep -c '^[^/].*/$\|^[^/].*[^/]$' 2>/dev/null || echo "0")
    log "✓ Backup concluído com sucesso"
    log "Output rsync: $(echo "$RSYNC_OUTPUT" | tail -5)"
    update_status "success" "Backup concluído — $(date '+%d/%m/%Y %H:%M')"
else
    log "✗ ERRO no rsync (exit: $RSYNC_EXIT)"
    log "$RSYNC_OUTPUT"
    update_status "error" "Erro no rsync (exit ${RSYNC_EXIT}): $(echo "$RSYNC_OUTPUT" | tail -3 | tr '\n' ' ')"
    exit 1
fi

log "=== Backup do Obsidian finalizado ==="
exit 0
