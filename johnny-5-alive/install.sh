#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_CHART_DIR="$ROOT_DIR/johnny-5-alive/.helm"

DOMAIN=""
IMAGE_REPOSITORY=""
IMAGE_TAG=""
ENABLE_HPA=false
HPA_MIN_REPLICAS=1
HPA_MAX_REPLICAS=3
HPA_TARGET_CPU=80
HPA_TARGET_MEM=80
DRY_RUN=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Kube Me Up johnny-5-alive installer

Deploy the johnny-5-alive app to the current Kubernetes cluster.

Usage:
  ./k8s-tools/johnny-5-alive.install.sh --domain alive.example.com [options]

Options:
  --domain DOMAIN                    Ingress host/domain for the app
  --image-repository REPO           Optional image override
  --image-tag TAG                   Optional image tag override
  --enable-hpa                      Enable HPA for the app
  --hpa-min-replicas N              HPA minimum replicas (default: 1)
  --hpa-max-replicas N              HPA maximum replicas (default: 3)
  --hpa-target-cpu N                HPA target CPU utilization percent (default: 80)
  --hpa-target-mem N                HPA target memory utilization percent (default: 80)
  --dry-run                         Print Helm commands without executing them
  --help                            Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        DOMAIN="${2:-}"
        shift 2
        ;;
      --image-repository)
        IMAGE_REPOSITORY="${2:-}"
        shift 2
        ;;
      --image-tag)
        IMAGE_TAG="${2:-}"
        shift 2
        ;;
      --enable-hpa)
        ENABLE_HPA=true
        shift
        ;;
      --hpa-min-replicas)
        HPA_MIN_REPLICAS="${2:-}"
        shift 2
        ;;
      --hpa-max-replicas)
        HPA_MAX_REPLICAS="${2:-}"
        shift 2
        ;;
      --hpa-target-cpu)
        HPA_TARGET_CPU="${2:-}"
        shift 2
        ;;
      --hpa-target-mem)
        HPA_TARGET_MEM="${2:-}"
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

  if [[ -z "$DOMAIN" ]]; then
    log_error "--domain is required"
    exit 1
  fi

  if [[ "$ENABLE_HPA" == true ]]; then
    if ! is_positive_int "$HPA_MIN_REPLICAS"; then
      log_error "--hpa-min-replicas must be a positive integer"
      exit 1
    fi
    if ! is_positive_int "$HPA_MAX_REPLICAS"; then
      log_error "--hpa-max-replicas must be a positive integer"
      exit 1
    fi
    if ! is_positive_int "$HPA_TARGET_CPU" || (( HPA_TARGET_CPU > 100 )); then
      log_error "--hpa-target-cpu must be an integer between 1 and 100"
      exit 1
    fi
    if ! is_positive_int "$HPA_TARGET_MEM" || (( HPA_TARGET_MEM > 100 )); then
      log_error "--hpa-target-mem must be an integer between 1 and 100"
      exit 1
    fi
    if (( HPA_MAX_REPLICAS < HPA_MIN_REPLICAS )); then
      log_error "--hpa-max-replicas must be greater than or equal to --hpa-min-replicas"
      exit 1
    fi
  fi
}

build_helm_override_file() {
  local output_file="$1"
  local tls_secret
  tls_secret="$(echo "$DOMAIN" | tr '.' '-')-tls"

  cat >"$output_file" <<EOF
ingress:
  enabled: true
  className: "nginx"
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: $DOMAIN
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: $tls_secret
      hosts:
        - $DOMAIN
EOF

  if [[ -n "$IMAGE_REPOSITORY" || -n "$IMAGE_TAG" ]]; then
    {
      echo "image:"
      if [[ -n "$IMAGE_REPOSITORY" ]]; then
        echo "  repository: $IMAGE_REPOSITORY"
      fi
      if [[ -n "$IMAGE_TAG" ]]; then
        echo "  tag: $IMAGE_TAG"
      fi
    } >>"$output_file"
  fi

  if [[ "$ENABLE_HPA" == true ]]; then
    {
      echo "autoscaling:"
      echo "  enabled: true"
      echo "  minReplicas: $HPA_MIN_REPLICAS"
      echo "  maxReplicas: $HPA_MAX_REPLICAS"
      echo "  targetCPUUtilizationPercentage: $HPA_TARGET_CPU"
      echo "  targetMemoryUtilizationPercentage: $HPA_TARGET_MEM"
    } >>"$output_file"
  fi
}

deploy_app() {
  log_step "Deploying johnny-5-alive"
  local values_file
  values_file="$(mktemp -t kube-me-up-values.XXXXXX.yaml)"
  build_helm_override_file "$values_file"

  run_cmd "helm upgrade --install johnny-5-alive $APP_CHART_DIR -f $values_file"
  run_cmd "kubectl rollout status deployment/johnny-5-alive --timeout=5m"
  run_cmd "kubectl get ingress johnny-5-alive"

  if [[ "$ENABLE_HPA" == true ]]; then
    run_cmd "kubectl get hpa johnny-5-alive"
  fi

  log_info "Runtime override file: $values_file"
}

main() {
  parse_args "$@"
  preflight
  deploy_app
  log_info "johnny-5-alive install complete"
}

main "$@"
