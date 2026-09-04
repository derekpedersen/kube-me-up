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

## 5. Configure and Apply ClusterIssuer

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

## 6. Deploy Johnny 5 Alive

Choose one deploy mode.

### 6.1 Kubernetes Helm Deploy

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
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
EOF
```

Validate HPA:

```bash
kubectl get hpa johnny-5-alive
```

### 6.2 Local Docker Deploy

```bash
cd johnny-5-alive
make run
```

App will be available at `http://localhost:9090`.

## 7. DNS and TLS Validation

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

## 8. Troubleshooting

### 8.1 Ingress Pending

Symptom:

`kubectl get ingress` shows no address.

Checks:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get ingressclass nginx
```

### 8.2 Certificate Not Issued

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

### 8.3 App Not Starting

Checks:

```bash
kubectl get pods -l app.kubernetes.io/name=johnny-5-alive
kubectl describe pod -l app.kubernetes.io/name=johnny-5-alive
kubectl logs -l app.kubernetes.io/name=johnny-5-alive
```

If image pull fails, provide a reachable image repository in your Helm overrides.

### 8.4 HPA Not Scaling

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

### 8.5 Prometheus or Grafana Unavailable

Checks:

```bash
kubectl get pods -n monitoring
kubectl get events -n monitoring --sort-by=.metadata.creationTimestamp
kubectl logs -n monitoring deployment/kube-prometheus-stack-operator
```

## 9. Cleanup

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
```

Delete DOKS cluster:

```bash
doctl kubernetes cluster delete kube-me-up
```

## 10. Installer Mapping

`install.sh` implements this runbook in guided form:

1. Preflight checks.
2. Cluster path prompts.
3. Infrastructure install.
4. Optional observability install.
5. Runtime ClusterIssuer generation and apply.
6. Deploy mode prompt (Kubernetes or Docker).
7. Optional HPA runtime overrides for Kubernetes deploy mode.
8. Post-install verification summary.

### 10.1 Dry Run and Resume Flags

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

# Deploy app with HPA enabled
./install.sh --use-existing-cluster --skip-cluster --skip-infra --deploy-mode kubernetes --enable-hpa --hpa-min-replicas 2 --hpa-max-replicas 10 --hpa-target-cpu 80 --email your-email@example.com --domain your-domain.example.com
```

### 10.2 One-Command Demo Target

Use Makefile automation to install infra, observability, issuer, and app with HPA in one command:

```bash
make install-full-observability EMAIL=your-email@example.com DOMAIN=your-domain.example.com
```

Optional HPA tuning:

```bash
make install-full-observability \
  EMAIL=your-email@example.com \
  DOMAIN=your-domain.example.com \
  HPA_MIN_REPLICAS=2 \
  HPA_MAX_REPLICAS=12 \
  HPA_TARGET_CPU=75
```
