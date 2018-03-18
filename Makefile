build:
	docker build ./ -t nginx-proxy

publish:
	docker tag nginx-proxy us.gcr.io/derekpedersen-195304/nginx-proxy:latest
	gcloud docker -- push us.gcr.io/derekpedersen-195304/nginx-proxy:latest

deploy:
	kubectl delete deployment nginx-proxy-deployment
	kubectl create -f ./kubernetes/deployment.yaml

delete:
	kubectl delete deployment nginx-proxy-deployment