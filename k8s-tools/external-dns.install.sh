#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=false
DO_API_TOKEN="${DO_API_TOKEN:-}"
DOMAIN_FILTER="${EXTERNAL_DNS_DOMAIN_FILTER:-}"
TXT_OWNER_ID="${EXTERNAL_DNS_TXT_OWNER_ID:-}"
RELEASE_NAME="external-dns"
NAMESPACE="external-dns"
SECRET_NAME="external-dns"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Kube Me Up ExternalDNS installer

Install ExternalDNS for DigitalOcean DNS. This is required shared infrastructure
for automatic ingress hostname management across apps.

Usage:
  ./k8s-tools/external-dns.install.sh [options]

Required options (or environment variables):
  --do-api-token TOKEN        DigitalOcean API token
                              or set DO_API_TOKEN
  --txt-owner-id ID           TXT owner id used for record ownership
                              or set EXTERNAL_DNS_TXT_OWNER_ID

Optional:
  --domain-filter DOMAIN      DNS domain scope for managed records
                              or set EXTERNAL_DNS_DOMAIN_FILTER
  --release-name NAME         Helm release name (default: external-dns)
  --namespace NS              Namespace (default: external-dns)
  --secret-name NAME          Secret name for token (default: external-dns)
  --dry-run                   Print commands without executing
  --help                      Show this help

Example:
  ./k8s-tools/external-dns.install.sh \
    --do-api-token "$DO_API_TOKEN" \
    --txt-owner-id kube-me-up
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --do-api-token)
        DO_API_TOKEN="${2:-}"
        shift 2
        ;;
      --domain-filter)
        DOMAIN_FILTER="${2:-}"
        shift 2
        ;;
      --txt-owner-id)
        TXT_OWNER_ID="${2:-}"
        shift 2
        ;;
      --release-name)
        RELEASE_NAME="${2:-}"
        shift 2
        ;;
      --namespace)
        NAMESPACE="${2:-}"
        shift 2
        ;;
      --secret-name)
        SECRET_NAME="${2:-}"
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
  require_cmd helm
  require_cmd kubectl

  if [[ -z "$DO_API_TOKEN" ]]; then
    log_error "DigitalOcean API token is required (--do-api-token or DO_API_TOKEN)"
    exit 1
  fi

  if [[ -z "$TXT_OWNER_ID" ]]; then
    log_error "TXT owner id is required (--txt-owner-id or EXTERNAL_DNS_TXT_OWNER_ID)"
    exit 1
  fi

  if [[ -z "$DOMAIN_FILTER" ]]; then
    log_warn "No domain filter set. ExternalDNS will process all ingress hosts visible to this cluster."
  fi
}

install_external_dns() {
  log_step "Installing ExternalDNS"

  run_cmd "helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/"
  run_cmd "helm repo update"

  run_cmd "kubectl get namespace $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE"
  run_cmd "kubectl -n $NAMESPACE create secret generic $SECRET_NAME --from-literal=do_token=$DO_API_TOKEN --dry-run=client -o yaml | kubectl apply -f -"

  local helm_cmd
  helm_cmd="helm upgrade --install $RELEASE_NAME external-dns/external-dns --namespace $NAMESPACE --set provider.name=digitalocean --set env[0].name=DO_TOKEN --set env[0].valueFrom.secretKeyRef.name=$SECRET_NAME --set env[0].valueFrom.secretKeyRef.key=do_token --set sources[0]=ingress --set registry=txt --set txtOwnerId=$TXT_OWNER_ID --set policy=sync"

  if [[ -n "$DOMAIN_FILTER" ]]; then
    helm_cmd+=" --set domainFilters[0]=$DOMAIN_FILTER"
  fi

  run_cmd "$helm_cmd"

  run_cmd "kubectl rollout status deployment/$RELEASE_NAME -n $NAMESPACE --timeout=5m"
  run_cmd "kubectl get deployment $RELEASE_NAME -n $NAMESPACE"
}

main() {
  parse_args "$@"
  preflight
  install_external_dns
  log_info "ExternalDNS install complete"
}

main "$@"