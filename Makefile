.PHONY: helm-repos install-ingress-nginx install-cert-manager install-metrics-server ingress certs metrics-api helm-charts

helm-repos:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx/
	helm repo add jetstack https://charts.jetstack.io
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
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

ingress: install-ingress-nginx

certs: install-cert-manager

metrics-api: install-metrics-server

helm-charts: install-ingress-nginx install-cert-manager install-metrics-server
