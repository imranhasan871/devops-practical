#!/usr/bin/env bash
# deploy.sh - zero-downtime rolling deploy for docker compose environments
# usage: IMAGE_TAG=ghcr.io/org/repo:sha-abc ./scripts/deploy.sh
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG env var is required}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/devops-practical/infra}"
HEALTH_URL="${HEALTH_URL:-http://localhost/healthz}"
MAX_RETRIES=20
RETRY_DELAY=3

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "deploying image: $IMAGE_TAG"

# log in to ghcr.io if credentials are available
ENV_FILE="/opt/devops-practical/.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
  log "authenticated with ghcr.io"
fi

cd "$COMPOSE_DIR"

# record the currently running image so we can roll back if the new one fails
PREVIOUS_IMAGE_TAG=$(docker compose ps --format json app 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['Image'] if isinstance(d,list) else d['Image'])" \
  2>/dev/null || echo "")
log "previous image: ${PREVIOUS_IMAGE_TAG:-unknown}"

# pull new image so the actual restart is instant
log "pulling image..."
docker pull "$IMAGE_TAG"

# write the pinned tag into the compose override so the correct image is used
cat > "$COMPOSE_DIR/docker-compose.override.yml" <<EOF
version: "3.9"
services:
  app:
    image: ${IMAGE_TAG}
EOF

log "starting new containers..."
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --no-deps --remove-orphans app

# wait for the new instance to pass its health check
log "waiting for health check at $HEALTH_URL..."
for i in $(seq 1 $MAX_RETRIES); do
  http_status=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")

  if [[ "$http_status" == "200" ]]; then
    log "health check passed (attempt $i)"
    break
  fi

  if [[ $i -eq $MAX_RETRIES ]]; then
    log "ERROR: health check failed after $MAX_RETRIES attempts (last status: $http_status)"
    if [[ -n "${PREVIOUS_IMAGE_TAG:-}" ]]; then
      log "rolling back to $PREVIOUS_IMAGE_TAG..."
      IMAGE_TAG="$PREVIOUS_IMAGE_TAG" docker compose up -d --no-deps app
    else
      log "no previous image recorded - cannot roll back automatically"
    fi
    exit 1
  fi

  log "attempt $i/$MAX_RETRIES: status $http_status, retrying in ${RETRY_DELAY}s..."
  sleep "$RETRY_DELAY"
done

log "deploy complete"
docker compose ps
