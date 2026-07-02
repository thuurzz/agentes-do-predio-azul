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

echo "=== Fase 6: Langfuse ==="

echo "Renderizando valores..."
render_template "${PROJECT_DIR}/values/langfuse.yaml.template"

microk8s helm3 repo add langfuse https://langfuse.github.io/langfuse-k8s --force-update 2>/dev/null || true
microk8s helm3 repo update

microk8s helm3 upgrade --install langfuse langfuse/langfuse \
  -f "${PROJECT_DIR}/values/langfuse.yaml" \
  -n langfuse \
  --timeout 15m

echo ""
echo "Verificando pods..."
microk8s kubectl get pods -n langfuse

echo ""
echo "Aguardando pods ficarem prontos..."
microk8s kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=langfuse \
  -n langfuse \
  --timeout=600s 2>/dev/null || true

echo ""
echo "Configurando NodePort 30082..."
microk8s kubectl patch svc langfuse-web -n langfuse \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":3000,"targetPort":3000,"nodePort":30082}]}}' \
  2>/dev/null || true

echo ""
echo "Verificando acesso..."
curl -s -o /dev/null -w '%{http_code}' http://localhost:30082/ || echo "Aguardando..."
sleep 5
curl -s -o /dev/null -w '%{http_code}' http://localhost:30082/ || true

echo ""
echo "Langfuse disponivel em http://localhost:30082"

echo "=== Fase 6 concluida ==="
