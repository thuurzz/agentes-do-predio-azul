#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export ENV_FILE="${PROJECT_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi

KEYCLOAK_URL="${KEYCLOAK_URL:-http://192.168.1.10:30080}"
ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:-gqrbqCsi3B8PL3Jo}"
REALM="${KEYCLOAK_REALM:-lab-agentes}"
USERS="${USERS:-usuario1 usuario2 usuario3 usuario4 usuario5}"

echo "=== Criando usuarios no Keycloak ==="
echo "Realm: ${REALM}"
echo "URL:   ${KEYCLOAK_URL}"

ADMIN_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASS}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo ""

COUNT=0
for user in ${USERS}; do
  echo "Criando ${user}..."

  curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"${user}\",
      \"email\": \"${user}@predioazul.com\",
      \"firstName\": \"${user}\",
      \"lastName\": \"Agente\",
      \"enabled\": true,
      \"emailVerified\": true,
      \"credentials\": [{
        \"type\": \"password\",
        \"value\": \"Azul2024!\",
        \"temporary\": false
      }]
    }" > /dev/null

  echo "  Usuario: ${user} / Azul2024!"
  echo "  Email:   ${user}@predioazul.com"
  echo ""
  COUNT=$((COUNT + 1))
done

echo "=== ${COUNT} usuarios criados ==="
