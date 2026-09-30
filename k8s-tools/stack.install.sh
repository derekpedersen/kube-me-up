#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Kube Me Up stack installer

Full guided stack deployment orchestrator.
This script delegates to dedicated tool scripts for each step.

Usage:
  ./k8s-tools/stack.install.sh [options]

Options:
  --use-existing-cluster
  --skip-cluster
  --skip-infra
  --skip-issuer
  --skip-app
  --with-observability
  --with-debug-pod
  --deploy-mode kubernetes|docker|skip
  --domain DOMAIN
  --email EMAIL
  --dry-run
  --non-interactive
  --yes
  --help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done
}

run_orchestrator() {
  echo "Stack flow is intentionally delegated to dedicated install steps."
  echo "Recommended commands:"
  echo "  ./k8s-tools/nginx.install.sh"
  echo "  ./k8s-tools/external-dns.install.sh --domain-filter example.com --txt-owner-id kube-me-up --do-api-token \"$DO_API_TOKEN\""
  echo "  ./k8s-tools/cert-manager.install.sh"
  echo "  ./k8s-tools/metrics.install.sh"
  echo "  ./k8s-tools/issuer.install.sh --email you@example.com"
  echo "  ./k8s-tools/app.install.sh --domain alive.example.com"
  echo "  ./k8s-tools/observability.install.sh"
}

main() {
  parse_args "$@"
  run_orchestrator
}

main "$@"
