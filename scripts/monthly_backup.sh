#!/bin/bash
# monthly_backup.sh
# Backup mensal de todos os containers e VMs via vzdump
# Envia para share SMB //10.0.0.50/backup/vm-proxmox/
# Mantém as últimas 4 versões de cada VM/CT

set -euo pipefail

# Configuração
SMB_HOST="//10.0.0.50/backup"
SMB_USER="jarvis"
SMB_PASS="Radin10@@@"
SMB_MOUNT="/mnt/backup-windows"
BACKUP_DEST="${SMB_MOUNT}/vm-proxmox"
MAX_BACKUPS=4
VZDUMP_TMPDIR="/mnt/hd1tb/backup-tmp"
DATE_TAG=$(date +%Y%m)
ERRORS=()
SUCCESS=()

log() {
    echo "[$(date '+%d/%m/%Y %H:%M:%S')] $1"
}

# Monta o share SMB
mount_smb() {
    log "Montando share SMB ${SMB_HOST}..."
    mkdir -p "${SMB_MOUNT}"
    if ! mountpoint -q "${SMB_MOUNT}"; then
        mount -t cifs "${SMB_HOST}" "${SMB_MOUNT}" \
            -o "username=${SMB_USER},password=${SMB_PASS},uid=0,gid=0,file_mode=0755,dir_mode=0755,vers=3.0"
    fi
    mkdir -p "${BACKUP_DEST}"
    log "✓ Share montado em ${SMB_MOUNT}"
}

# Desmonta o share SMB
umount_smb() {
    if mountpoint -q "${SMB_MOUNT}"; then
        umount "${SMB_MOUNT}" && log "Share SMB desmontado."
    fi
}

# Garante diretório temporário local
setup_tmpdir() {
    mkdir -p "${VZDUMP_TMPDIR}"
}

# Lista todos os CTs
get_all_cts() {
    pct list | tail -n +2 | awk '{print $1}' | while read -r vmid; do
        local name
        name=$(pct config "$vmid" | grep -oP '^hostname:\s*\K.*' || echo "$vmid")
        echo "ct:${vmid}:${name}"
    done
}

# Lista todas as VMs
get_all_vms() {
    qm list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r vmid; do
        local name
        name=$(qm config "$vmid" | grep -oP '^name:\s*\K.*' || echo "$vmid")
        echo "vm:${vmid}:${name}"
    done
}

# Faz o backup via vzdump
do_backup() {
    local type="$1" vmid="$2" name="$3"
    local dest_dir="${BACKUP_DEST}/${type}-${vmid}-${name}"

    mkdir -p "${dest_dir}"
    log "Iniciando backup: ${type} ${vmid} (${name})..."

    local vzdump_args=(
        --compress zstd
        --mode snapshot
        --tmpdir "${VZDUMP_TMPDIR}"
        --dumpdir "${dest_dir}"
        --notes-template "Backup mensal ${DATE_TAG}"
    )

    # Modo stop se snapshot falhar (CTs com bind mounts não suportam snapshot)
    if [[ "$type" == "ct" ]]; then
        if vzdump "$vmid" "${vzdump_args[@]}" 2>&1; then
            log "✓ Backup concluído: ct ${vmid} (${name})"
            SUCCESS+=("ct ${vmid} (${name})")
        else
            log "Snapshot falhou para ct ${vmid}, tentando modo stop..."
            vzdump_args[3]="stop"  # troca mode
            if vzdump "$vmid" --compress zstd --mode stop --tmpdir "${VZDUMP_TMPDIR}" --dumpdir "${dest_dir}" 2>&1; then
                log "✓ Backup concluído (modo stop): ct ${vmid} (${name})"
                SUCCESS+=("ct ${vmid} (${name})")
            else
                log "✗ ERRO no backup: ct ${vmid} (${name})"
                ERRORS+=("ct ${vmid} (${name}): falha no vzdump")
            fi
        fi
    elif [[ "$type" == "vm" ]]; then
        if vzdump "$vmid" "${vzdump_args[@]}" 2>&1; then
            log "✓ Backup concluído: vm ${vmid} (${name})"
            SUCCESS+=("vm ${vmid} (${name})")
        else
            log "✗ ERRO no backup: vm ${vmid} (${name})"
            ERRORS+=("vm ${vmid} (${name}): falha no vzdump")
        fi
    fi
}

# Remove backups antigos — mantém os últimos MAX_BACKUPS por CT/VM
cleanup_old_backups() {
    local type="$1" vmid="$2" name="$3"
    local dest_dir="${BACKUP_DEST}/${type}-${vmid}-${name}"

    [[ ! -d "$dest_dir" ]] && return

    # Lista arquivos .zst ordenados por data (mais antigos primeiro)
    local files
    mapfile -t files < <(ls -t "${dest_dir}"/*.zst 2>/dev/null || true)
    local count=${#files[@]}

    if [[ $count -gt $MAX_BACKUPS ]]; then
        local excess=$(( count - MAX_BACKUPS ))
        log "Removendo ${excess} backup(s) antigo(s) de ${type} ${vmid} (${name})..."
        for (( i=count-1; i>=MAX_BACKUPS; i-- )); do
            local old_file="${files[$i]}"
            local old_log="${old_file%.zst}.log"
            rm -f "$old_file" "$old_log"
            log "  Removido: $(basename "$old_file")"
        done
    fi
}

# Trap para garantir desmontagem em caso de erro
trap umount_smb EXIT

# === MAIN ===
log "=== Iniciando backup mensal RadinLab ==="
log "Data: $(date '+%d/%m/%Y') | Destino: ${SMB_HOST}/vm-proxmox/"

setup_tmpdir
mount_smb

# Coleta todos os alvos
TARGETS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && TARGETS+=("$line")
done < <(get_all_cts)
while IFS= read -r line; do
    [[ -n "$line" ]] && TARGETS+=("$line")
done < <(get_all_vms)

log "Total de alvos: ${#TARGETS[@]}"

for target in "${TARGETS[@]}"; do
    IFS=: read -r type vmid name <<< "$target"
    do_backup "$type" "$vmid" "$name"
    cleanup_old_backups "$type" "$vmid" "$name"
done

# Limpa tmp
rm -rf "${VZDUMP_TMPDIR:?}"/*

# Resultado
echo ""
log "=== Resultado ==="
log "Sucesso: ${#SUCCESS[@]} | Erros: ${#ERRORS[@]}"

for item in "${SUCCESS[@]}"; do
    log "  ✓ $item"
done

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    log "ERROS:"
    for err in "${ERRORS[@]}"; do
        log "  ✗ $err"
    done
    exit 1
fi

log "Backup mensal concluído com sucesso!"
exit 0
