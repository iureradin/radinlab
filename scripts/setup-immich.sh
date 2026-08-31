#!/usr/bin/env bash
# ---
# setup-immich.sh
# Deploy Immich Photo Management via Docker Compose
# Usa o docker-compose.yml oficial do release do Immich
# ---
set -euo pipefail

# --- Configuração
IMMICH_VERSION="${IMMICH_VERSION:-v3}"
DB_PASSWORD="${DB_PASSWORD:-immich_db_pass}"
DB_USERNAME="${DB_USERNAME:-immich}"
DB_DATABASE_NAME="${DB_DATABASE_NAME:-immich}"
UPLOAD_LOCATION="${UPLOAD_LOCATION:-/var/lib/immich/upload}"
DB_DATA_LOCATION="${DB_DATA_LOCATION:-/var/lib/immich/pgdata}"
IMMICH_DIR="/opt/immich"
PHOTOS_PATH="${PHOTOS_PATH:-/mnt/hd1tb/iure/fotos}"

echo "=== Deploying Immich ${IMMICH_VERSION} ==="

# --- Diretórios
mkdir -p "${IMMICH_DIR}"
mkdir -p "${UPLOAD_LOCATION}"
mkdir -p "${DB_DATA_LOCATION}"

# --- Baixa o docker-compose.yml oficial do release
echo "Baixando docker-compose.yml oficial do Immich ${IMMICH_VERSION}..."

# Resolve a tag de release para buscar o compose correto
RELEASE_TAG=$(curl -s https://api.github.com/repos/immich-app/immich/releases/latest | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
echo "Release encontrado: ${RELEASE_TAG}"

curl -fsSL "https://github.com/immich-app/immich/releases/download/${RELEASE_TAG}/docker-compose.yml" \
  -o "${IMMICH_DIR}/docker-compose.yml"

# --- Cria .env
cat > "${IMMICH_DIR}/.env" <<EOF
# Gerado por setup-immich.sh em $(date '+%d/%m/%Y %H:%M')
UPLOAD_LOCATION=${UPLOAD_LOCATION}
DB_DATA_LOCATION=${DB_DATA_LOCATION}
IMMICH_VERSION=${IMMICH_VERSION}
DB_PASSWORD=${DB_PASSWORD}
DB_USERNAME=${DB_USERNAME}
DB_DATABASE_NAME=${DB_DATABASE_NAME}
EOF

# --- Adiciona mount das fotos existentes no compose
# Monta /mnt/fotos (bind mount do CT) como /mnt/hd1tb/iure/fotos dentro do container
if ! grep -q "hd1tb" "${IMMICH_DIR}/docker-compose.yml"; then
  sed -i "s|- /etc/localtime:/etc/localtime:ro|- /etc/localtime:/etc/localtime:ro\n      - /mnt/fotos:${PHOTOS_PATH}:ro|" \
    "${IMMICH_DIR}/docker-compose.yml"
fi

# --- Pull e sobe a stack
cd "${IMMICH_DIR}"
echo "Baixando imagens..."
docker compose pull

echo "Subindo containers..."
docker compose up -d

# --- Aguarda o servidor responder
echo "Aguardando Immich inicializar..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:2283/api/server/ping &>/dev/null; then
    echo "✓ Immich respondendo após $((i * 5))s"
    break
  fi
  sleep 5
done

# --- Status final
echo ""
docker compose ps
echo ""
echo "=== Deploy concluído ==="
echo "Acesse: http://$(hostname -I | awk '{print $1}'):2283"
echo "Upload: ${UPLOAD_LOCATION}"
echo "Fotos existentes: ${PHOTOS_PATH} (read-only)"
