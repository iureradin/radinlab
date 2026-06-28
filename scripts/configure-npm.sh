#!/bin/bash
set -euo pipefail

NPM_URL="${NPM_URL:-http://localhost:81}"
NPM_EMAIL="${NPM_EMAIL:?NPM_EMAIL not set}"
NPM_PASSWORD="${NPM_PASSWORD:?NPM_PASSWORD not set}"
LE_EMAIL="${LE_EMAIL:-$NPM_EMAIL}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set}"

# Login
TOKEN=$(curl -sf "$NPM_URL/api/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASSWORD\"}" | jq -r '.token')

echo "Authenticated with NPM"

# Request wildcard SSL cert via DNS challenge (Route 53)
EXISTING_CERTS=$(curl -sf "$NPM_URL/api/nginx/certificates" \
  -H "Authorization: Bearer $TOKEN")

CERT_ID=$(echo "$EXISTING_CERTS" | jq -r '.[] | select(.domain_names[] == "*.radinlab.com.br") | .id' | head -1)

if [ -z "$CERT_ID" ] || [ "$CERT_ID" = "null" ]; then
  echo "Requesting wildcard certificate for *.radinlab.com.br..."
  CERT_RESPONSE=$(curl -s "$NPM_URL/api/nginx/certificates" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"provider\": \"letsencrypt\",
      \"domain_names\": [\"*.radinlab.com.br\", \"radinlab.com.br\"],
      \"meta\": {
        \"letsencrypt_email\": \"$LE_EMAIL\",
        \"letsencrypt_agree\": true,
        \"dns_challenge\": true,
        \"dns_provider\": \"route53\",
        \"dns_provider_credentials\": \"dns_route53_aws_access_key_id=$AWS_ACCESS_KEY_ID\\ndns_route53_aws_secret_access_key=$AWS_SECRET_ACCESS_KEY\"
      }
    }")
  echo "Certificate response: $CERT_RESPONSE"
  CERT_ID=$(echo "$CERT_RESPONSE" | jq -r '.id')
  if [ -z "$CERT_ID" ] || [ "$CERT_ID" = "null" ]; then
    echo "ERROR: Failed to create certificate"
    exit 1
  fi
  echo "Certificate created (ID: $CERT_ID)"
else
  echo "Wildcard certificate already exists (ID: $CERT_ID)"
fi

# Proxy hosts: domain|host|port
HOSTS=(
  "grafana.radinlab.com.br|grafana|3000"
  "auth.radinlab.com.br|authentik-server|9000"
)

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
      \"certificate_id\": $CERT_ID,
      \"block_exploits\": true
    }" > /dev/null

  echo "$domain ✓"
done

echo "NPM configuration complete"
