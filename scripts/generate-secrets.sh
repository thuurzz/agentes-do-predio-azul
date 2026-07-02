#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${PROJECT_DIR}/.env"
ENV_EXAMPLE="${PROJECT_DIR}/.env.example"

echo "=== Gerando .env ==="

if [ -f "$ENV_FILE" ]; then
  echo "AVISO: .env já existe."
  read -p "Sobrescrever? (s/N) " confirm
  if [ "${confirm,,}" != "s" ]; then
    echo "Abortado."
    exit 0
  fi
fi

# Gerar valores aleatórios
PG_PASSWORD=$(openssl rand -base64 24)
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 12)
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 16)"
LANGFUSE_SALT=$(openssl rand -hex 32)
LANGFUSE_NEXTAUTH_SECRET=$(openssl rand -hex 32)
LANGFUSE_CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
LANGFUSE_S3_ROOT_PASSWORD=$(openssl rand -hex 12)

# Perguntar valores que o usuário precisa definir
echo ""
read -p "Node IP [192.168.1.10]: " NODE_IP
NODE_IP="${NODE_IP:-192.168.1.10}"

KEYCLOAK_URL="http://${NODE_IP}:30080"
KEYCLOAK_HOSTNAME_URL="${KEYCLOAK_URL}"

read -p "SSO test user [tester]: " SSO_TEST_USER
SSO_TEST_USER="${SSO_TEST_USER:-tester}"

read -p "SSO test password [test123]: " SSO_TEST_PASSWORD
SSO_TEST_PASSWORD="${SSO_TEST_PASSWORD:-test123}"

echo ""
echo "Gerando .env ..."

cat > "$ENV_FILE" << EOF
# =============================================
# Agentes do Prédio Azul — Environment Config
# =============================================
# Gerado por scripts/generate-secrets.sh
# $(date)

# --- Host/Network ---
NODE_IP=${NODE_IP}
KEYCLOAK_URL=${KEYCLOAK_URL}

# --- PostgreSQL ---
PG_USER=litellm
PG_PASSWORD=${PG_PASSWORD}
PG_HOST=postgresql.infrastructure.svc.cluster.local
PG_PORT=5432

# --- Keycloak ---
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
KEYCLOAK_REALM=lab-agentes
KEYCLOAK_HOSTNAME_URL=${KEYCLOAK_HOSTNAME_URL}

# --- LiteLLM ---
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_GENERIC_CLIENT_SECRET=<preenchido pelo 07-configure-sso.sh>

# --- Langfuse ---
LANGFUSE_SALT=${LANGFUSE_SALT}
LANGFUSE_NEXTAUTH_SECRET=${LANGFUSE_NEXTAUTH_SECRET}
LANGFUSE_CLICKHOUSE_PASSWORD=${LANGFUSE_CLICKHOUSE_PASSWORD}
LANGFUSE_S3_ROOT_PASSWORD=${LANGFUSE_S3_ROOT_PASSWORD}
LANGFUSE_KEYCLOAK_CLIENT_SECRET=<preenchido pelo 07-configure-sso.sh>
LANGFUSE_PUBLIC_KEY=<criar API key no Langfuse UI apos deploy>
LANGFUSE_SECRET_KEY=<criar API key no Langfuse UI apos deploy>

# --- SSO Test User ---
SSO_TEST_USER=${SSO_TEST_USER}
SSO_TEST_PASSWORD=${SSO_TEST_PASSWORD}
EOF

echo ""
echo "============================================="
echo " .env gerado com sucesso!"
echo "============================================="
echo " Node IP:      ${NODE_IP}"
echo " Keycloak:     ${KEYCLOAK_URL}"
echo " PG password:  ${PG_PASSWORD}"
echo " Keycloak adm: ${KEYCLOAK_ADMIN_PASSWORD}"
echo " LiteLLM key:  ${LITELLM_MASTER_KEY}"
echo " SSO user:     ${SSO_TEST_USER} / ${SSO_TEST_PASSWORD}"
echo "============================================="
echo ""
echo "Proximos passos:"
echo "  1. Rodar 07-configure-sso.sh (preenche client secrets)"
echo "  2. Apos Langfuse subir, criar API key e preencher no .env"
echo "  3. Rodar scripts de deploy na ordem"
