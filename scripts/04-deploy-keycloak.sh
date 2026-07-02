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

render_template() {
  local template="$1"
  local output="${template%.template}"
  envsubst < "$template" > "$output"
}

echo "=== Fase 4: Keycloak ==="

echo "Renderizando valores..."
render_template "${PROJECT_DIR}/values/keycloak.yaml.template"

microk8s helm3 repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true
microk8s helm3 repo update

microk8s helm3 upgrade --install keycloak bitnami/keycloak \
  -f "${PROJECT_DIR}/values/keycloak.yaml" \
  -n infrastructure \
  --wait \
  --timeout 15m

echo ""
echo "Verificando pods..."
microk8s kubectl get pods -n infrastructure -l app.kubernetes.io/name=keycloak

echo ""
echo "Aguardando pod ficar pronto..."
microk8s kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=keycloak \
  -n infrastructure \
  --timeout=600s

echo ""
echo "Keycloak disponivel em ${KEYCLOAK_URL}"
echo "Admin: ${KEYCLOAK_ADMIN}"

echo "=== Fase 4 concluida ==="
