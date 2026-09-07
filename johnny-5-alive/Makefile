export GIT_COMMIT_SHA = $(shell git rev-parse HEAD)
ALIVE_REPO ?= derekpedersen/johnny-5-alive

build:
	docker build ./ -t johnny-5-alive:latest --no-cache

run: build
	docker run -d -p 9090:8080 johnny-5-alive:latest

docker:
	docker build ./ -t johnny-5-alive:latest --no-cache

publish: docker
	docker tag johnny-5-alive $(ALIVE_REPO):$(GIT_COMMIT_SHA)
	docker push $(ALIVE_REPO):$(GIT_COMMIT_SHA)

set-version:
	.helm/set-version.sh

deploy: set-version
	helm upgrade johnny-5-alive .helm

kubernetes: build publish deploy