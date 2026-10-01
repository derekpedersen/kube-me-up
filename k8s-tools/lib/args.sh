#!/usr/bin/env bash

usage() {
  cat <<'EOF'
Kube Me Up installer

The runtime install flow works with any existing Kubernetes cluster. Automatic cluster creation is DOKS-only.

Usage:
  ./k8s-tools/nginx.install.sh [options]

Options:
  --cloud doks|gke|eks         Cloud provider hint (default: doks)
  --use-existing-cluster       Skip cluster creation and use current kubeconfig context
  --skip-cluster               Resume mode: skip cluster provisioning/connectivity step
  --skip-infra                 Resume mode: skip infrastructure install step
  --with-observability         Install Prometheus + Grafana (kube-prometheus-stack)
  --skip-observability         Resume mode: skip observability install step
  --with-debug-pod             Deploy standalone johnny-5-debug pod for exec/testing
  --skip-debug-pod             Resume mode: skip debug pod deployment step
  --debug-pod-image IMAGE      Debug pod image (default: johnny-5-debug:latest)
  --debug-pod-namespace NS     Debug pod namespace (default: default)
  --debug-pod-name NAME        Debug pod name (default: johnny-5-debug)
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
  --hpa-min-replicas N         HPA minimum replicas (default: 1)
  --hpa-max-replicas N         HPA maximum replicas (default: 3)
  --hpa-target-cpu N           HPA target CPU utilization percent (default: 80)
  --hpa-target-mem N           HPA target memory utilization percent (default: 80)
  --dry-run                    Print commands without executing
  --non-interactive            Require all needed flags, no prompts
  --yes                        Auto-confirm prompts
  --help                       Show this help

Examples:
  ./k8s-tools/nginx.install.sh
  ./k8s-tools/nginx.install.sh --dry-run --use-existing-cluster
  ./k8s-tools/nginx.install.sh --use-existing-cluster --deploy-mode skip --skip-infra --skip-issuer --skip-app --with-debug-pod
  ./k8s-tools/nginx.install.sh --use-existing-cluster --skip-cluster --skip-infra --deploy-mode kubernetes --skip-issuer
  ./k8s-tools/nginx.install.sh --use-existing-cluster --domain alive.example.com --email you@example.com
  ./k8s-tools/nginx.install.sh --use-existing-cluster --deploy-mode kubernetes --with-observability --enable-hpa --domain alive.example.com --email you@example.com
  ./k8s-tools/nginx.install.sh --cluster-name kube-me-up --region nyc3
EOF
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
      --with-debug-pod)
        WITH_DEBUG_POD=true
        shift
        ;;
      --skip-debug-pod)
        SKIP_DEBUG_POD=true
        shift
        ;;
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
      --hpa-target-mem)
        HPA_TARGET_MEM="${2:-}"
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

  if [[ "$WITH_DEBUG_POD" == true && "$SKIP_DEBUG_POD" == true ]]; then
    log_warn "Debug pod requested and skipped; debug pod step will be skipped (--skip-debug-pod)"
  fi

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
    if ! is_positive_int "$HPA_TARGET_MEM" || (( HPA_TARGET_MEM > 100 )); then
      log_error "--hpa-target-mem must be an integer between 1 and 100"
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
