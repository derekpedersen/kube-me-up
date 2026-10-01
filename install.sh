#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

SKIP_INFRA=false
SKIP_ISSUER=false
SKIP_APP=false
SKIP_DEBUG=false
WITH_OBSERVABILITY=false
COMMON_ARGS=()
EXTERNAL_DNS_ARGS=()
APP_ARGS=()
DEBUG_ARGS=()
ISSUER_EMAIL="${EMAIL:-you@example.com}"

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
     - external-dns
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
  --do-api-token TOKEN DigitalOcean API token for mandatory ExternalDNS
  --domain-filter ZONE Optional ExternalDNS scope (recommended)
  --txt-owner-id ID    TXT owner id used by ExternalDNS
  --help               Show this help

Compatibility aliases still accepted:
  --skip-cluster       Legacy no-op alias for cluster creation flow
  --with-debug-pod     Legacy alias that keeps the debug deployment enabled

Examples:
  ./install.sh --use-existing-cluster
  ./install.sh --dry-run --use-existing-cluster
  ./install.sh --use-existing-cluster --skip-app --skip-debug
  ./install.sh --use-existing-cluster --with-observability --skip-app
  ./install.sh --use-existing-cluster --txt-owner-id kube-me-up --do-api-token "$DO_API_TOKEN"
  ./install.sh --use-existing-cluster --domain-filter example.com --txt-owner-id kube-me-up --do-api-token "$DO_API_TOKEN"
EOF
}

run_if_present() {
  local script_path="$1"
  shift

  if [[ -f "$script_path" ]]; then
    bash "$script_path" "$@"
  else
    echo "Missing script: $script_path" >&2
    exit 1
  fi
}

build_installer_args() {
  COMMON_ARGS=()
  EXTERNAL_DNS_ARGS=()
  APP_ARGS=()
  DEBUG_ARGS=()
  ISSUER_EMAIL="${EMAIL:-you@example.com}"

  local i=0
  while (( i < ${#ROOT_ARGS[@]} )); do
    local arg="${ROOT_ARGS[$i]}"

    case "$arg" in
      --dry-run)
        COMMON_ARGS+=("$arg")
        ((i += 1))
        ;;
      --email)
        if (( i + 1 < ${#ROOT_ARGS[@]} )); then
          ISSUER_EMAIL="${ROOT_ARGS[$((i + 1))]}"
        fi
        ((i += 2))
        ;;
      --domain|--image-repository|--image-tag|--hpa-min-replicas|--hpa-max-replicas|--hpa-target-cpu|--hpa-target-mem)
        if (( i + 1 < ${#ROOT_ARGS[@]} )); then
          APP_ARGS+=("$arg" "${ROOT_ARGS[$((i + 1))]}")
        fi
        ((i += 2))
        ;;
      --enable-hpa)
        APP_ARGS+=("$arg")
        ((i += 1))
        ;;
      --debug-pod-image|--debug-pod-namespace|--debug-pod-name)
        if (( i + 1 < ${#ROOT_ARGS[@]} )); then
          DEBUG_ARGS+=("$arg" "${ROOT_ARGS[$((i + 1))]}")
        fi
        ((i += 2))
        ;;
      --do-api-token|--domain-filter|--txt-owner-id|--release-name|--namespace|--secret-name)
        if (( i + 1 < ${#ROOT_ARGS[@]} )); then
          EXTERNAL_DNS_ARGS+=("$arg" "${ROOT_ARGS[$((i + 1))]}")
        fi
        ((i += 2))
        ;;
      --use-existing-cluster|--deploy-mode|--cloud|--cluster-name|--region|--non-interactive|--yes)
        if [[ "$arg" == "--deploy-mode" || "$arg" == "--cloud" || "$arg" == "--cluster-name" || "$arg" == "--region" ]]; then
          ((i += 2))
        else
          ((i += 1))
        fi
        ;;
      *)
        ((i += 1))
        ;;
    esac
  done
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
  build_installer_args

  if [[ "$SKIP_INFRA" == false ]]; then
    log_info "Running shared infrastructure installers"
    run_if_present "$ROOT_DIR/k8s-tools/nginx.install.sh" "${COMMON_ARGS[@]}"
    run_if_present "$ROOT_DIR/k8s-tools/cert-manager.install.sh" "${COMMON_ARGS[@]}"
    run_if_present "$ROOT_DIR/k8s-tools/metrics.install.sh" "${COMMON_ARGS[@]}"
    if [[ ${#EXTERNAL_DNS_ARGS[@]} -gt 0 ]]; then
      run_if_present "$ROOT_DIR/k8s-tools/external-dns.install.sh" "${COMMON_ARGS[@]}" "${EXTERNAL_DNS_ARGS[@]}"
    else
      run_if_present "$ROOT_DIR/k8s-tools/external-dns.install.sh" "${COMMON_ARGS[@]}"
    fi
    if [[ "$SKIP_ISSUER" == false ]]; then
      run_if_present "$ROOT_DIR/k8s-tools/issuer.install.sh" --email "$ISSUER_EMAIL" "${COMMON_ARGS[@]}"
    fi
  fi

  if [[ "$WITH_OBSERVABILITY" == true ]]; then
    log_info "Installing observability stack"
    run_if_present "$ROOT_DIR/k8s-tools/observability.install.sh" "${COMMON_ARGS[@]}"
  fi

  if [[ "$SKIP_APP" == false ]]; then
    log_info "Deploying johnny-5-alive"
    if [[ ${#APP_ARGS[@]} -gt 0 ]]; then
      run_if_present "$ROOT_DIR/k8s-tools/johnny-5-alive.install.sh" "${COMMON_ARGS[@]}" "${APP_ARGS[@]}"
    else
      run_if_present "$ROOT_DIR/k8s-tools/johnny-5-alive.install.sh" "${COMMON_ARGS[@]}"
    fi
  fi

  if [[ "$SKIP_DEBUG" == false ]]; then
    log_info "Deploying johnny-5-debug"
    if [[ ${#DEBUG_ARGS[@]} -gt 0 ]]; then
      run_if_present "$ROOT_DIR/johnny-5-debug/install.sh" "${COMMON_ARGS[@]}" "${DEBUG_ARGS[@]}"
    else
      run_if_present "$ROOT_DIR/johnny-5-debug/install.sh" "${COMMON_ARGS[@]}"
    fi
  fi
}

main "$@"
