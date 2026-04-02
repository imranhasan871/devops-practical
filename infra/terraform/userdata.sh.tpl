#!/bin/bash
# Droplet bootstrap script - runs once on first boot as root.
# Ubuntu 22.04 LTS base image.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ---- system update ----
apt-get update -q
apt-get upgrade -yq

# ---- install docker ----
apt-get install -yq ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu jammy stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -q
apt-get install -yq docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable --now docker

# ---- authenticate with GitHub Container Registry ----
echo "${ghcr_token}" | docker login ghcr.io -u "${ghcr_user}" --password-stdin

# ---- deploy the application stack ----
mkdir -p /opt/devops-practical/infra
cd /opt/devops-practical/infra

cat > docker-compose.yml <<COMPOSE
version: "3.9"
services:
  app:
    image: ${app_image}
    restart: unless-stopped
    environment:
      PORT: "8080"
      ENV: production
    expose:
      - "8080"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/healthz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s

  nginx:
    image: ${nginx_image}
    restart: unless-stopped
    ports:
      - "80:80"
    depends_on:
      app:
        condition: service_healthy
COMPOSE

docker compose pull
docker compose up -d

# persist credentials so future deploy.sh runs can also pull
mkdir -p /opt/devops-practical/infra
cat > /opt/devops-practical/.env <<ENV
GHCR_TOKEN=${ghcr_token}
GHCR_USER=${ghcr_user}
ENV

echo "bootstrap complete"
