#!/usr/bin/env bash
set -euo pipefail

echo "=== Iniciando cluster ==="
microk8s start
microk8s status --wait-ready
echo "Cluster pronto."
microk8s kubectl get pods -A | grep -E 'infrastructure|litellm|langfuse'
