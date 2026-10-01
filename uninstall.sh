#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

CLOUD="doks"
CLUSTER_NAME="kube-me-up"
DELETE_CLUSTER=false
DRY_RUN=false
NON_INTERACTIVE=false
AUTO_APPROVE=false
SKIP_APP=false
SKIP_INFRA=false
SKIP_OBSERVABILITY=false
SKIP_ISSUER=false
SKIP_DEBUG_POD=false

APP_RELEASE="johnny-5-alive"
APP_NAMESPACE="default"
ISSUER_NAME="letsencrypt-prod"
DEBUG_POD_NAMESPACE="default"
DEBUG_POD_NAME="johnny-5-debug"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  printf "%b[INFO]%b %s\n" "$GREEN" "$NC" "$1"
}

log_warn() {
  printf "%b[WARN]%b %s\n" "$YELLOW" "$NC" "$1"
}

log_error() {
  printf "%b[ERROR]%b %s\n" "$RED" "$NC" "$1" >&2
}

log_step() {
  printf "\n%b==>%b %s\n" "$BLUE" "$NC" "$1"
}

usage() {
  cat <<'EOF'
Kube Me Up uninstall script

The teardown flow works with any existing Kubernetes cluster. Optional cluster deletion is DOKS-only.

Usage:
  ./uninstall.sh [options]

Options:
  --cloud doks|gke|eks         Cloud provider hint for cluster deletion (default: doks)
  --cluster-name NAME          Cluster name to delete with doctl (default: kube-me-up)
  --delete-cluster             Delete the DOKS cluster after cleanup
  --skip-app                   Skip johnny-5-alive uninstall
  --skip-infra                 Skip ingress-nginx, cert-manager, and metrics-server uninstall
  --skip-observability         Skip kube-prometheus-stack uninstall
  --skip-issuer                Skip ClusterIssuer removal
  --skip-debug-pod             Skip johnny-5-debug pod removal
  --dry-run                    Print commands without executing
  --non-interactive            Fail instead of prompting for confirmation
  --yes                        Auto-confirm prompts
  --help                       Show this help

Examples:
  ./uninstall.sh
  ./uninstall.sh --dry-run
  ./uninstall.sh --skip-infra --skip-observability
  ./uninstall.sh --delete-cluster --yes
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Missing required command: $cmd"
    exit 1
  fi
}

run_cmd() {
  local cmd="$1"
  if [[ "$DRY_RUN" == true ]]; then
    printf "[DRY-RUN] %s\n" "$cmd"
    return 0
  fi
  eval "$cmd"
}

confirm() {
  local prompt="$1"
  if [[ "$AUTO_APPROVE" == true ]]; then
    return 0
  fi

  if [[ "$NON_INTERACTIVE" == true ]]; then
    log_error "Refusing to prompt in non-interactive mode. Re-run with --yes to confirm."
    exit 1
  fi

  local reply=""
  read -r -p "$prompt [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cloud)
        CLOUD="${2:-}"
        shift 2
        ;;
      --cluster-name)
        CLUSTER_NAME="${2:-}"
        shift 2
        ;;
      --delete-cluster)
        DELETE_CLUSTER=true
        shift
        ;;
      --skip-app)
        SKIP_APP=true
        shift
        ;;
      --skip-infra)
        SKIP_INFRA=true
        shift
        ;;
      --skip-observability)
        SKIP_OBSERVABILITY=true
        shift
        ;;
      --skip-issuer)
        SKIP_ISSUER=true
        shift
        ;;
      --skip-debug-pod)
        SKIP_DEBUG_POD=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
      --yes)
        AUTO_APPROVE=true
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

normalize_settings() {
  CLOUD="$(echo "$CLOUD" | tr '[:upper:]' '[:lower:]')"

  if [[ "$CLOUD" != "doks" && "$DELETE_CLUSTER" == true ]]; then
    log_error "--delete-cluster is only supported for DOKS clusters"
    exit 1
  fi

  if [[ "$SKIP_APP" == true && "$SKIP_INFRA" == true && "$SKIP_OBSERVABILITY" == true && "$SKIP_ISSUER" == true && "$SKIP_DEBUG_POD" == true && "$DELETE_CLUSTER" == false ]]; then
    log_warn "No cleanup actions selected"
    exit 0
  fi
}

preflight() {
  log_step "Running preflight checks"

  if [[ "$DRY_RUN" == true ]]; then
    return
  fi

  if [[ "$DELETE_CLUSTER" == true ]]; then
    require_cmd doctl
    return
  fi

  if [[ "$SKIP_APP" == false || "$SKIP_INFRA" == false || "$SKIP_OBSERVABILITY" == false || "$SKIP_ISSUER" == false || "$SKIP_DEBUG_POD" == false ]]; then
    require_cmd kubectl
  fi

  if [[ "$SKIP_APP" == false || "$SKIP_INFRA" == false || "$SKIP_OBSERVABILITY" == false ]]; then
    require_cmd helm
  fi
}

helm_release_exists() {
  local release="$1"
  local namespace="$2"

  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi

  helm status "$release" -n "$namespace" >/dev/null 2>&1
}

uninstall_release() {
  local release="$1"
  local namespace="$2"
  local label="$3"

  if ! helm_release_exists "$release" "$namespace"; then
    log_warn "$label release '$release' not found in namespace '$namespace'; skipping"
    return
  fi

  log_step "Removing $label"
  run_cmd "helm uninstall $release -n $namespace"
}

remove_clusterissuer() {
  if [[ "$SKIP_ISSUER" == true ]]; then
    log_warn "Skipping ClusterIssuer removal by request (--skip-issuer)"
    return
  fi

  log_step "Removing ClusterIssuer"
  run_cmd "kubectl delete clusterissuer $ISSUER_NAME --ignore-not-found"
}

remove_debug_pod() {
  if [[ "$SKIP_DEBUG_POD" == true ]]; then
    log_warn "Skipping debug pod removal by request (--skip-debug-pod)"
    return
  fi

  log_step "Removing standalone debug pod"
  run_cmd "kubectl delete pod $DEBUG_POD_NAME -n $DEBUG_POD_NAMESPACE --ignore-not-found"
}

remove_observability() {
  if [[ "$SKIP_OBSERVABILITY" == true ]]; then
    log_warn "Skipping observability removal by request (--skip-observability)"
    return
  fi

  uninstall_release "kube-prometheus-stack" "monitoring" "observability"
}

remove_infra() {
  if [[ "$SKIP_INFRA" == true ]]; then
    log_warn "Skipping infrastructure removal by request (--skip-infra)"
    return
  fi

  uninstall_release "ingress-nginx" "ingress-nginx" "ingress controller"
  uninstall_release "cert-manager" "cert-manager" "cert-manager"
  uninstall_release "metrics-server" "kube-system" "metrics-server"
}

remove_app() {
  if [[ "$SKIP_APP" == true ]]; then
    log_warn "Skipping app removal by request (--skip-app)"
    return
  fi

  uninstall_release "$APP_RELEASE" "$APP_NAMESPACE" "johnny-5-alive app"
}

delete_cluster() {
  if [[ "$DELETE_CLUSTER" == false ]]; then
    return
  fi

  log_step "Deleting DOKS cluster"

  if [[ "$DRY_RUN" == true ]]; then
    run_cmd "doctl kubernetes cluster delete $CLUSTER_NAME --force"
    return
  fi

  if ! doctl kubernetes cluster list --format Name --no-header | grep -Fxq "$CLUSTER_NAME"; then
    log_warn "Cluster '$CLUSTER_NAME' not found; skipping delete"
    return
  fi

  if ! confirm "Delete DOKS cluster '$CLUSTER_NAME'?"; then
    log_error "Cluster deletion canceled"
    exit 1
  fi

  run_cmd "doctl kubernetes cluster delete $CLUSTER_NAME --force"
}

summary() {
  log_step "Uninstall summary"
  echo "Cloud hint: $CLOUD"
  echo "Dry run: $DRY_RUN"
  echo "Delete cluster: $DELETE_CLUSTER"
  echo "Skip app: $SKIP_APP"
  echo "Skip infrastructure: $SKIP_INFRA"
  echo "Skip observability: $SKIP_OBSERVABILITY"
  echo "Skip issuer: $SKIP_ISSUER"
  echo "Skip debug pod: $SKIP_DEBUG_POD"
  if [[ "$DELETE_CLUSTER" == true ]]; then
    echo "Cluster name: $CLUSTER_NAME"
  fi
  echo
  echo "Cleanup complete"
}

main() {
  parse_args "$@"
  normalize_settings
  preflight

  if [[ "$DRY_RUN" == false ]]; then
    if ! confirm "Proceed with uninstalling the managed Kube Me Up resources?"; then
      log_error "Uninstall canceled"
      exit 1
    fi
  fi

  remove_debug_pod
  remove_app
  remove_clusterissuer
  remove_observability
  remove_infra
  delete_cluster
  summary
}

main "$@"