# Kube Me Up

Kube Me Up is a script-first path from fresh cluster to live HTTPS traffic.

It installs ingress, TLS automation, metrics, and a sample app.

The Helm-based install and uninstall flows are Kubernetes-provider agnostic for existing clusters, so they work across AKS, EKS, GKE, DOKS, and similar environments. Automatic cluster creation is still DOKS-first.

Repo guidance for automation lives in [AGENTS.md](AGENTS.md). Manual recovery steps live in [RUNBOOK.md](RUNBOOK.md).

## What You Get

1. `ingress-nginx` for routing
2. `cert-manager` + ClusterIssuer for TLS
3. `metrics-server` for `kubectl top` and HPA inputs
4. Optional `kube-prometheus-stack` for Prometheus and Grafana
5. Optional HPA tuning for `johnny-5-alive`
6. Optional standalone debug pod in `johnny-5-debug`

## Quick Start

Existing cluster (recommended):

```bash
chmod +x install.sh
./install.sh --use-existing-cluster
```

Preview only (no changes):

```bash
./install.sh --dry-run --use-existing-cluster
```

Full stack with observability + HPA:

```bash
./install.sh \
    --use-existing-cluster \
    --deploy-mode kubernetes \
    --with-observability \
    --enable-hpa \
    --hpa-min-replicas 1 \
    --hpa-max-replicas 3 \
    --hpa-target-cpu 80 \
    --hpa-target-mem 80 \
    --domain alive.example.com \
    --email you@example.com
```

## Common Workflows

Pod-only debug deploy (no app/ingress):

```bash
./install.sh \
    --use-existing-cluster \
    --deploy-mode skip \
    --skip-infra \
    --skip-issuer \
    --skip-app \
    --with-debug-pod
```

Observability only:

```bash
./install.sh --use-existing-cluster --with-observability --deploy-mode skip --skip-app
```

Resume app deploy only:

```bash
./install.sh --use-existing-cluster --skip-cluster --skip-infra --skip-issuer --deploy-mode kubernetes
```

## Uninstall

Preview the cleanup path:

```bash
./uninstall.sh --dry-run
```

Remove the managed stack from the current cluster:

```bash
chmod +x uninstall.sh
./uninstall.sh
```

Delete the DOKS cluster too:

```bash
./uninstall.sh --delete-cluster --yes
```

## Makefile Shortcuts

Full demo stack:

```bash
make install-full-observability EMAIL=you@example.com DOMAIN=alive.example.com
```

Debug image and pod:

```bash
make debug-build
make debug-build-publish
make debug-deploy-pod
make debug-exec
```

Cleanup:

```bash
make uninstall
```

HPA tuning via Makefile vars:

```bash
make install-full-observability \
    EMAIL=you@example.com \
    DOMAIN=alive.example.com \
    HPA_MIN_REPLICAS=1 \
    HPA_MAX_REPLICAS=3 \
    HPA_TARGET_CPU=75 \
    HPA_TARGET_MEM=80
```

## Debug Workload

`johnny-5-debug` is separate from `johnny-5-alive` and built for exec-heavy testing.

Included tools: `kubectl`, `helm`, `yq`, `curl`, `wget`, `nc`, `dig`, `ping`, `iproute2`, `tcpdump`, `jq`, `openssl`.

## Verify

```bash
kubectl get nodes
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get clusterissuer letsencrypt-prod
kubectl get ingress johnny-5-alive
kubectl get hpa johnny-5-alive
kubectl get certificate -A
kubectl get challenges -A
kubectl get pods -n monitoring
kubectl get pod johnny-5-debug -n default
```

## Prerequisites

- `kubectl`
- `helm`
- `docker`
- `make`
- `git`
- `doctl` (only for installer-managed DOKS cluster creation)

For deep troubleshooting and manual recovery, use [RUNBOOK.md](RUNBOOK.md).
