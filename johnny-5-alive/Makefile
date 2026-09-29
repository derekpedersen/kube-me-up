export GIT_COMMIT_SHA = $(shell git rev-parse HEAD)
ALIVE_REPO ?= derekpedersen/johnny-5-alive
ALIVE_TAG ?= $(GIT_COMMIT_SHA)

build:
	docker build ./ -t johnny-5-alive:latest --no-cache

run: build
	docker run -d -p 9090:8080 johnny-5-alive:latest

docker: build

publish: docker
	docker tag johnny-5-alive $(ALIVE_REPO):$(ALIVE_TAG)
	docker push $(ALIVE_REPO):$(ALIVE_TAG)

set-version:
	.helm/set-version.sh

deploy: set-version
	helm upgrade johnny-5-alive .helm

kubernetes: build publish deploy