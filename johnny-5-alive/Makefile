export GIT_COMMIT_SHA = $(shell git rev-parse HEAD)

build:
	docker build ./ -t johnny-5-alive:latest --no-cache

run: build
	docker-compose up -d

docker:
	docker build ./ -t johnny-5-alive:latest --no-cache

publish: docker
	docker tag johnny-5-alive us.gcr.io/sleipnir/johnny-5-alive:${GIT_COMMIT_SHA}
	gcloud docker -- push us.gcr.io/sleipnir/johnny-5-alive:${GIT_COMMIT_SHA}

set-version:
	.helm/set-version.sh

deploy: set-version
	helm upgrade johnny-5-alive .helm

kubernetes: build publish deploy