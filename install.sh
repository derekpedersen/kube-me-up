#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

SKIP_INFRA=false
SKIP_ISSUER=false
SKIP_APP=false
SKIP_DEBUG=false
WITH_OBSERVABILITY=false

log_info() {
  printf '%s\n' "$1"
}

usage() {
  cat <<'EOF'
Kube Me Up root install orchestrator

The root script is the repo-level coordinator. It runs the install flow in a
simple, human-readable order:

  1. shared infra
     - nginx
     - cert-manager
     - metrics
     - issuer
  2. optional observability
  3. johnny-5-alive app
  4. johnny-5-debug pod

Usage:
  ./install.sh [flags]

Flags:
  --skip-infra         Skip all shared infra installers
  --skip-issuer        Skip the ClusterIssuer installer
  --skip-app           Skip the johnny-5-alive deployment
  --skip-debug         Skip the johnny-5-debug deployment
  --with-observability Install the Prometheus/Grafana stack in addition to core infra
  --help               Show this help

Compatibility aliases still accepted:
  --skip-cluster       Legacy no-op alias for cluster creation flow
  --with-debug-pod     Legacy alias that keeps the debug deployment enabled

Examples:
  ./install.sh --use-existing-cluster
  ./install.sh --dry-run --use-existing-cluster
  ./install.sh --use-existing-cluster --skip-app --skip-debug
  ./install.sh --use-existing-cluster --with-observability --skip-app
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

strip_root_flags() {
  local -a out=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-cluster|--skip-infra|--skip-issuer|--skip-app|--skip-debug|--with-debug-pod|--with-observability|--help)
        shift
        ;;
      *)
        out+=("$1")
        shift
        ;;
    esac
  done

  printf '%s\n' "${out[@]}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-infra)
        SKIP_INFRA=true
        shift
        ;;
      --skip-issuer)
        SKIP_ISSUER=true
        shift
        ;;
      --skip-app)
        SKIP_APP=true
        shift
        ;;
      --skip-debug)
        SKIP_DEBUG=true
        shift
        ;;
      --with-observability)
        WITH_OBSERVABILITY=true
        shift
        ;;
      --skip-cluster|--with-debug-pod)
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        ROOT_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

main() {
  ROOT_ARGS=()
  parse_args "$@"

  if [[ "$SKIP_INFRA" == false ]]; then
    log_info "Running shared infrastructure installers"
    run_if_present "$ROOT_DIR/k8s-tools/nginx.install.sh" $(strip_root_flags "${ROOT_ARGS[@]}")
    run_if_present "$ROOT_DIR/k8s-tools/cert-manager.install.sh" $(strip_root_flags "${ROOT_ARGS[@]}")
    run_if_present "$ROOT_DIR/k8s-tools/metrics.install.sh" $(strip_root_flags "${ROOT_ARGS[@]}")
    if [[ "$SKIP_ISSUER" == false ]]; then
      run_if_present "$ROOT_DIR/k8s-tools/issuer.install.sh" --email "${EMAIL:-you@example.com}" $(strip_root_flags "${ROOT_ARGS[@]}")
    fi
  fi

  if [[ "$WITH_OBSERVABILITY" == true ]]; then
    log_info "Installing observability stack"
    run_if_present "$ROOT_DIR/k8s-tools/observability.install.sh" $(strip_root_flags "${ROOT_ARGS[@]}")
  fi

  if [[ "$SKIP_APP" == false ]]; then
    log_info "Deploying johnny-5-alive"
    run_if_present "$ROOT_DIR/johnny-5-alive/install.sh" $(strip_root_flags "${ROOT_ARGS[@]}")
  fi

  if [[ "$SKIP_DEBUG" == false ]]; then
    log_info "Deploying johnny-5-debug"
    run_if_present "$ROOT_DIR/johnny-5-debug/install.sh" $(strip_root_flags "${ROOT_ARGS[@]}")
  fi
}

main "$@"
