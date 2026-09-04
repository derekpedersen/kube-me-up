#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
APP_CHART_DIR="$ROOT_DIR/johnny-5-alive/.helm"

CLOUD="doks"
USE_EXISTING_CLUSTER=""
CLUSTER_NAME="kube-me-up"
REGION="nyc3"
LETSENCRYPT_EMAIL=""
DOMAIN=""
DEPLOY_MODE=""
IMAGE_REPOSITORY=""
IMAGE_TAG=""
WITH_OBSERVABILITY=false
SKIP_OBSERVABILITY=false
ENABLE_HPA=false
HPA_MIN_REPLICAS=2
HPA_MAX_REPLICAS=10
HPA_TARGET_CPU=80
DRY_RUN=false
SKIP_CLUSTER=false
SKIP_INFRA=false
SKIP_ISSUER=false
SKIP_APP=false
NON_INTERACTIVE=false
AUTO_APPROVE=false

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
Kube Me Up installer

Usage:
  ./install.sh [options]

Options:
  --cloud doks|gke|eks         Cloud provider hint (default: doks)
  --use-existing-cluster       Skip cluster creation and use current kubeconfig context
  --skip-cluster               Resume mode: skip cluster provisioning/connectivity step
  --skip-infra                 Resume mode: skip infrastructure install step
  --with-observability         Install Prometheus + Grafana (kube-prometheus-stack)
  --skip-observability         Resume mode: skip observability install step
  --skip-issuer                Resume mode: skip ClusterIssuer apply step
  --skip-app                   Resume mode: skip application deployment step
  --cluster-name NAME          Cluster name (default: kube-me-up)
  --region REGION              Region (default: nyc3)
  --email EMAIL                Let's Encrypt email
  --domain DOMAIN              Ingress host/domain for app
  --deploy-mode MODE           kubernetes|docker|skip
  --image-repository REPO      Optional Helm override for image.repository
  --image-tag TAG              Optional Helm override for image.tag
  --enable-hpa                 Enable HorizontalPodAutoscaler for johnny-5-alive (Kubernetes mode)
  --hpa-min-replicas N         HPA minimum replicas (default: 2)
  --hpa-max-replicas N         HPA maximum replicas (default: 10)
  --hpa-target-cpu N           HPA target CPU utilization percent (default: 80)
  --dry-run                    Print commands without executing
  --non-interactive            Require all needed flags, no prompts
  --yes                        Auto-confirm prompts
  --help                       Show this help

Examples:
  ./install.sh
  ./install.sh --dry-run --use-existing-cluster
  ./install.sh --use-existing-cluster --skip-cluster --skip-infra --deploy-mode kubernetes --skip-issuer
  ./install.sh --use-existing-cluster --domain alive.example.com --email you@example.com
  ./install.sh --use-existing-cluster --deploy-mode kubernetes --with-observability --enable-hpa --domain alive.example.com --email you@example.com
  ./install.sh --cluster-name kube-me-up --region nyc3
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Missing required command: $cmd"
    exit 1
  fi
}

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
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

  local reply=""
  read -r -p "$prompt [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

prompt_default() {
  local var_name="$1"
  local prompt="$2"
  local default_value="$3"

  if [[ "$NON_INTERACTIVE" == true ]]; then
    if [[ -z "${!var_name}" ]]; then
      printf -v "$var_name" '%s' "$default_value"
    fi
    return
  fi

  local value=""
  read -r -p "$prompt [$default_value]: " value
  if [[ -z "$value" ]]; then
    printf -v "$var_name" '%s' "$default_value"
  else
    printf -v "$var_name" '%s' "$value"
  fi
}

prompt_required() {
  local var_name="$1"
  local prompt="$2"

  if [[ "$NON_INTERACTIVE" == true ]]; then
    if [[ -z "${!var_name}" ]]; then
      log_error "Missing required option for non-interactive mode: $var_name"
      exit 1
    fi
    return
  fi

  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$prompt: " value
  done
  printf -v "$var_name" '%s' "$value"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cloud)
        CLOUD="${2:-}"
        shift 2
        ;;
      --use-existing-cluster)
        USE_EXISTING_CLUSTER="true"
        shift
        ;;
      --cluster-name)
        CLUSTER_NAME="${2:-}"
        shift 2
        ;;
      --skip-cluster)
        SKIP_CLUSTER=true
        shift
        ;;
      --skip-infra)
        SKIP_INFRA=true
        shift
        ;;
      --with-observability)
        WITH_OBSERVABILITY=true
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
      --skip-app)
        SKIP_APP=true
        shift
        ;;
      --region)
        REGION="${2:-}"
        shift 2
        ;;
      --email)
        LETSENCRYPT_EMAIL="${2:-}"
        shift 2
        ;;
      --domain)
        DOMAIN="${2:-}"
        shift 2
        ;;
      --deploy-mode)
        DEPLOY_MODE="${2:-}"
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

  if [[ -n "$DEPLOY_MODE" ]]; then
    DEPLOY_MODE="$(echo "$DEPLOY_MODE" | tr '[:upper:]' '[:lower:]')"
  fi

  if [[ "$DEPLOY_MODE" == "skip" ]]; then
    SKIP_APP=true
  fi

  if [[ "$WITH_OBSERVABILITY" == true && "$SKIP_OBSERVABILITY" == true ]]; then
    log_warn "Observability requested and skipped; observability step will be skipped (--skip-observability)"
  fi

  if [[ -z "$USE_EXISTING_CLUSTER" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
      USE_EXISTING_CLUSTER="true"
    else
      local answer=""
      read -r -p "Use existing kubeconfig context instead of creating DOKS cluster? [Y/n]: " answer
      if [[ "$answer" =~ ^[Nn]$ ]]; then
        USE_EXISTING_CLUSTER="false"
      else
        USE_EXISTING_CLUSTER="true"
      fi
    fi
  fi

  if [[ "$USE_EXISTING_CLUSTER" == "false" && "$CLOUD" != "doks" ]]; then
    log_warn "Automated cluster creation in this script is DOKS-first. For $CLOUD, create cluster manually and re-run with --use-existing-cluster."
    exit 1
  fi

  if [[ "$USE_EXISTING_CLUSTER" == "false" ]]; then
    prompt_default CLUSTER_NAME "Cluster name" "$CLUSTER_NAME"
    prompt_default REGION "DOKS region" "$REGION"
  fi

  if [[ -z "$DEPLOY_MODE" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
      DEPLOY_MODE="kubernetes"
    else
      echo "Choose deploy mode:"
      echo "  1) kubernetes"
      echo "  2) docker"
      echo "  3) skip"
      local choice=""
      read -r -p "Selection [1]: " choice
      case "$choice" in
        ""|1) DEPLOY_MODE="kubernetes" ;;
        2) DEPLOY_MODE="docker" ;;
        3) DEPLOY_MODE="skip" ;;
        *)
          log_error "Invalid deploy mode selection"
          exit 1
          ;;
      esac
    fi
  fi

  case "$DEPLOY_MODE" in
    kubernetes|docker|skip)
      ;;
    *)
      log_error "Invalid --deploy-mode: $DEPLOY_MODE"
      exit 1
      ;;
  esac

  if [[ "$ENABLE_HPA" == true && "$DEPLOY_MODE" != "kubernetes" ]]; then
    log_error "--enable-hpa is only valid with --deploy-mode kubernetes"
    exit 1
  fi

  if [[ "$ENABLE_HPA" == true && "$SKIP_APP" == true ]]; then
    log_warn "HPA requested but app deployment is skipped; disabling HPA for this run"
    ENABLE_HPA=false
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
    if (( HPA_MAX_REPLICAS < HPA_MIN_REPLICAS )); then
      log_error "--hpa-max-replicas must be greater than or equal to --hpa-min-replicas"
      exit 1
    fi
  fi

  if [[ "$DEPLOY_MODE" == "kubernetes" && "$NON_INTERACTIVE" != true ]]; then
    if [[ "$WITH_OBSERVABILITY" == false ]]; then
      local observability_answer=""
      read -r -p "Install Prometheus + Grafana observability stack? [y/N]: " observability_answer
      if [[ "$observability_answer" =~ ^[Yy]$ ]]; then
        WITH_OBSERVABILITY=true
      fi
    fi

    if [[ "$ENABLE_HPA" == false && "$SKIP_APP" == false ]]; then
      local hpa_answer=""
      read -r -p "Enable HPA for johnny-5-alive? [y/N]: " hpa_answer
      if [[ "$hpa_answer" =~ ^[Yy]$ ]]; then
        ENABLE_HPA=true
      fi
    fi
  fi

  if [[ "$DEPLOY_MODE" == "kubernetes" && "$SKIP_ISSUER" == false ]]; then
    prompt_required LETSENCRYPT_EMAIL "Let's Encrypt email"
  fi

  if [[ "$DEPLOY_MODE" == "kubernetes" && "$SKIP_APP" == false ]]; then
    prompt_required DOMAIN "Ingress domain (for example alive.example.com)"

    if [[ "$NON_INTERACTIVE" != true ]]; then
      read -r -p "Optional image repository override (Enter to keep chart default): " IMAGE_REPOSITORY
      read -r -p "Optional image tag override (Enter to keep chart default): " IMAGE_TAG
    fi
  fi
}

preflight() {
  log_step "Running preflight checks"
  if [[ "$SKIP_CLUSTER" == false || "$SKIP_INFRA" == false || ( "$DEPLOY_MODE" == "kubernetes" && ( "$SKIP_ISSUER" == false || "$SKIP_APP" == false ) ) ]]; then
    require_cmd kubectl
  fi

  if [[ "$SKIP_INFRA" == false || ( "$DEPLOY_MODE" == "kubernetes" && "$SKIP_APP" == false ) ]]; then
    require_cmd helm
  fi

  if [[ "$WITH_OBSERVABILITY" == true && "$SKIP_OBSERVABILITY" == false ]]; then
    require_cmd helm
  fi

  if [[ "$SKIP_INFRA" == false || "$DEPLOY_MODE" == "docker" ]]; then
    require_cmd make
  fi

  if [[ "$WITH_OBSERVABILITY" == true && "$SKIP_OBSERVABILITY" == false ]]; then
    require_cmd make
  fi

  if [[ "$DEPLOY_MODE" == "docker" && "$SKIP_APP" == false ]]; then
    require_cmd docker
  fi

  if [[ "$SKIP_CLUSTER" == false && "$USE_EXISTING_CLUSTER" == "false" ]]; then
    require_cmd doctl
  fi

  if [[ ! -d "$APP_CHART_DIR" ]]; then
    log_error "Chart directory not found: $APP_CHART_DIR"
    exit 1
  fi
}

install_observability() {
  if [[ "$WITH_OBSERVABILITY" == false ]]; then
    return
  fi

  if [[ "$SKIP_OBSERVABILITY" == true ]]; then
    log_warn "Skipping observability install by request (--skip-observability)"
    return
  fi

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

create_or_use_cluster() {
  if [[ "$SKIP_CLUSTER" == true ]]; then
    log_warn "Skipping cluster step by request (--skip-cluster)"
    return
  fi

  if [[ "$USE_EXISTING_CLUSTER" == "false" ]]; then
    log_step "Provisioning DOKS cluster"

    if doctl kubernetes cluster list --format Name --no-header | grep -Fxq "$CLUSTER_NAME"; then
      log_warn "Cluster '$CLUSTER_NAME' already exists. Skipping create and using existing cluster."
    else
      local create_cmd
      create_cmd="doctl kubernetes cluster create $CLUSTER_NAME --region $REGION --node-pool name=worker-pool\;size=s-2vcpu-4gb\;count=3"

      echo "About to run:"
      echo "  $create_cmd"
      if ! confirm "Proceed with creating cluster '$CLUSTER_NAME' in region '$REGION'?"; then
        log_error "Cluster creation canceled"
        exit 1
      fi

      run_cmd "$create_cmd"
    fi

    run_cmd "doctl kubernetes cluster kubeconfig save $CLUSTER_NAME"
  fi

  log_step "Verifying Kubernetes connectivity"
  run_cmd "kubectl cluster-info >/dev/null"
  run_cmd "kubectl get nodes"
}

install_infra() {
  if [[ "$SKIP_INFRA" == true ]]; then
    log_warn "Skipping infrastructure install by request (--skip-infra)"
    return
  fi

  log_step "Installing infrastructure charts"
  pushd "$ROOT_DIR" >/dev/null
  run_cmd "make helm-charts"
  popd >/dev/null

  log_step "Waiting for infrastructure readiness"
  run_cmd "kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=5m"
  run_cmd "kubectl rollout status deployment/cert-manager -n cert-manager --timeout=5m"
  run_cmd "kubectl rollout status deployment/metrics-server -n kube-system --timeout=5m"

  run_cmd "kubectl get ingressclass nginx >/dev/null"
  run_cmd "kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null"
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
    email: $LETSENCRYPT_EMAIL
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
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
    } >>"$output_file"
  fi
}

apply_cluster_issuer() {
  if [[ "$SKIP_ISSUER" == true ]]; then
    log_warn "Skipping ClusterIssuer apply by request (--skip-issuer)"
    return
  fi

  log_step "Applying ClusterIssuer"
  local issuer_file
  issuer_file="$(mktemp -t kube-me-up-issuer.XXXXXX.yaml)"
  build_cluster_issuer_file "$issuer_file"
  run_cmd "kubectl apply -f $issuer_file"
  run_cmd "kubectl get clusterissuer letsencrypt-prod"

  log_info "Runtime issuer manifest: $issuer_file"
}

deploy_kubernetes_app() {
  if [[ "$SKIP_APP" == true ]]; then
    log_warn "Skipping app deployment by request (--skip-app)"
    return
  fi

  log_step "Deploying johnny-5-alive with runtime overrides"
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

deploy_docker_app() {
  if [[ "$SKIP_APP" == true ]]; then
    log_warn "Skipping app deployment by request (--skip-app)"
    return
  fi

  log_step "Running johnny-5-alive with Docker"
  pushd "$ROOT_DIR/johnny-5-alive" >/dev/null
  run_cmd "make run"
  popd >/dev/null

  log_info "Local app started on http://localhost:9090"
}

summary() {
  log_step "Installation summary"
  echo "Cloud hint: $CLOUD"
  echo "Dry run: $DRY_RUN"
  echo "Use existing cluster: $USE_EXISTING_CLUSTER"
  echo "Deploy mode: $DEPLOY_MODE"
  echo "Skip cluster step: $SKIP_CLUSTER"
  echo "Skip infrastructure step: $SKIP_INFRA"
  echo "With observability: $WITH_OBSERVABILITY"
  echo "Skip observability step: $SKIP_OBSERVABILITY"
  echo "Skip issuer step: $SKIP_ISSUER"
  echo "Skip app step: $SKIP_APP"
  echo "HPA enabled: $ENABLE_HPA"

  if [[ "$ENABLE_HPA" == true ]]; then
    echo "HPA min replicas: $HPA_MIN_REPLICAS"
    echo "HPA max replicas: $HPA_MAX_REPLICAS"
    echo "HPA target CPU: $HPA_TARGET_CPU"
  fi

  if [[ "$DEPLOY_MODE" == "kubernetes" ]]; then
    echo "Domain: $DOMAIN"
    echo "Let's Encrypt email: $LETSENCRYPT_EMAIL"
    echo
    echo "Next verification commands:"
    echo "  kubectl get svc -n ingress-nginx ingress-nginx-controller"
    echo "  kubectl get ingress johnny-5-alive"
    echo "  kubectl get certificate -A"
    echo "  kubectl get challenges -A"
    if [[ "$ENABLE_HPA" == true ]]; then
      echo "  kubectl get hpa johnny-5-alive"
    fi
    if [[ "$WITH_OBSERVABILITY" == true && "$SKIP_OBSERVABILITY" == false ]]; then
      echo "  kubectl get pods -n monitoring"
      echo "  kubectl get svc -n monitoring kube-prometheus-stack-grafana"
      echo "  kubectl get svc -n monitoring kube-prometheus-stack-prometheus"
      echo "  kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
    fi
    echo "  curl -I http://$DOMAIN"
    echo "  curl -I https://$DOMAIN"
  elif [[ "$DEPLOY_MODE" == "docker" ]]; then
    echo "Check local endpoint: http://localhost:9090"
  else
    echo "App deployment skipped. Infrastructure is installed and ready."
  fi

  echo
  echo "For detailed procedures and troubleshooting, see RUNBOOK.md"
}

main() {
  parse_args "$@"
  normalize_settings
  preflight
  create_or_use_cluster
  install_infra
  install_observability

  case "$DEPLOY_MODE" in
    kubernetes)
      apply_cluster_issuer
      deploy_kubernetes_app
      ;;
    docker)
      deploy_docker_app
      ;;
    skip)
      log_warn "App deployment mode is skip"
      ;;
  esac

  summary
}

main "$@"
