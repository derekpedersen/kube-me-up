#!/usr/bin/env bash

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

  if [[ "$WITH_DEBUG_POD" == true && "$SKIP_DEBUG_POD" == false ]]; then
    require_cmd kubectl
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

  if [[ "$WITH_DEBUG_POD" == true && "$SKIP_DEBUG_POD" == false && ! -f "$DEBUG_POD_MANIFEST" ]]; then
    log_error "Debug pod manifest not found: $DEBUG_POD_MANIFEST"
    exit 1
  fi
}

deploy_debug_pod() {
  if [[ "$WITH_DEBUG_POD" == false ]]; then
    return
  fi

  if [[ "$SKIP_DEBUG_POD" == true ]]; then
    log_warn "Skipping debug pod deployment by request (--skip-debug-pod)"
    return
  fi

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
      echo "  targetMemoryUtilizationPercentage: $HPA_TARGET_MEM"
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
  echo "With debug pod: $WITH_DEBUG_POD"
  echo "Skip debug pod step: $SKIP_DEBUG_POD"
  echo "Skip issuer step: $SKIP_ISSUER"
  echo "Skip app step: $SKIP_APP"
  echo "HPA enabled: $ENABLE_HPA"

  if [[ "$WITH_DEBUG_POD" == true ]]; then
    echo "Debug pod image: $DEBUG_POD_IMAGE"
    echo "Debug pod namespace: $DEBUG_POD_NAMESPACE"
    echo "Debug pod name: $DEBUG_POD_NAME"
  fi

  if [[ "$ENABLE_HPA" == true ]]; then
    echo "HPA min replicas: $HPA_MIN_REPLICAS"
    echo "HPA max replicas: $HPA_MAX_REPLICAS"
    echo "HPA target CPU: $HPA_TARGET_CPU"
    echo "HPA target memory: $HPA_TARGET_MEM"
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
    if [[ "$WITH_DEBUG_POD" == true && "$SKIP_DEBUG_POD" == false ]]; then
      echo "  kubectl get pod $DEBUG_POD_NAME -n $DEBUG_POD_NAMESPACE"
      echo "  kubectl exec -it -n $DEBUG_POD_NAMESPACE $DEBUG_POD_NAME -- sh"
    fi
    echo "  curl -I http://$DOMAIN"
    echo "  curl -I https://$DOMAIN"
  elif [[ "$DEPLOY_MODE" == "docker" ]]; then
    echo "Check local endpoint: http://localhost:9090"
    if [[ "$WITH_DEBUG_POD" == true && "$SKIP_DEBUG_POD" == false ]]; then
      echo "Debug pod is also deployed on Kubernetes:"
      echo "  kubectl get pod $DEBUG_POD_NAME -n $DEBUG_POD_NAMESPACE"
      echo "  kubectl exec -it -n $DEBUG_POD_NAMESPACE $DEBUG_POD_NAME -- sh"
    fi
  else
    echo "App deployment skipped. Infrastructure is installed and ready."
    if [[ "$WITH_DEBUG_POD" == true && "$SKIP_DEBUG_POD" == false ]]; then
      echo "Debug pod deployed for pod-only testing:"
      echo "  kubectl get pod $DEBUG_POD_NAME -n $DEBUG_POD_NAMESPACE"
      echo "  kubectl exec -it -n $DEBUG_POD_NAMESPACE $DEBUG_POD_NAME -- sh"
    fi
  fi

  echo
  echo "For detailed procedures and troubleshooting, see RUNBOOK.md"
}
