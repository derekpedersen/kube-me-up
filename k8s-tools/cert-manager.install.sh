#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Kube Me Up cert-manager installer

Install cert-manager as a standalone tool.

Usage:
  ./k8s-tools/cert-manager.install.sh [options]

Options:
  --dry-run     Print Helm commands without executing them
  --help        Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

preflight() {
  require_cmd helm
  require_cmd kubectl
}

install_cert_manager() {
  log_step "Installing cert-manager"
  run_cmd "helm repo add jetstack https://charts.jetstack.io"
  run_cmd "helm repo update"
  run_cmd "helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.9.1 --set installCRDs=true"
  run_cmd "kubectl rollout status deployment/cert-manager -n cert-manager --timeout=5m"
  run_cmd "kubectl get pods -n cert-manager"
}

main() {
  parse_args "$@"
  preflight
  install_cert_manager
  log_info "cert-manager install complete"
}

main "$@"
