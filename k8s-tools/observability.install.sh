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
Kube Me Up observability installer

Install the kube-prometheus-stack observability bundle.

Usage:
  ./k8s-tools/observability.install.sh [options]

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

install_observability() {
  log_step "Installing observability stack"
  pushd "$ROOT_DIR" >/dev/null
  run_cmd "make install-observability"
  popd >/dev/null

  log_step "Waiting for observability readiness"
  run_cmd "kubectl rollout status deployment/kube-prometheus-stack-operator -n monitoring --timeout=5m"
  run_cmd "kubectl get svc -n monitoring kube-prometheus-stack-grafana"
  run_cmd "kubectl get svc -n monitoring kube-prometheus-stack-prometheus"
  log_info "Grafana access: kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
}

main() {
  parse_args "$@"
  preflight
  install_observability
  log_info "Observability install complete"
}

main "$@"
