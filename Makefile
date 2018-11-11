build:
	docker build --no-cache ./ -t nginx-proxy

publish:
	docker tag nginx-proxy us.gcr.io/${GCLOUD_PROJECT_ID}/nginx-proxy:latest
	gcloud docker -- push us.gcr.io/${GCLOUD_PROJECT_ID}/nginx-proxy:latest

delete:
	kubectl delete deployment nginx-proxy-deployment

kubernetes: build publish deploy

deploy:
	sed -e 's/%GCLOUD_PROJECT_ID%/${GCLOUD_PROJECT_ID}/g' ./deployment.yaml > deployment.sed.yaml
	kubectl apply -f ./deployment.sed.yaml
	kubectl apply -f ./kubernetes/service.yaml