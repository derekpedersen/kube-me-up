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
Kube Me Up ingress-nginx installer

Install only ingress-nginx and related ingress prerequisites.

Usage:
  ./k8s-tools/nginx.install.sh [options]

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

install_ingress_nginx() {
  log_step "Installing ingress-nginx"
  run_cmd "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx/"
  run_cmd "helm repo update"
  run_cmd "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.ingressClassResource.name=nginx --set controller.ingressClassResource.default=true"
  run_cmd "kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=5m"
  run_cmd "kubectl get ingressclass nginx >/dev/null"
}

main() {
  parse_args "$@"
  preflight
  install_ingress_nginx
  log_info "ingress-nginx install complete"
}

main "$@"
