#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export ENV_FILE="${PROJECT_DIR}/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERRO: .env não encontrado. Execute: cp .env.example .env && edite o arquivo"
  exit 1
fi
set -a; source "$ENV_FILE"; set +a

echo "=== Fase 7: Configurar SSO ==="

echo "[7.1] Obtendo token admin..."
ADMIN_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${KEYCLOAK_ADMIN}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "Token obtido: ${ADMIN_TOKEN:0:20}..."

echo "[7.2] Criando realm ${KEYCLOAK_REALM}..."
curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"realm\": \"${KEYCLOAK_REALM}\",
    \"enabled\": true,
    \"loginWithEmailAllowed\": true,
    \"registrationAllowed\": false
  }" > /dev/null
echo "Realm ${KEYCLOAK_REALM} criado."

echo ""
echo "[7.3] Criando client litellm..."
LITELLM_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"clientId\": \"litellm\",
    \"name\": \"LiteLLM\",
    \"enabled\": true,
    \"publicClient\": false,
    \"standardFlowEnabled\": true,
    \"directAccessGrantsEnabled\": true,
    \"redirectUris\": [\"http://localhost:30081/sso/callback\", \"http://localhost:30081/*\"],
    \"webOrigins\": [\"+\"],
    \"protocol\": \"openid-connect\"
  }")

LITELLM_CLIENT_UUID=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=litellm" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

LITELLM_SECRET=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${LITELLM_CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])")

echo "Client litellm criado. Secret: ${LITELLM_SECRET}"

echo ""
echo "[7.4] Criando client langfuse..."
LANGUSE_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"clientId\": \"langfuse\",
    \"name\": \"Langfuse\",
    \"enabled\": true,
    \"publicClient\": false,
    \"standardFlowEnabled\": true,
    \"directAccessGrantsEnabled\": true,
    \"redirectUris\": [\"http://localhost:30082/api/auth/callback/keycloak\"],
    \"webOrigins\": [\"+\"],
    \"protocol\": \"openid-connect\"
  }")

LANGUSE_CLIENT_UUID=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=langfuse" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

LANGUSE_SECRET=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${LANGUSE_CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])")

echo "Client langfuse criado. Secret: ${LANGUSE_SECRET}"

echo ""
echo "[7.5] Criando usuario de teste..."
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${SSO_TEST_USER}\",
    \"email\": \"${SSO_TEST_USER}@predioazul.com\",
    \"firstName\": \"Test\",
    \"lastName\": \"User\",
    \"enabled\": true,
    \"credentials\": [{
      \"type\": \"password\",
      \"value\": \"${SSO_TEST_PASSWORD}\",
      \"temporary\": false
    }]
  }" > /dev/null
echo "Usuario ${SSO_TEST_USER}/${SSO_TEST_PASSWORD} criado."

echo ""
echo "============================================="
echo " SSO configurado!"
echo "============================================="
echo " Realm:     ${KEYCLOAK_REALM}"
echo " Usuario:   ${SSO_TEST_USER} / ${SSO_TEST_PASSWORD}"
echo " LiteLLM:   client_id=litellm  secret=${LITELLM_SECRET}"
echo " Langfuse:  client_id=langfuse secret=${LANGUSE_SECRET}"
echo "============================================="

echo ""
echo "[7.6] Atualizando .env com client secrets..."
if [ -f "$ENV_FILE" ]; then
  if grep -q "LITELLM_GENERIC_CLIENT_SECRET" "$ENV_FILE"; then
    sed -i "s/^LITELLM_GENERIC_CLIENT_SECRET=.*/LITELLM_GENERIC_CLIENT_SECRET=${LITELLM_SECRET}/" "$ENV_FILE"
  else
    echo "LITELLM_GENERIC_CLIENT_SECRET=${LITELLM_SECRET}" >> "$ENV_FILE"
  fi
  if grep -q "LANGFUSE_KEYCLOAK_CLIENT_SECRET" "$ENV_FILE"; then
    sed -i "s/^LANGFUSE_KEYCLOAK_CLIENT_SECRET=.*/LANGFUSE_KEYCLOAK_CLIENT_SECRET=${LANGUSE_SECRET}/" "$ENV_FILE"
  else
    echo "LANGFUSE_KEYCLOAK_CLIENT_SECRET=${LANGUSE_SECRET}" >> "$ENV_FILE"
  fi
  echo ".env atualizado."
fi

echo ""
echo "[7.7] Re-renderizando valores e redeploy..."
render_template() {
  local template="$1"
  local output="${template%.template}"
  envsubst < "$template" > "$output"
}
render_template "${PROJECT_DIR}/values/litellm.yaml.template"
render_template "${PROJECT_DIR}/values/langfuse.yaml.template"

microk8s helm3 upgrade litellm /tmp/litellm-chart/deploy/charts/litellm-helm \
  -f "${PROJECT_DIR}/values/litellm.yaml" \
  -n litellm \
  --timeout 5m 2>/dev/null || true

microk8s helm3 upgrade langfuse langfuse/langfuse \
  -f "${PROJECT_DIR}/values/langfuse.yaml" \
  -n langfuse \
  --timeout 10m 2>/dev/null || true

echo ""
echo "Aguardando pods reiniciarem..."
microk8s kubectl rollout restart deployment/litellm -n litellm 2>/dev/null || true
microk8s kubectl rollout restart deployment/langfuse-web -n langfuse 2>/dev/null || true
microk8s kubectl rollout restart deployment/langfuse-worker -n langfuse 2>/dev/null || true

sleep 15
microk8s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=litellm -n litellm --timeout=120s 2>/dev/null || true
microk8s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=langfuse -n langfuse --timeout=120s 2>/dev/null || true

# Reapply NodePorts
microk8s kubectl patch svc litellm -n litellm \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":4000,"targetPort":"http","nodePort":30081}]}}' \
  2>/dev/null || true
microk8s kubectl patch svc langfuse-web -n langfuse \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":3000,"targetPort":3000,"nodePort":30082}]}}' \
  2>/dev/null || true

echo ""
echo "=== Fase 7 concluida ==="
echo ""
echo "Testar no browser:"
echo "  LiteLLM:  http://localhost:30081  (clicar 'Sign in with SSO')"
echo "  Langfuse: http://localhost:30082  (clicar 'Sign in with Keycloak')"
echo "  Usuario:  ${SSO_TEST_USER} / ${SSO_TEST_PASSWORD}"
