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
Kube Me Up metrics installer

Install metrics-server as a standalone tool.

Usage:
  ./k8s-tools/metrics.install.sh [options]

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

install_metrics_server() {
  log_step "Installing metrics-server"
  run_cmd "helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/"
  run_cmd "helm repo update"
  run_cmd "helm upgrade --install metrics-server metrics-server/metrics-server --namespace kube-system --set args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP\,ExternalIP\,Hostname}"
  run_cmd "kubectl get deployment metrics-server -n kube-system"
  run_cmd "kubectl get apiservice v1beta1.metrics.k8s.io"
}

main() {
  parse_args "$@"
  preflight
  install_metrics_server
  log_info "metrics-server install complete"
}

main "$@"
