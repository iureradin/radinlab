#!/bin/bash
# weekly_fullbackup.sh
# Backup completo semanal de todas VMs e CTs via vzdump para SMB (.50)
# Destino: /mnt/cifs/backup/vm-proxmox/<nome>/
# Mantém 4 backups por VM/CT (remove o mais antigo quando exceder)
# Valida integridade após upload
# Grava resultado em /tmp/fullbackup-status.json

set -uo pipefail

BACKUP_DEST="/mnt/cifs/backup/vm-proxmox"
MAX_BACKUPS=4
STATUS_FILE="/tmp/fullbackup-status.json"
TIMESTAMP=$(date '+%d/%m/%Y %H:%M:%S')
ERRORS=()
SUCCESS=()

TELEGRAM_BOT_TOKEN="8846315620:AAEPbRUFRIK6tOSI5HwtHjNEIJ_oHAglznM"
TELEGRAM_CHAT_ID="620923420"

log() { echo "[$(date '+%d/%m/%Y %H:%M:%S')] $1"; }

telegram_msg() {
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=$1" > /dev/null 2>&1 || true
}

check_dest() {
    if ! mountpoint -q /mnt/cifs/backup 2>/dev/null; then
        log "ERRO: /mnt/cifs/backup nao esta montado"
        return 1
    fi
    mkdir -p "$BACKUP_DEST" 2>/dev/null || { log "ERRO: nao foi possivel criar $BACKUP_DEST"; return 1; }
    local testfile="$BACKUP_DEST/.write_test_$$"
    touch "$testfile" 2>/dev/null || { log "ERRO: sem permissao de escrita em $BACKUP_DEST"; return 1; }
    rm -f "$testfile"
    return 0
}

# Remove backups antigos mantendo apenas MAX_BACKUPS
cleanup_old_backups() {
    local dest_dir="$1"
    local files
    mapfile -t files < <(find "$dest_dir" -maxdepth 1 \( -name "*.vma.zst" -o -name "*.tar.zst" \) -printf '%T@ %p\n' 2>/dev/null | sort -n | awk '{print $2}')
    local count=${#files[@]}
    if [[ $count -gt $MAX_BACKUPS ]]; then
        local to_delete=$(( count - MAX_BACKUPS ))
        for (( i=0; i<to_delete; i++ )); do
            log "  Removendo backup antigo: $(basename "${files[$i]}")"
            rm -f "${files[$i]}" "${files[$i]%.zst}.log" 2>/dev/null || true
        done
    fi
}

do_backup() {
    local type="$1" vmid="$2" name="$3" mode="$4"
    local dest_dir="$BACKUP_DEST/$name"
    mkdir -p "$dest_dir"

    log "Iniciando backup $type $vmid ($name) modo=$mode..."

    local output
    if output=$(vzdump "$vmid" \
        --mode "$mode" \
        --compress zstd \
        --dumpdir "$dest_dir" \
        2>&1); then

        # Valida arquivo criado
        local backup_file
        backup_file=$(find "$dest_dir" -maxdepth 1 \( -name "*.vma.zst" -o -name "*.tar.zst" \) -newer "$dest_dir" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')

        if [[ -z "$backup_file" ]]; then
            # Fallback: pegar o mais recente
            backup_file=$(find "$dest_dir" -maxdepth 1 \( -name "*.vma.zst" -o -name "*.tar.zst" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
        fi

        if [[ -z "$backup_file" ]]; then
            log "ERRO: $type $vmid ($name) - arquivo nao encontrado apos vzdump"
            ERRORS+=("$type $vmid ($name): arquivo nao encontrado")
            return 1
        fi

        local size
        size=$(stat -c%s "$backup_file" 2>/dev/null || echo 0)
        if [[ "$size" -lt 1048576 ]]; then
            log "ERRO: $type $vmid ($name) - arquivo suspeito (${size} bytes)"
            ERRORS+=("$type $vmid ($name): arquivo suspeito (${size} bytes)")
            return 1
        fi

        local size_hr
        size_hr=$(du -sh "$backup_file" 2>/dev/null | cut -f1)
        log "OK: $type $vmid ($name) -> $(basename "$backup_file") ($size_hr)"
        SUCCESS+=("$type $vmid ($name) [${size_hr}]")

        # Limpa backups antigos mantendo MAX_BACKUPS
        cleanup_old_backups "$dest_dir"
        return 0
    else
        log "ERRO: vzdump $type $vmid ($name)"
        log "  $output" | tail -3
        ERRORS+=("$type $vmid ($name): $(echo "$output" | grep -i 'error\|err\|fail' | tail -1 | cut -c1-80)")
        return 1
    fi
}

get_backup_mode() {
    local type="$1" vmid="$2"
    local status
    if [[ "$type" == "ct" ]]; then
        status=$(pct status "$vmid" 2>/dev/null | awk '{print $2}')
    else
        status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')
    fi
    # VMs running usam snapshot (sem downtime), CTs running usam stop
    if [[ "$status" == "running" && "$type" == "vm" ]]; then
        echo "snapshot"
    else
        echo "stop"
    fi
}

# Main
log "=== Iniciando weekly full backup ==="
log "Destino: $BACKUP_DEST | Retencao: $MAX_BACKUPS versoes por VM/CT"

if ! check_dest; then
    telegram_msg "[RadinLab] ERRO: weekly full backup falhou - share SMB inacessivel!"
    exit 1
fi

log "Share SMB OK. Espaco disponivel: $(df -h /mnt/cifs/backup | tail -1 | awk '{print $4}')"

log "--- Backup de Containers LXC ---"
while IFS= read -r line; do
    vmid=$(echo "$line" | awk '{print $1}')
    [[ -z "$vmid" || "$vmid" == "VMID" ]] && continue
    name=$(pct config "$vmid" 2>/dev/null | grep -oP '^hostname:\s*\K.*' || echo "ct-$vmid")
    mode=$(get_backup_mode "ct" "$vmid")
    do_backup "ct" "$vmid" "$name" "$mode"
done < <(pct list 2>/dev/null | tail -n +2)

log "--- Backup de VMs QEMU ---"
while IFS= read -r line; do
    vmid=$(echo "$line" | awk '{print $1}')
    [[ -z "$vmid" || "$vmid" == "VMID" ]] && continue
    name=$(qm config "$vmid" 2>/dev/null | grep -oP '^name:\s*\K.*' || echo "vm-$vmid")
    mode=$(get_backup_mode "vm" "$vmid")
    do_backup "vm" "$vmid" "$name" "$mode"
done < <(qm list 2>/dev/null | tail -n +2)

echo ""
log "=== Resultado ==="
log "Sucesso: ${#SUCCESS[@]} | Erros: ${#ERRORS[@]}"
for s in "${SUCCESS[@]}"; do log "  + $s"; done
for e in "${ERRORS[@]}"; do log "  - ERRO: $e"; done

# Status final
FINAL_STATUS="success"
FINAL_MSG="Sucesso: ${#SUCCESS[@]} alvos"
ERROR_LIST_STR=""
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    FINAL_STATUS="error"
    ERROR_LIST_STR=$(printf '%s | ' "${ERRORS[@]}" | sed 's/ | $//')
    FINAL_MSG="Sucesso: ${#SUCCESS[@]} | Erros: ${#ERRORS[@]} -- ${ERROR_LIST_STR}"
fi

cat > "$STATUS_FILE" << STATUS_EOF
{
  "fullbackup": {
    "status": "$FINAL_STATUS",
    "message": "$FINAL_MSG",
    "timestamp": "$TIMESTAMP"
  }
}
STATUS_EOF

# Notificação Telegram
SUCCESS_LINES=$(printf '%s\n' "${SUCCESS[@]}" | sed 's/^/  /' | head -15)
if [[ "$FINAL_STATUS" == "success" ]]; then
    telegram_msg "Weekly Full Backup - RadinLab
${TIMESTAMP}

Sucesso: ${#SUCCESS[@]} VMs/CTs
${SUCCESS_LINES}"
    log "Backup semanal concluido com sucesso!"
    exit 0
else
    ERROR_LINES=$(printf '%s\n' "${ERRORS[@]}" | sed 's/^/  ERRO: /' | head -10)
    telegram_msg "ERRO - Weekly Full Backup - RadinLab
${TIMESTAMP}

Sucesso: ${#SUCCESS[@]} | Erros: ${#ERRORS[@]}
${ERROR_LINES}"
    log "Backup semanal concluido com erros!"
    exit 1
fi
