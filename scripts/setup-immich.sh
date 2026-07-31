#!/usr/bin/env bash
# ---
# setup-immich.sh
# Deploy Immich Photo Management via Docker Compose
# ---
set -euo pipefail

# --- Configuration
IMMICH_VERSION="${IMMICH_VERSION:-release}"
DB_PASSWORD="${DB_PASSWORD:-immich_db_password_change_me}"
UPLOAD_LOCATION="${UPLOAD_LOCATION:-/mnt/photos}"
IMMICH_DIR="/opt/immich"

echo "=== Deploying Immich ${IMMICH_VERSION} ==="

# --- Create directories
mkdir -p "${IMMICH_DIR}"
mkdir -p "${UPLOAD_LOCATION}"
mkdir -p "${IMMICH_DIR}/db"

# --- Create .env file
cat > "${IMMICH_DIR}/.env" <<EOF
# ---
# Immich Environment Configuration
# ---

# Version
IMMICH_VERSION=${IMMICH_VERSION}

# Database
DB_PASSWORD=${DB_PASSWORD}
DB_USERNAME=postgres
DB_DATABASE_NAME=immich

# Upload location
UPLOAD_LOCATION=${UPLOAD_LOCATION}

# Machine Learning
IMMICH_MACHINE_LEARNING_URL=http://immich-machine-learning:3003
EOF

# --- Create Docker Compose file
cat > "${IMMICH_DIR}/docker-compose.yml" <<'COMPOSE'
# ---
# Immich Docker Compose
# https://immich.app
# ---

name: immich

services:
  # --- Immich Server
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    volumes:
      - ${UPLOAD_LOCATION:-/mnt/photos}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports:
      - "2283:2283"
    depends_on:
      - redis
      - database
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:2283/api/server/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # --- Machine Learning
  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    volumes:
      - model-cache:/cache
    env_file:
      - .env
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python3", "-c", "import requests; requests.get('http://localhost:3003/ping')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s

  # --- Redis
  redis:
    container_name: immich_redis
    image: docker.io/redis:6.2-alpine
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # --- PostgreSQL with pgvecto.rs
  database:
    container_name: immich_postgres
    image: docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME:-postgres}
      POSTGRES_DB: ${DB_DATABASE_NAME:-immich}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - ${IMMICH_DIR:-/opt/immich}/db:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready --dbname='${DB_DATABASE_NAME}' --username='${DB_USERNAME}'"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  model-cache:
COMPOSE

# --- Pull and start containers
cd "${IMMICH_DIR}"
docker compose pull
docker compose up -d

# --- Wait for startup
echo "Waiting for Immich to start..."
sleep 15

# --- Check status
docker compose ps

echo ""
echo "=== Immich deployment complete ==="
echo "Access Immich at: http://<container-ip>:2283"
echo "Upload location: ${UPLOAD_LOCATION}"
echo ""
