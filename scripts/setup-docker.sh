#!/usr/bin/env bash
# ---
# setup-docker.sh
# Install Docker CE and Docker Compose on Ubuntu 22.04 LXC
# ---
set -euo pipefail

echo "=== Installing Docker CE on Ubuntu 22.04 ==="

# --- Update system packages
apt-get update -y
apt-get upgrade -y

# --- Install prerequisites
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apt-transport-https \
  software-properties-common

# --- Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --no-tty --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# --- Set up the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# --- Install Docker CE
apt-get update -y
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# --- Enable and start Docker
systemctl enable docker
systemctl start docker

# --- Verify installation
docker --version
docker compose version

echo "=== Docker CE installation complete ==="
