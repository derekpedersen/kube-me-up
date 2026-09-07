# Kube Me Up Runbook

This runbook is the operator-safe, step-by-step install and validation guide for this repository.

## 1. Preflight

Run these checks from repo root:

```bash
command -v kubectl
command -v helm
command -v docker
command -v make
command -v git
```

If you plan to create a DigitalOcean Kubernetes cluster from this workflow:

```bash
command -v doctl
```

## 2. Choose Cluster Path

You have two supported paths in this runbook.

1. Create a new DOKS cluster.
2. Use an existing Kubernetes cluster/context.

### 2.1 Create a New DOKS Cluster

Authenticate and create cluster:

```bash
doctl auth init

doctl kubernetes cluster create kube-me-up \
  --region nyc3 \
  --node-pool "name=worker-pool;size=s-2vcpu-4gb;count=3"
```

Fetch kubeconfig:

```bash
doctl kubernetes cluster kubeconfig save kube-me-up
kubectl get nodes
```

### 2.2 Use Existing Cluster

Confirm context is valid:

```bash
kubectl config current-context
kubectl cluster-info
kubectl get nodes
```

## 3. Install Infrastructure Layer

This installs ingress, cert-manager, and metrics-server.

```bash
make helm-charts
```

Validate readiness:

```bash
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=5m
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=5m
kubectl rollout status deployment/metrics-server -n kube-system --timeout=5m
kubectl get ingressclass nginx
kubectl get apiservice v1beta1.metrics.k8s.io
```

## 4. Optional Observability Layer (Prometheus + Grafana)

Install:

```bash
make install-observability
```

Validate readiness:

```bash
kubectl rollout status deployment/kube-prometheus-stack-operator -n monitoring --timeout=5m
kubectl get svc -n monitoring kube-prometheus-stack-grafana
kubectl get svc -n monitoring kube-prometheus-stack-prometheus
```

Access Grafana locally:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```

## 5. Optional Standalone Debug Pod

Use `johnny-5-debug` for exec-based connectivity and Kubernetes testing without deploying the app stack.

Build image locally:

```bash
make debug-build
make debug-build-publish
```

Deploy pod only:

```bash
make debug-deploy-pod
kubectl exec -it -n default johnny-5-debug -- sh
```

Deploy with custom image and namespace:

```bash
make debug-deploy-pod DEBUG_IMAGE=your-registry/johnny-5-debug:tag DEBUG_NAMESPACE=default DEBUG_POD_NAME=johnny-5-debug
```

Delete debug pod:

```bash
make debug-delete-pod
```

## 6. Configure and Apply ClusterIssuer

The default template in this repo includes a static email. For real use, apply your own email.

Option A: Use installer (recommended).

```bash
./install.sh
```

Option B: Manual apply with edited email:

```bash
cp cluster_issuer.yaml /tmp/cluster_issuer.runtime.yaml
sed -i.bak 's/derekpedersen.com@gmail.com/your-email@example.com/' /tmp/cluster_issuer.runtime.yaml
kubectl apply -f /tmp/cluster_issuer.runtime.yaml
kubectl get clusterissuer letsencrypt-prod
```

## 7. Deploy Johnny 5 Alive

Choose one deploy mode.

### 7.1 Kubernetes Helm Deploy

Prepare runtime override values to avoid mutating tracked files:

```bash
cat > /tmp/johnny-5-values.runtime.yaml <<'EOF'
ingress:
  enabled: true
  className: nginx
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: your-domain.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: your-domain-example-com-tls
      hosts:
        - your-domain.example.com
EOF
```

Deploy:

```bash
helm upgrade --install johnny-5-alive johnny-5-alive/.helm -f /tmp/johnny-5-values.runtime.yaml
kubectl rollout status deployment/johnny-5-alive --timeout=5m
kubectl get ingress johnny-5-alive
```

Enable HPA in runtime overrides:

```bash
cat >> /tmp/johnny-5-values.runtime.yaml <<'EOF'
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
EOF
```

Validate HPA:

```bash
kubectl get hpa johnny-5-alive
```

### 7.2 Local Docker Deploy

```bash
cd johnny-5-alive
make run
```

App will be available at `http://localhost:9090`.

## 8. DNS and TLS Validation

For Kubernetes HTTPS path:

1. Get ingress controller load balancer address.
2. Point your domain DNS record to that address.
3. Wait for cert-manager challenge completion.

Commands:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get ingress johnny-5-alive
kubectl get certificate -A
kubectl get challenges -A
```

Endpoint checks:

```bash
curl -I http://your-domain.example.com
curl -I https://your-domain.example.com
```

Expected behavior:

1. HTTP should eventually redirect to HTTPS when ingress and chart config are fully applied.
2. HTTPS should return a valid certificate after ACME challenge succeeds.

## 9. Troubleshooting

### 9.1 Ingress Pending

Symptom:

`kubectl get ingress` shows no address.

Checks:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get ingressclass nginx
```

### 9.2 Certificate Not Issued

Checks:

```bash
kubectl get clusterissuer letsencrypt-prod -o yaml
kubectl get certificate -A
kubectl get challenges -A
kubectl logs -n cert-manager deploy/cert-manager
```

Likely causes:

1. DNS does not point to ingress load balancer.
2. Domain not publicly reachable.
3. Incorrect ingress host/tls values.

### 9.3 App Not Starting

Checks:

```bash
kubectl get pods -l app.kubernetes.io/name=johnny-5-alive
kubectl describe pod -l app.kubernetes.io/name=johnny-5-alive
kubectl logs -l app.kubernetes.io/name=johnny-5-alive
```

If image pull fails, provide a reachable image repository in your Helm overrides.

### 9.4 HPA Not Scaling

Checks:

```bash
kubectl get hpa johnny-5-alive -o yaml
kubectl top pods -l app.kubernetes.io/name=johnny-5-alive
kubectl describe hpa johnny-5-alive
```

Likely causes:

1. `metrics-server` is not healthy.
2. Workload CPU is below target.
3. HPA is not enabled in chart override values.

### 9.5 Prometheus or Grafana Unavailable

Checks:

```bash
kubectl get pods -n monitoring
kubectl get events -n monitoring --sort-by=.metadata.creationTimestamp
kubectl logs -n monitoring deployment/kube-prometheus-stack-operator
```

### 9.6 Debug Pod Not Ready

Checks:

```bash
kubectl get pod -n default johnny-5-debug
kubectl describe pod -n default johnny-5-debug
kubectl logs -n default johnny-5-debug
```

Likely causes:

1. Image is not pullable from cluster nodes.
2. Namespace mismatch between deploy and exec commands.
3. Cluster policy blocks networking tools.

## 10. Cleanup

Remove app:

```bash
helm uninstall johnny-5-alive
```

Remove infrastructure:

```bash
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall cert-manager -n cert-manager
helm uninstall metrics-server -n kube-system
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete pod johnny-5-debug -n default --ignore-not-found
```

Delete DOKS cluster:

```bash
doctl kubernetes cluster delete kube-me-up
```

## 11. Installer Mapping

`install.sh` implements this runbook in guided form:

1. Preflight checks.
2. Cluster path prompts.
3. Optional debug pod deployment.
4. Infrastructure install.
5. Optional observability install.
6. Runtime ClusterIssuer generation and apply.
7. Deploy mode prompt (Kubernetes or Docker).
8. Optional HPA runtime overrides for Kubernetes deploy mode.
9. Post-install verification summary.

### 11.1 Dry Run and Resume Flags

Use dry run to preview every command:

```bash
./install.sh --dry-run --use-existing-cluster
```

Use explicit skip flags to resume from partial progress:

```bash
# Re-run only infrastructure
./install.sh --use-existing-cluster --skip-cluster --skip-app --deploy-mode skip

# Re-run issuer + app only
./install.sh --use-existing-cluster --skip-cluster --skip-infra --deploy-mode kubernetes --email your-email@example.com --domain your-domain.example.com

# Re-run app only
./install.sh --use-existing-cluster --skip-cluster --skip-infra --skip-issuer --deploy-mode kubernetes --domain your-domain.example.com

# Install optional observability layer only
./install.sh --use-existing-cluster --with-observability --skip-cluster --skip-infra --skip-issuer --skip-app --deploy-mode skip

# Deploy standalone debug pod only
./install.sh --use-existing-cluster --deploy-mode skip --skip-infra --skip-issuer --skip-app --with-debug-pod

# Deploy standalone debug pod with custom image/namespace/name
./install.sh --use-existing-cluster --deploy-mode skip --skip-infra --skip-issuer --skip-app --with-debug-pod --debug-pod-image your-registry/johnny-5-debug:tag --debug-pod-namespace default --debug-pod-name johnny-5-debug

# Deploy app with HPA enabled
./install.sh --use-existing-cluster --skip-cluster --skip-infra --deploy-mode kubernetes --enable-hpa --hpa-min-replicas 1 --hpa-max-replicas 3 --hpa-target-cpu 80 --hpa-target-mem 80 --email your-email@example.com --domain your-domain.example.com
```

### 11.2 One-Command Demo Target

Use Makefile automation to install infra, observability, issuer, and app with HPA in one command:

```bash
make install-full-observability EMAIL=your-email@example.com DOMAIN=your-domain.example.com
```

Optional HPA tuning:

```bash
make install-full-observability \
  EMAIL=your-email@example.com \
  DOMAIN=your-domain.example.com \
  HPA_MIN_REPLICAS=1 \
  HPA_MAX_REPLICAS=3 \
  HPA_TARGET_CPU=75 \
  HPA_TARGET_MEM=80
```
