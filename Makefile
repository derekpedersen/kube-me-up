.PHONY: helm-repos install-ingress-nginx install-cert-manager install-metrics-server install-external-dns external-dns-verify install-observability observability-verify install-issuer deploy-app-hpa install-full-observability uninstall alive-build alive-publish alive-build-publish debug-build debug-publish debug-build-publish publish-all debug-deploy-pod debug-exec debug-delete-pod doctl-auth deploy-main ingress certs metrics-api helm-charts

HPA_MIN_REPLICAS ?= 1
HPA_MAX_REPLICAS ?= 3
HPA_TARGET_CPU ?= 80
HPA_TARGET_MEM ?= 80
ALIVE_IMAGE ?= johnny-5-alive:latest
ALIVE_REPO ?= derekpedersen/johnny-5-alive
ALIVE_TAG ?= $(shell git rev-parse --short HEAD)
DEBUG_IMAGE ?= johnny-5-debug:latest
DEBUG_NAMESPACE ?= default
DEBUG_POD_NAME ?= johnny-5-debug
DEBUG_REPO ?= derekpedersen/johnny-5-debug
DEBUG_TAG ?= $(shell git rev-parse --short HEAD)
DOKS_CLUSTER_NAME ?= kube-me-up
EXTERNAL_DNS_NAMESPACE ?= external-dns
EXTERNAL_DNS_RELEASE ?= external-dns
EXTERNAL_DNS_SECRET ?= external-dns

helm-repos:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx/
	helm repo add jetstack https://charts.jetstack.io
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
	helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update

install-ingress-nginx: helm-repos
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx --create-namespace \
		--set controller.ingressClassResource.name=nginx \
		--set controller.ingressClassResource.default=true

install-cert-manager: helm-repos
	helm upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager --create-namespace \
		--version v1.9.1 --set installCRDs=true

install-metrics-server: helm-repos
	helm upgrade --install metrics-server metrics-server/metrics-server \
		--namespace kube-system \
		--set 'args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP\,ExternalIP\,Hostname}'
	kubectl get deployment metrics-server -n kube-system
	kubectl get apiservice v1beta1.metrics.k8s.io

install-external-dns: helm-repos
	@if [ -z "$(DO_API_TOKEN)" ]; then \
		echo "DO_API_TOKEN is required. Example: make install-external-dns DO_API_TOKEN=... EXTERNAL_DNS_DOMAIN_FILTER=example.com EXTERNAL_DNS_TXT_OWNER_ID=kube-me-up"; \
		exit 1; \
	fi
	@if [ -z "$(EXTERNAL_DNS_TXT_OWNER_ID)" ]; then \
		echo "EXTERNAL_DNS_TXT_OWNER_ID is required. Example: make install-external-dns EXTERNAL_DNS_TXT_OWNER_ID=kube-me-up"; \
		exit 1; \
	fi
	@if [ -z "$(EXTERNAL_DNS_DOMAIN_FILTER)" ]; then \
		echo "WARNING: EXTERNAL_DNS_DOMAIN_FILTER not set. ExternalDNS will sync all ingress hosts it sees."; \
	fi
	kubectl get namespace $(EXTERNAL_DNS_NAMESPACE) >/dev/null 2>&1 || kubectl create namespace $(EXTERNAL_DNS_NAMESPACE)
	kubectl -n $(EXTERNAL_DNS_NAMESPACE) create secret generic $(EXTERNAL_DNS_SECRET) --from-literal=do_token="$(DO_API_TOKEN)" --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install $(EXTERNAL_DNS_RELEASE) external-dns/external-dns \
		--namespace $(EXTERNAL_DNS_NAMESPACE) \
		--set provider.name=digitalocean \
		--set env[0].name=DO_TOKEN \
		--set env[0].valueFrom.secretKeyRef.name=$(EXTERNAL_DNS_SECRET) \
		--set env[0].valueFrom.secretKeyRef.key=do_token \
		--set sources[0]=ingress \
		$(if $(EXTERNAL_DNS_DOMAIN_FILTER),--set domainFilters[0]="$(EXTERNAL_DNS_DOMAIN_FILTER)") \
		--set registry=txt \
		--set txtOwnerId="$(EXTERNAL_DNS_TXT_OWNER_ID)" \
		--set policy=sync
	kubectl rollout status deployment/$(EXTERNAL_DNS_RELEASE) -n $(EXTERNAL_DNS_NAMESPACE) --timeout=5m

external-dns-verify:
	kubectl get deployment $(EXTERNAL_DNS_RELEASE) -n $(EXTERNAL_DNS_NAMESPACE)
	kubectl get pods -n $(EXTERNAL_DNS_NAMESPACE)
	kubectl logs -n $(EXTERNAL_DNS_NAMESPACE) deployment/$(EXTERNAL_DNS_RELEASE) --tail=40
	@if [ -n "$(EXTERNAL_DNS_DOMAIN_FILTER)" ]; then \
		echo "ExternalDNS domain filter: $(EXTERNAL_DNS_DOMAIN_FILTER)"; \
	else \
		echo "ExternalDNS domain filter: not set"; \
	fi

install-observability: helm-repos
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace monitoring --create-namespace

observability-verify:
	kubectl get pods -n monitoring
	kubectl get svc -n monitoring kube-prometheus-stack-grafana
	kubectl get svc -n monitoring kube-prometheus-stack-prometheus

install-issuer:
	@if [ -z "$(EMAIL)" ]; then \
		echo "EMAIL is required. Example: make install-issuer EMAIL=you@example.com"; \
		exit 1; \
	fi
	@sed "s/derekpedersen.com@gmail.com/$(EMAIL)/" cluster_issuer.yaml | kubectl apply -f -
	kubectl get clusterissuer letsencrypt-prod

deploy-app-hpa:
	@if [ -z "$(DOMAIN)" ]; then \
		echo "DOMAIN is required. Example: make deploy-app-hpa DOMAIN=alive.example.com"; \
		exit 1; \
	fi
	@tls_secret=$$(echo "$(DOMAIN)" | tr '.' '-')-tls; \
	helm upgrade --install johnny-5-alive johnny-5-alive/.helm \
		--set ingress.enabled=true \
		--set ingress.className=nginx \
		--set ingress.hosts[0].host="$(DOMAIN)" \
		--set ingress.hosts[0].paths[0].path=/ \
		--set ingress.hosts[0].paths[0].pathType=ImplementationSpecific \
		--set ingress.tls[0].secretName="$$tls_secret" \
		--set ingress.tls[0].hosts[0]="$(DOMAIN)" \
		--set autoscaling.enabled=true \
		--set autoscaling.minReplicas=$(HPA_MIN_REPLICAS) \
		--set autoscaling.maxReplicas=$(HPA_MAX_REPLICAS) \
		--set autoscaling.targetCPUUtilizationPercentage=$(HPA_TARGET_CPU) \
		--set autoscaling.targetMemoryUtilizationPercentage=$(HPA_TARGET_MEM)
	kubectl rollout status deployment/johnny-5-alive --timeout=5m
	kubectl get ingress johnny-5-alive
	kubectl get hpa johnny-5-alive

install-full-observability: helm-charts install-observability install-issuer deploy-app-hpa observability-verify
	@echo "Full stack complete: infra + observability + issuer + app(HPA)"
	@echo "Grafana: kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"

uninstall:
	chmod +x uninstall.sh
	./uninstall.sh

alive-build:
	$(MAKE) -C johnny-5-alive build IMAGE=$(ALIVE_IMAGE)

alive-publish:
	$(MAKE) -C johnny-5-alive publish ALIVE_REPO=$(ALIVE_REPO) ALIVE_TAG=$(ALIVE_TAG)

alive-build-publish: alive-build alive-publish
	@echo "Alive image published: $(ALIVE_REPO):$(ALIVE_TAG)"

debug-build:
	$(MAKE) -C johnny-5-debug build IMAGE=$(DEBUG_IMAGE)

debug-publish:
	$(MAKE) -C johnny-5-debug publish IMAGE=$(DEBUG_IMAGE) DEBUG_REPO=$(DEBUG_REPO) DEBUG_TAG=$(DEBUG_TAG)

debug-build-publish: debug-build debug-publish
	@echo "Debug image published: $(DEBUG_REPO):$(DEBUG_TAG)"

publish-all: alive-build-publish debug-build-publish
	@echo "All images published."

debug-deploy-pod:
	$(MAKE) -C johnny-5-debug deploy-pod-image IMAGE=$(DEBUG_IMAGE) NAMESPACE=$(DEBUG_NAMESPACE) POD_NAME=$(DEBUG_POD_NAME)

debug-exec:
	kubectl exec -it -n $(DEBUG_NAMESPACE) $(DEBUG_POD_NAME) -- sh

debug-delete-pod:
	$(MAKE) -C johnny-5-debug delete-pod NAMESPACE=$(DEBUG_NAMESPACE) POD_NAME=$(DEBUG_POD_NAME)

doctl-auth:
	@if ! command -v doctl >/dev/null 2>&1; then \
		echo "doctl is required for this target"; \
		exit 1; \
	fi
	@if [ -n "$(DO_API_TOKEN)" ]; then \
		doctl auth init -t "$(DO_API_TOKEN)"; \
	else \
		echo "DO_API_TOKEN not set, using existing doctl auth context"; \
	fi
	@if [ -z "$(DOKS_CLUSTER_NAME)" ]; then \
		echo "DOKS_CLUSTER_NAME is required. Example: make doctl-auth DOKS_CLUSTER_NAME=kube-me-up"; \
		exit 1; \
	fi
	doctl kubernetes cluster kubeconfig save "$(DOKS_CLUSTER_NAME)"

deploy-main:
	$(MAKE) doctl-auth DOKS_CLUSTER_NAME="$(DOKS_CLUSTER_NAME)"
	@if [ -z "$(ALIVE_REPO)" ]; then \
		echo "ALIVE_REPO is required. Example: make deploy-main ALIVE_REPO=derekpedersen/johnny-5-alive"; \
		exit 1; \
	fi
	@if [ -z "$(ALIVE_TAG)" ]; then \
		echo "ALIVE_TAG is required. Example: make deploy-main ALIVE_TAG=$$(git rev-parse HEAD)"; \
		exit 1; \
	fi
	@if [ -z "$(DEBUG_REPO)" ]; then \
		echo "DEBUG_REPO is required. Example: make deploy-main DEBUG_REPO=derekpedersen/johnny-5-debug"; \
		exit 1; \
	fi
	@if [ -z "$(DEBUG_TAG)" ]; then \
		echo "DEBUG_TAG is required. Example: make deploy-main DEBUG_TAG=$$(git rev-parse HEAD)"; \
		exit 1; \
	fi
	helm upgrade --install johnny-5-alive johnny-5-alive/.helm \
		--set image.repository="$(ALIVE_REPO)" \
		--set image.tag="$(ALIVE_TAG)"
	$(MAKE) debug-deploy-pod DEBUG_IMAGE="$(DEBUG_REPO):$(DEBUG_TAG)" DEBUG_NAMESPACE=$(DEBUG_NAMESPACE) DEBUG_POD_NAME=$(DEBUG_POD_NAME)
	kubectl get pods -n $(DEBUG_NAMESPACE) -l app.kubernetes.io/name=johnny-5-debug
	kubectl get deployment -n $(DEBUG_NAMESPACE) -l app.kubernetes.io/name=johnny-5-alive

ingress: install-ingress-nginx

certs: install-cert-manager

metrics-api: install-metrics-server

helm-charts: install-ingress-nginx install-cert-manager install-metrics-server install-external-dns
