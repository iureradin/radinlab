#!/bin/bash
set -euo pipefail

NPM_URL="${NPM_URL:-http://localhost:81}"
NPM_EMAIL="${NPM_EMAIL:?NPM_EMAIL not set}"
NPM_PASSWORD="${NPM_PASSWORD:?NPM_PASSWORD not set}"

# Login
TOKEN=$(curl -sf "$NPM_URL/api/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASSWORD\"}" | jq -r '.token')

echo "Authenticated with NPM"

# Proxy hosts config: domain|host|port
HOSTS=(
  "grafana.radinlab.com.br|grafana|3000"
  "auth.radinlab.com.br|authentik-server|9000"
)

# Get existing proxy hosts
EXISTING=$(curl -sf "$NPM_URL/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.[].domain_names[0]')

for entry in "${HOSTS[@]}"; do
  IFS='|' read -r domain host port <<< "$entry"

  if echo "$EXISTING" | grep -qx "$domain"; then
    echo "$domain already configured, skipping"
    continue
  fi

  echo "Creating proxy host: $domain -> $host:$port"
  curl -sf "$NPM_URL/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"domain_names\": [\"$domain\"],
      \"forward_scheme\": \"http\",
      \"forward_host\": \"$host\",
      \"forward_port\": $port,
      \"ssl_forced\": true,
      \"allow_websocket_upgrade\": true,
      \"meta\": {\"letsencrypt_agree\": true, \"dns_challenge\": false},
      \"certificate_id\": \"new\",
      \"advanced_config\": \"\",
      \"block_exploits\": true
    }" > /dev/null

  echo "$domain ✓"
done

echo "NPM configuration complete"
