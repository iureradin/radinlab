#!/bin/bash
# daily_snapshot.sh
# Cria snapshots diários de containers/VMs com tag 'daily_snapshot'
# Mantém no máximo 3 snapshots por VM/container
# Uso: ./daily_snapshot.sh

set -euo pipefail

SNAPSHOT_TAG="daily_snapshot"
MAX_SNAPSHOTS=3
SNAPSHOT_NAME="auto_$(date +%d%m%Y_%H%M)"
ERRORS=()
SUCCESS=()

log() {
    echo "[$(date '+%d/%m/%Y %H:%M:%S')] $1"
}

# Busca containers LXC com a tag daily_snapshot
get_tagged_cts() {
    pct list | tail -n +2 | awk '{print $1}' | while read -r vmid; do
        local tags name
        name=$(pct config "$vmid" | grep -oP '^hostname:\s*\K.*' || echo "$vmid")
        tags=$(pct config "$vmid" | grep -oP '^tags:\s*\K.*' || true)
        if echo "$tags" | grep -qw "$SNAPSHOT_TAG"; then
            echo "ct:$vmid:$name"
        fi
    done
}

# Busca VMs QEMU com a tag daily_snapshot
get_tagged_vms() {
    qm list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r vmid; do
        local tags name
        name=$(qm config "$vmid" | grep -oP '^name:\s*\K.*' || echo "$vmid")
        tags=$(qm config "$vmid" | grep -oP '^tags:\s*\K.*' || true)
        if echo "$tags" | grep -qw "$SNAPSHOT_TAG"; then
            echo "vm:$vmid:$name"
        fi
    done
}

# Cria snapshot
create_snapshot() {
    local type="$1" vmid="$2" name="$3"

    log "Criando snapshot '$SNAPSHOT_NAME' para $type $vmid ($name)..."

    if [[ "$type" == "ct" ]]; then
        if pct snapshot "$vmid" "$SNAPSHOT_NAME" --description "Auto snapshot $(date '+%d/%m/%Y %H:%M')"; then
            log "✓ Snapshot criado: $type $vmid ($name)"
            SUCCESS+=("$type $vmid ($name)")
        else
            log "✗ ERRO ao criar snapshot: $type $vmid ($name)"
            ERRORS+=("$type $vmid ($name): falha ao criar snapshot")
        fi
    elif [[ "$type" == "vm" ]]; then
        if qm snapshot "$vmid" "$SNAPSHOT_NAME" --description "Auto snapshot $(date '+%d/%m/%Y %H:%M')"; then
            log "✓ Snapshot criado: $type $vmid ($name)"
            SUCCESS+=("$type $vmid ($name)")
        else
            log "✗ ERRO ao criar snapshot: $type $vmid ($name)"
            ERRORS+=("$type $vmid ($name): falha ao criar snapshot")
        fi
    fi
}

# Remove snapshots antigos (mantém apenas MAX_SNAPSHOTS)
cleanup_snapshots() {
    local type="$1" vmid="$2" name="$3"

    log "Verificando snapshots antigos de $type $vmid ($name)..."

    local snapshots
    if [[ "$type" == "ct" ]]; then
        snapshots=$(pct listsnapshot "$vmid" | grep -oP '^\s*\`->\s*\K(auto_\S+)|^\s*\K(auto_\S+)' | sort)
    elif [[ "$type" == "vm" ]]; then
        snapshots=$(qm listsnapshot "$vmid" | grep -oP '^\s*\`->\s*\K(auto_\S+)|^\s*\K(auto_\S+)' | sort)
    fi

    local count
    count=$(echo "$snapshots" | grep -c . || true)

    if [[ "$count" -gt "$MAX_SNAPSHOTS" ]]; then
        local to_delete
        to_delete=$(echo "$snapshots" | head -n $((count - MAX_SNAPSHOTS)))

        while IFS= read -r snap; do
            [[ -z "$snap" ]] && continue
            log "Removendo snapshot antigo '$snap' de $type $vmid ($name)..."
            if [[ "$type" == "ct" ]]; then
                pct delsnapshot "$vmid" "$snap" || ERRORS+=("$type $vmid ($name): falha ao remover $snap")
            elif [[ "$type" == "vm" ]]; then
                qm delsnapshot "$vmid" "$snap" || ERRORS+=("$type $vmid ($name): falha ao remover $snap")
            fi
        done <<< "$to_delete"
    fi
}

# Main
log "=== Iniciando daily snapshot ==="
log "Tag: $SNAPSHOT_TAG | Max snapshots: $MAX_SNAPSHOTS"

# Coleta VMs/CTs com a tag
TARGETS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && TARGETS+=("$line")
done < <(get_tagged_cts)
while IFS= read -r line; do
    [[ -n "$line" ]] && TARGETS+=("$line")
done < <(get_tagged_vms)

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    log "Nenhuma VM/CT encontrada com tag '$SNAPSHOT_TAG'"
    exit 0
fi

log "Encontrados ${#TARGETS[@]} alvos: ${TARGETS[*]}"

# Processa cada alvo
for target in "${TARGETS[@]}"; do
    IFS=: read -r type vmid name <<< "$target"
    create_snapshot "$type" "$vmid" "$name"
    cleanup_snapshots "$type" "$vmid" "$name"
done

# Resultado final
echo ""
log "=== Resultado ==="
log "Sucesso: ${#SUCCESS[@]} | Erros: ${#ERRORS[@]}"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    log "ERROS:"
    for err in "${ERRORS[@]}"; do
        log "  - $err"
    done
    exit 1
fi

log "Todos os snapshots criados com sucesso!"
exit 0
