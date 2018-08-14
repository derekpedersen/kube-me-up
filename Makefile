build:
	docker build --no-cache ./ -t nginx-proxy

publish:
	docker tag nginx-proxy us.gcr.io/derekpedersen-195304/nginx-proxy:latest
	gcloud docker -- push us.gcr.io/derekpedersen-195304/nginx-proxy:latest

deploy: delete
	kubectl create -f ./kubernetes/deployment.yaml

delete:
	kubectl delete deployment nginx-proxy-deployment

kubernetes: build publish deploy

