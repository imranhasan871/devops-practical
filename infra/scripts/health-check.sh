#!/usr/bin/env bash
# health-check.sh - quick smoke test for the running stack
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost}"
PASS=0
FAIL=0

check() {
  local name="$1"
  local url="$2"
  local expected_status="$3"
  local body_contains="${4:-}"

  response=$(curl -s -o /tmp/hc_body -w "%{http_code}" "$url")

  if [[ "$response" != "$expected_status" ]]; then
    echo "FAIL  $name → expected $expected_status, got $response"
    FAIL=$((FAIL+1))
    return
  fi

  if [[ -n "$body_contains" ]] && ! grep -q "$body_contains" /tmp/hc_body; then
    echo "FAIL  $name → body missing '$body_contains'"
    cat /tmp/hc_body
    FAIL=$((FAIL+1))
    return
  fi

  echo "PASS  $name"
  PASS=$((PASS+1))
}

echo "=== smoke tests against $BASE_URL ==="

check "liveness probe"   "$BASE_URL/healthz"  "200" "alive"
check "readiness probe"  "$BASE_URL/readyz"   "200" "ready"
check "GET /status"      "$BASE_URL/status"   "200" "\"status\":\"ok\""

# POST /data
post_response=$(curl -s -o /tmp/hc_post -w "%{http_code}" \
  -X POST "$BASE_URL/data" \
  -H "Content-Type: application/json" \
  -d '{"key":"smoke-test","value":"ok"}')

if [[ "$post_response" == "201" ]]; then
  echo "PASS  POST /data"
  PASS=$((PASS+1))
else
  echo "FAIL  POST /data → expected 201, got $post_response"
  cat /tmp/hc_post
  FAIL=$((FAIL+1))
fi

check "GET /data"         "$BASE_URL/data"     "200" "\"count\""

echo ""
echo "results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
