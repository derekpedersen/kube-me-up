IMAGE ?= johnny-5-debug:latest
NAMESPACE ?= default
POD_NAME ?= johnny-5-debug
DEBUG_REPO ?= derekpedersen/johnny-5-debug
DEBUG_TAG ?= latest

build:
	docker build -t $(IMAGE) .

publish: build
	docker tag $(IMAGE) $(DEBUG_REPO):$(DEBUG_TAG)
	docker push $(DEBUG_REPO):$(DEBUG_TAG)

run: build
	docker run --rm -it $(IMAGE)

deploy-pod:
	kubectl apply -n $(NAMESPACE) -f pod.yaml
	kubectl wait --for=condition=Ready pod/$(POD_NAME) -n $(NAMESPACE) --timeout=180s

deploy-pod-image:
	@kubectl get namespace $(NAMESPACE) >/dev/null 2>&1 || kubectl create namespace $(NAMESPACE)
	@sed "s|image: johnny-5-debug:latest|image: $(IMAGE)|" pod.yaml | kubectl apply -n $(NAMESPACE) -f -
	kubectl wait --for=condition=Ready pod/$(POD_NAME) -n $(NAMESPACE) --timeout=180s

exec:
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -- sh

delete-pod:
	kubectl delete pod $(POD_NAME) -n $(NAMESPACE) --ignore-not-found
