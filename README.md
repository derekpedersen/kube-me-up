# Kube Me Up

Kube Me Up is a script-first path from fresh cluster to live HTTPS traffic.

It installs ingress, DNS automation, TLS automation, metrics, and a sample app.

The Helm-based install and uninstall flows are Kubernetes-provider agnostic for existing clusters, so they work across AKS, EKS, GKE, DOKS, and similar environments. Automatic cluster creation is still DOKS-first.

Repo guidance for automation lives in [AGENTS.md](AGENTS.md). Manual recovery steps live in [RUNBOOK.md](RUNBOOK.md).

## What You Get

1. `ingress-nginx` for routing
2. `external-dns` for automatic DNS records from ingress hosts
3. `cert-manager` + ClusterIssuer for TLS
4. `metrics-server` for `kubectl top` and HPA inputs
5. Optional `kube-prometheus-stack` for Prometheus and Grafana
6. Optional HPA tuning for `johnny-5-alive`
7. Optional standalone debug pod in `johnny-5-debug`

## Script Layout

This repo is intentionally split by responsibility:

| Script | Scope | Installs / Runs |
|---|---|---|
| [install.sh](install.sh) | root orchestrator | Calls the shared infra installers and then the app/debug installers in order |
| [k8s-tools/nginx.install.sh](k8s-tools/nginx.install.sh) | shared infra | ingress-nginx |
| [k8s-tools/external-dns.install.sh](k8s-tools/external-dns.install.sh) | shared infra | ExternalDNS (DigitalOcean provider) |
| [k8s-tools/cert-manager.install.sh](k8s-tools/cert-manager.install.sh) | shared infra | cert-manager |
| [k8s-tools/metrics.install.sh](k8s-tools/metrics.install.sh) | shared infra | metrics-server for `kubectl top` and HPA inputs |
| [k8s-tools/issuer.install.sh](k8s-tools/issuer.install.sh) | shared infra | LetsEncrypt ClusterIssuer |
| [k8s-tools/johnny-5-alive.install.sh](k8s-tools/johnny-5-alive.install.sh) | app installer | deploys the sample app |
| [johnny-5-debug/install.sh](johnny-5-debug/install.sh) | debug-local | deploys the standalone debug pod |

## Quick Start

Use the root orchestrator to run the full flow:

```bash
chmod +x install.sh
./install.sh --use-existing-cluster
```

Required environment variables for ExternalDNS:

```bash
export DO_API_TOKEN="your-digitalocean-api-token"
export EXTERNAL_DNS_TXT_OWNER_ID="kube-me-up"
```

Recommended for safer DNS scoping:

```bash
export EXTERNAL_DNS_DOMAIN_FILTER="example.com"
```

Install one shared component directly:

```bash
chmod +x k8s-tools/nginx.install.sh
./k8s-tools/nginx.install.sh
```

Install ExternalDNS directly:

```bash
chmod +x k8s-tools/external-dns.install.sh
./k8s-tools/external-dns.install.sh
```

Deploy just the app:

```bash
chmod +x k8s-tools/johnny-5-alive.install.sh
./k8s-tools/johnny-5-alive.install.sh --domain alive.example.com
```

Deploy just the debug pod:

```bash
chmod +x johnny-5-debug/install.sh
./johnny-5-debug/install.sh --use-existing-cluster
```

Preview only (no changes):

```bash
./install.sh --dry-run --use-existing-cluster
```

Optional full stack variation with app-specific settings:

```bash
./install.sh \
    --use-existing-cluster \
    --deploy-mode kubernetes \
    --domain alive.example.com \
    --email you@example.com
```

Optional observability stack:

```bash
./install.sh --use-existing-cluster --with-observability --skip-app --skip-debug
```

## Common Workflows

Install only shared infrastructure:

```bash
./install.sh --use-existing-cluster --skip-app --skip-debug
```

Install only shared infrastructure and verify ExternalDNS:

```bash
make helm-charts DO_API_TOKEN=$DO_API_TOKEN EXTERNAL_DNS_DOMAIN_FILTER=example.com EXTERNAL_DNS_TXT_OWNER_ID=kube-me-up
make external-dns-verify EXTERNAL_DNS_DOMAIN_FILTER=example.com
```

Deploy the app only:

```bash
./install.sh --use-existing-cluster --skip-infra --skip-issuer --skip-debug
```

Deploy the debug pod only:

```bash
./install.sh --use-existing-cluster --skip-infra --skip-issuer --skip-app
```

Resume app deployment after the cluster and infra are ready:

```bash
./install.sh --use-existing-cluster --skip-infra --skip-issuer --deploy-mode kubernetes
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
kubectl get deployment external-dns -n external-dns
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

Required env vars for mandatory ExternalDNS shared infra:

- `DO_API_TOKEN`
- `EXTERNAL_DNS_TXT_OWNER_ID`

Recommended env var for scoped DNS management:

- `EXTERNAL_DNS_DOMAIN_FILTER`

For deep troubleshooting and manual recovery, use [RUNBOOK.md](RUNBOOK.md).
