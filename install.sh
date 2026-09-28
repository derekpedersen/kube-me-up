#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

log_info() {
  printf '%s\n' "$1"
}

usage() {
  cat <<'EOF'
Kube Me Up root install orchestrator

This script coordinates the repo by calling the infrastructure tool scripts
and the project-local app/debug installers in the right order.

Usage:
  ./install.sh [options]

Examples:
  ./install.sh --use-existing-cluster
  ./install.sh --dry-run --use-existing-cluster
  ./install.sh --use-existing-cluster --deploy-mode kubernetes --domain alive.example.com --email you@example.com
EOF
}

run_if_present() {
  local script_path="$1"
  shift

  if [[ -f "$script_path" ]]; then
    "$script_path" "$@"
  else
    echo "Missing script: $script_path" >&2
    exit 1
  fi
}

main() {
  if [[ $# -gt 0 && "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  log_info "Running infrastructure stack"
  run_if_present "$ROOT_DIR/k8s-tools/nginx.install.sh" "$@"
  run_if_present "$ROOT_DIR/k8s-tools/cert-manager.install.sh" "$@"
  run_if_present "$ROOT_DIR/k8s-tools/metrics.install.sh" "$@"
  run_if_present "$ROOT_DIR/k8s-tools/issuer.install.sh" --email "${EMAIL:-you@example.com}" "$@"

  log_info "Deploying johnny-5-alive"
  run_if_present "$ROOT_DIR/johnny-5-alive/install.sh" "$@"

  log_info "Deploying johnny-5-debug"
  run_if_present "$ROOT_DIR/johnny-5-debug/install.sh" "$@"
}

main "$@"
