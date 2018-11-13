export GIT_COMMIT_SHA = $(shell git rev-parse HEAD)

build:
	docker build --no-cache ./ -t nginx-proxy

publish:
	docker tag nginx-proxy us.gcr.io/${GCLOUD_PROJECT_ID}/nginx-proxy:${GIT_COMMIT_SHA}
	gcloud docker -- push us.gcr.io/${GCLOUD_PROJECT_ID}/nginx-proxy:${GIT_COMMIT_SHA}

deploy:
	sed -e 's/%GCLOUD_PROJECT_ID%/${GCLOUD_PROJECT_ID}/g' -e 's/%GIT_COMMIT_SHA%/${GIT_COMMIT_SHA}/g' ./kubernetes/deployment.yaml > deployment.sed.yaml
	kubectl apply -f ./deployment.sed.yaml
	kubectl apply -f ./kubernetes/service.yaml

kubernetes: build publish deploy