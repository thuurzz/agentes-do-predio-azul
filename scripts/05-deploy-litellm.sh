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

echo "=== Fase 5: LiteLLM ==="

CHART_DIR="/tmp/litellm-chart"
CHART_PATH="$CHART_DIR/deploy/charts/litellm-helm"

if [ ! -d "$CHART_PATH" ]; then
  echo "Clonando chart LiteLLM..."
  git clone --depth 1 https://github.com/BerriAI/litellm.git "$CHART_DIR"
fi

echo "Renderizando valores..."
render_template "${PROJECT_DIR}/values/litellm.yaml.template"

microk8s helm3 upgrade --install litellm "$CHART_PATH" \
  -f "${PROJECT_DIR}/values/litellm.yaml" \
  -n litellm \
  --timeout 10m

echo ""
echo "Verificando pods..."
microk8s kubectl get pods -n litellm

echo ""
echo "Aguardando pod ficar pronto..."
microk8s kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=litellm \
  -n litellm \
  --timeout=300s

echo ""
echo "Configurando NodePort 30081..."
microk8s kubectl patch svc litellm -n litellm \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":4000,"targetPort":"http","nodePort":30081}]}}' \
  2>/dev/null || true

echo ""
echo "Verificando acesso..."
curl -s http://localhost:30081/health/readiness || echo "Aguardando NodePort..."
sleep 5
curl -s http://localhost:30081/health/readiness || true

echo ""
echo "LiteLLM disponivel em http://localhost:30081"

echo "=== Fase 5 concluida ==="
