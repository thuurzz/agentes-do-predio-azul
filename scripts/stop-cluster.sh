#!/usr/bin/env bash
set -euo pipefail

echo "=== Parando cluster ==="
microk8s stop
echo "Cluster parado. Dados preservados (PVCs hostpath)."
echo "Para religar: microk8s start"
