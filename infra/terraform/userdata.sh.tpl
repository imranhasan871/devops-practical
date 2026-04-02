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
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -q
apt-get install -yq docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable --now docker

# ---- install doctl (used to authenticate with DO Container Registry) ----
curl -sL https://github.com/digitalocean/doctl/releases/latest/download/doctl-$(curl -s https://api.github.com/repos/digitalocean/doctl/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d 'v')-linux-amd64.tar.gz \
  | tar xz -C /usr/local/bin doctl

# ---- authenticate with DigitalOcean Container Registry ----
doctl auth init --access-token "${do_token}"
doctl registry login --expiry-seconds 0   # non-expiring credentials on the Droplet

# ---- start the application ----
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
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/healthz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s
COMPOSE

docker compose pull
docker compose up -d

echo "bootstrap complete"
