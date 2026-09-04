.PHONY: helm-repos install-ingress-nginx install-cert-manager install-metrics-server install-observability observability-verify install-issuer deploy-app-hpa install-full-observability ingress certs metrics-api helm-charts

HPA_MIN_REPLICAS ?= 2
HPA_MAX_REPLICAS ?= 10
HPA_TARGET_CPU ?= 80

helm-repos:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx/
	helm repo add jetstack https://charts.jetstack.io
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
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
		--set args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP\,ExternalIP\,Hostname}
	kubectl get deployment metrics-server -n kube-system
	kubectl get apiservice v1beta1.metrics.k8s.io

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
		--set autoscaling.targetCPUUtilizationPercentage=$(HPA_TARGET_CPU)
	kubectl rollout status deployment/johnny-5-alive --timeout=5m
	kubectl get ingress johnny-5-alive
	kubectl get hpa johnny-5-alive

install-full-observability: helm-charts install-observability install-issuer deploy-app-hpa observability-verify
	@echo "Full stack complete: infra + observability + issuer + app(HPA)"
	@echo "Grafana: kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"

ingress: install-ingress-nginx

certs: install-cert-manager

metrics-api: install-metrics-server

helm-charts: install-ingress-nginx install-cert-manager install-metrics-server
