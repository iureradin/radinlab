#!/bin/bash
# daily_snapshot.sh
# Cria snapshots diários de containers/VMs com tag 'daily_snapshot'
# Mantém no máximo 3 snapshots por VM/container
# CT 109 (jellyfin): trata bind mounts removendo-os temporariamente para
# permitir snapshot via pct, com restore garantido via trap.
# Após snapshot do jellyfin, executa testes obrigatórios.

set -uo pipefail

SNAPSHOT_TAG="daily_snapshot"
MAX_SNAPSHOTS=3
SNAPSHOT_NAME="auto_$(date +%d%m%Y_%H%M)"
ERRORS=()
SUCCESS=()

# Telegram
TELEGRAM_BOT_TOKEN="8846315620:AAEPbRUFRIK6tOSI5HwtHjNEIJ_oHAglznM"
TELEGRAM_CHAT_ID="620923420"

# Jellyfin - configurações para tratamento especial
JELLYFIN_CTID=109
JELLYFIN_USER="jellyfin"

log() {
    echo "[$(date '+%d/%m/%Y %H:%M:%S')] $1"
}

telegram_alert() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        > /dev/null 2>&1 || true
}

# Testes pós-snapshot do jellyfin
jellyfin_post_snapshot_tests() {
    local vmid="$1"
    local test_errors=()

    log "Executando testes pós-snapshot do jellyfin (CT $vmid)..."

    # Teste 1: serviço jellyfin rodando
    if pct exec "$vmid" -- systemctl is-active jellyfin > /dev/null 2>&1; then
        log "  ✓ Serviço jellyfin: rodando"
    else
        log "  ✗ Serviço jellyfin: PARADO"
        test_errors+=("jellyfin service is down")
    fi

    # Teste 2: processo jellyfin existe
    if pct exec "$vmid" -- pgrep -u "$JELLYFIN_USER" jellyfin > /dev/null 2>&1; then
        log "  ✓ Processo jellyfin: ativo (user: $JELLYFIN_USER)"
    else
        log "  ✗ Processo jellyfin: não encontrado para user $JELLYFIN_USER"
        test_errors+=("jellyfin process not running as $JELLYFIN_USER")
    fi

    # Teste 3: leitura/escrita nos discos pelo user jellyfin
    local test_file=".snapshot_test_$$"
    for mp in "/mnt/hd4tb" "/mnt/hd1tb" "/mnt/ssd500gb"; do
        # Teste de leitura
        if pct exec "$vmid" -- su -s /bin/sh "$JELLYFIN_USER" -c "ls '$mp' > /dev/null 2>&1"; then
            log "  ✓ Leitura em $mp: OK"
        else
            log "  ✗ Leitura em $mp: FALHOU"
            test_errors+=("read failed on $mp")
        fi

        # Teste de escrita
        if pct exec "$vmid" -- su -s /bin/sh "$JELLYFIN_USER" -c "touch '$mp/$test_file' 2>/dev/null && rm -f '$mp/$test_file' 2>/dev/null"; then
            log "  ✓ Escrita em $mp: OK"
        else
            log "  ✗ Escrita em $mp: FALHOU (pode ser permissão — verificar manualmente)"
            # Escrita pode falhar por design (somente leitura), não é crítico
        fi
    done

    # Teste 4: porta HTTP do jellyfin respondendo
    if pct exec "$vmid" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8096/health 2>/dev/null | grep -q "200\|301\|302"; then
        log "  ✓ HTTP jellyfin (porta 8096): respondendo"
    else
        log "  ⚠ HTTP jellyfin (porta 8096): sem resposta (pode estar iniciando)"
    fi

    if [[ ${#test_errors[@]} -gt 0 ]]; then
        for err in "${test_errors[@]}"; do
            ERRORS+=("ct $vmid (jellyfin) post-test: $err")
        done
        log "  ✗ Testes pós-snapshot: ${#test_errors[@]} falha(s)"
        return 1
    fi

    log "  ✓ Todos os testes pós-snapshot passaram"
    return 0
}

# Snapshot especial para jellyfin (edita config diretamente para remover bind mounts e dev,
# faz snapshot com container parado, restaura config e reinicia)
create_snapshot_jellyfin() {
    local vmid="$1" name="$2"
    local conf_file="/etc/pve/lxc/${vmid}.conf"
    local conf_backup="/tmp/pve_lxc_${vmid}_backup_$$.conf"

    log "Iniciando snapshot especial para jellyfin (CT $vmid)..."

    # Backup da config original
    cp "$conf_file" "$conf_backup"

    # Garante restore da config e reinício do container em qualquer saída
    trap "
        log 'Restaurando config do jellyfin via trap (emergência)...'
        cp '$conf_backup' '$conf_file'
        pct start $vmid 2>/dev/null || true
        rm -f '$conf_backup'
    " EXIT INT TERM

    # Para o container
    log "  Parando container..."
    if ! pct stop "$vmid" 2>&1; then
        log "✗ ERRO ao parar ct $vmid ($name)"
        ERRORS+=("ct $vmid ($name): falha ao parar container")
        trap - EXIT INT TERM
        rm -f "$conf_backup"
        pct start "$vmid" 2>/dev/null
        return 1
    fi

    # Aguarda parada completa
    local tries=0
    while pct status "$vmid" 2>/dev/null | grep -q "running"; do
        sleep 2
        (( tries++ ))
        if [[ "$tries" -gt 10 ]]; then
            log "✗ Timeout aguardando parada do ct $vmid"
            ERRORS+=("ct $vmid ($name): timeout ao parar")
            cp "$conf_backup" "$conf_file"
            pct start "$vmid" 2>/dev/null
            trap - EXIT INT TERM
            rm -f "$conf_backup"
            return 1
        fi
    done
    log "  Container parado."

    # Remove mp e dev da config diretamente (sem pct set para evitar pending)
    log "  Removendo bind mounts e device passthrough da config..."
    grep -v -E '^(mp[0-9]+|dev[0-9]+):' "$conf_file" > "${conf_file}.tmp" && mv "${conf_file}.tmp" "$conf_file"

    # Cria snapshot
    local output
    if output=$(pct snapshot "$vmid" "$SNAPSHOT_NAME" --description "Auto snapshot $(date '+%d/%m/%Y %H:%M')" 2>&1); then
        log "✓ Snapshot criado: ct $vmid ($name)"
        SUCCESS+=("ct $vmid ($name)")
    else
        log "✗ ERRO ao criar snapshot: ct $vmid ($name) — $output"
        ERRORS+=("ct $vmid ($name): $output")
    fi

    # Restaura config original antes de reiniciar, preservando seções de snapshot
    # que o pct snapshot gravou no arquivo durante a operação
    log "  Restaurando config original (preservando metadados de snapshot)..."

    # Extrai seções de snapshot geradas pelo pct snapshot (linhas [snapname] e posteriores)
    local snap_sections
    snap_sections=$(awk '/^\[/{found=1} found{print}' "$conf_file" 2>/dev/null || true)

    # Restaura config original (sem seções de snapshot)
    grep -v '^\[' "$conf_backup" > "$conf_file" || cp "$conf_backup" "$conf_file"

    # Adiciona parent e snaptime da config atual (gerados pelo pct snapshot)
    local parent_line snaptime_line
    parent_line=$(grep '^parent:' "$conf_file.pre_restore" 2>/dev/null || grep '^parent:' "$conf_file" 2>/dev/null || true)

    # Re-anexa as seções de snapshot preservadas
    if [[ -n "$snap_sections" ]]; then
        echo "" >> "$conf_file"
        echo "$snap_sections" >> "$conf_file"
        log "  Metadados de snapshot preservados."
    fi

    rm -f "$conf_backup"

    # Reinicia container
    log "  Reiniciando container..."
    if ! pct start "$vmid" 2>&1; then
        log "✗ ERRO CRÍTICO: falha ao reiniciar ct $vmid ($name)!"
        ERRORS+=("ct $vmid ($name): CRITICO - falha ao reiniciar")
        telegram_alert "[RadinLab] CRITICO: jellyfin (CT $vmid) NAO reiniciou apos snapshot! Verifique imediatamente."
        trap - EXIT INT TERM
        return 1
    fi

    trap - EXIT INT TERM
    log "  Container reiniciado."

    # Aguarda serviço estabilizar
    log "  Aguardando 15s para o jellyfin estabilizar..."
    sleep 15

    # Executa testes pós-snapshot
    jellyfin_post_snapshot_tests "$vmid"
}

# Busca containers LXC com a tag daily_snapshot
get_tagged_cts() {
    pct list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r vmid; do
        local tags name
        name=$(pct config "$vmid" 2>/dev/null | grep -oP '^hostname:\s*\K.*' || echo "$vmid")
        tags=$(pct config "$vmid" 2>/dev/null | grep -oP '^tags:\s*\K.*' || true)
        if echo "$tags" | grep -qw "$SNAPSHOT_TAG"; then
            echo "ct:$vmid:$name"
        fi
    done
}

# Busca VMs QEMU com a tag daily_snapshot
get_tagged_vms() {
    qm list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r vmid; do
        local tags name
        name=$(qm config "$vmid" 2>/dev/null | grep -oP '^name:\s*\K.*' || echo "$vmid")
        tags=$(qm config "$vmid" 2>/dev/null | grep -oP '^tags:\s*\K.*' || true)
        if echo "$tags" | grep -qw "$SNAPSHOT_TAG"; then
            echo "vm:$vmid:$name"
        fi
    done
}

# Cria snapshot padrão
create_snapshot() {
    local type="$1" vmid="$2" name="$3"

    # Jellyfin tem tratamento especial
    if [[ "$type" == "ct" && "$vmid" == "$JELLYFIN_CTID" ]]; then
        create_snapshot_jellyfin "$vmid" "$name"
        return
    fi

    log "Criando snapshot '$SNAPSHOT_NAME' para $type $vmid ($name)..."

    local output
    if [[ "$type" == "ct" ]]; then
        if output=$(pct snapshot "$vmid" "$SNAPSHOT_NAME" --description "Auto snapshot $(date '+%d/%m/%Y %H:%M')" 2>&1); then
            log "✓ Snapshot criado: $type $vmid ($name)"
            SUCCESS+=("$type $vmid ($name)")
        else
            log "✗ ERRO ao criar snapshot: $type $vmid ($name) — $output"
            ERRORS+=("$type $vmid ($name): $output")
        fi
    elif [[ "$type" == "vm" ]]; then
        if output=$(qm snapshot "$vmid" "$SNAPSHOT_NAME" --description "Auto snapshot $(date '+%d/%m/%Y %H:%M')" 2>&1); then
            log "✓ Snapshot criado: $type $vmid ($name)"
            SUCCESS+=("$type $vmid ($name)")
        else
            log "✗ ERRO ao criar snapshot: $type $vmid ($name) — $output"
            ERRORS+=("$type $vmid ($name): $output")
        fi
    fi
}

# Remove snapshots antigos (mantém apenas MAX_SNAPSHOTS)
cleanup_snapshots() {
    local type="$1" vmid="$2" name="$3"

    log "Verificando snapshots antigos de $type $vmid ($name)..."

    local snapshots
    if [[ "$type" == "ct" ]]; then
        snapshots=$(pct listsnapshot "$vmid" 2>/dev/null | grep -oP '^\s*\`->\s*\K(auto_\S+)|^\s*\K(auto_\S+)' | sort || true)
    elif [[ "$type" == "vm" ]]; then
        snapshots=$(qm listsnapshot "$vmid" 2>/dev/null | grep -oP '^\s*\`->\s*\K(auto_\S+)|^\s*\K(auto_\S+)' | sort || true)
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
                pct delsnapshot "$vmid" "$snap" 2>/dev/null || ERRORS+=("$type $vmid ($name): falha ao remover $snap")
            elif [[ "$type" == "vm" ]]; then
                qm delsnapshot "$vmid" "$snap" 2>/dev/null || ERRORS+=("$type $vmid ($name): falha ao remover $snap")
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

    ERROR_LIST=""
    for err in "${ERRORS[@]}"; do
        ERROR_LIST="${ERROR_LIST}- ${err}\n"
    done

    telegram_alert "[RadinLab] Snapshot com erros

Sucesso: ${#SUCCESS[@]} | Erros: ${#ERRORS[@]}
Data: $(date '+%d/%m/%Y %H:%M')

Erros:
${ERROR_LIST}"

    exit 1
fi

log "Todos os snapshots criados com sucesso!"
exit 0
