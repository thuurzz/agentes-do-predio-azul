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
  echo "  Rendered: $output"
}

echo "=== Fase 1: Bootstrap ==="

echo "[1.1] Instalando microk8s..."
sudo snap install microk8s --classic --channel=1.32/stable

echo "[1.2] Adicionando usuario ao grupo microk8s..."
sudo usermod -a -G microk8s "$USER"
newgrp microk8s

echo "[1.4] Habilitando addons..."
sudo microk8s enable dns
sudo microk8s enable hostpath-storage
sudo microk8s enable helm3

echo "[1.5] Aguardando cluster..."
microk8s status --wait-ready

echo "[1.6] Criando alias..."
alias kubectl='microk8s kubectl'

echo "[1.7-1.9] Criando namespaces..."
microk8s kubectl create namespace infrastructure --dry-run=client -o yaml | microk8s kubectl apply -f -
microk8s kubectl create namespace litellm --dry-run=client -o yaml | microk8s kubectl apply -f -
microk8s kubectl create namespace langfuse --dry-run=client -o yaml | microk8s kubectl apply -f -

echo "[1.10] Verificando..."
microk8s kubectl get nodes
microk8s kubectl get ns

echo "=== Fase 1 concluida ==="
