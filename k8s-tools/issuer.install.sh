#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EMAIL=""
DRY_RUN=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Kube Me Up ClusterIssuer installer

Apply a LetsEncrypt ClusterIssuer as a standalone tool.

Usage:
  ./k8s-tools/issuer.install.sh --email you@example.com [options]

Options:
  --email EMAIL    LetsEncrypt email address
  --dry-run        Print kubectl apply command without executing it
  --help           Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --email)
        EMAIL="${2:-}"
        shift 2
        ;;
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
  require_cmd kubectl
  if [[ -z "$EMAIL" ]]; then
    log_error "--email is required"
    exit 1
  fi
}

build_cluster_issuer_file() {
  local output_file="$1"

  cat >"$output_file" <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: $EMAIL
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
}

apply_cluster_issuer() {
  log_step "Applying ClusterIssuer"
  local issuer_file
  issuer_file="$(mktemp -t kube-me-up-issuer.XXXXXX.yaml)"
  build_cluster_issuer_file "$issuer_file"
  run_cmd "kubectl apply -f $issuer_file"
  run_cmd "kubectl get clusterissuer letsencrypt-prod"
  log_info "ClusterIssuer manifest: $issuer_file"
}

main() {
  parse_args "$@"
  preflight
  apply_cluster_issuer
  log_info "ClusterIssuer apply complete"
}

main "$@"
