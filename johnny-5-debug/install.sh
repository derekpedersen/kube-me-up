#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEBUG_POD_MANIFEST="$ROOT_DIR/johnny-5-debug/pod.yaml"

DEBUG_POD_IMAGE="johnny-5-debug:latest"
DEBUG_POD_NAMESPACE="default"
DEBUG_POD_NAME="johnny-5-debug"
DRY_RUN=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Kube Me Up johnny-5-debug installer

Deploy the standalone debug pod used for exec/testing inside Kubernetes.

Usage:
  ./k8s-tools/johnny-5-debug.install.sh [options]

Options:
  --debug-pod-image IMAGE      Debug pod image (default: johnny-5-debug:latest)
  --debug-pod-namespace NS     Debug pod namespace (default: default)
  --debug-pod-name NAME        Debug pod name (default: johnny-5-debug)
  --dry-run                    Print kubectl commands without executing them
  --help                       Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug-pod-image)
        DEBUG_POD_IMAGE="${2:-}"
        shift 2
        ;;
      --debug-pod-namespace)
        DEBUG_POD_NAMESPACE="${2:-}"
        shift 2
        ;;
      --debug-pod-name)
        DEBUG_POD_NAME="${2:-}"
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

  if [[ -z "$DEBUG_POD_IMAGE" ]]; then
    log_error "--debug-pod-image cannot be empty"
    exit 1
  fi

  if [[ -z "$DEBUG_POD_NAMESPACE" ]]; then
    log_error "--debug-pod-namespace cannot be empty"
    exit 1
  fi

  if [[ -z "$DEBUG_POD_NAME" ]]; then
    log_error "--debug-pod-name cannot be empty"
    exit 1
  fi

  if [[ ! -f "$DEBUG_POD_MANIFEST" ]]; then
    log_error "Debug pod manifest not found: $DEBUG_POD_MANIFEST"
    exit 1
  fi
}

deploy_debug_pod() {
  log_step "Deploying standalone johnny-5-debug pod"

  run_cmd "kubectl get namespace $DEBUG_POD_NAMESPACE >/dev/null 2>&1 || kubectl create namespace $DEBUG_POD_NAMESPACE"

  local debug_manifest
  debug_manifest="$(mktemp -t kube-me-up-debug-pod.XXXXXX.yaml)"

  cat >"$debug_manifest" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $DEBUG_POD_NAME
  labels:
    app.kubernetes.io/name: johnny-5-debug
spec:
  containers:
    - name: debug
      image: $DEBUG_POD_IMAGE
      imagePullPolicy: IfNotPresent
      command: ["sh", "-c", "sleep infinity"]
      stdin: true
      tty: true
EOF

  run_cmd "kubectl apply -n $DEBUG_POD_NAMESPACE -f $debug_manifest"
  run_cmd "kubectl wait --for=condition=Ready pod/$DEBUG_POD_NAME -n $DEBUG_POD_NAMESPACE --timeout=180s"
  run_cmd "kubectl get pod $DEBUG_POD_NAME -n $DEBUG_POD_NAMESPACE"

  log_info "Debug pod manifest: $debug_manifest"
  log_info "Exec into pod: kubectl exec -it -n $DEBUG_POD_NAMESPACE $DEBUG_POD_NAME -- sh"
}

main() {
  parse_args "$@"
  preflight
  deploy_debug_pod
  log_info "johnny-5-debug install complete"
}

main "$@"
