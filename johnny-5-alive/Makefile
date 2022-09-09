build:
	docker build ./ -t johnny-5-alive:latest --no-cache

run: build
	docker-compose up -d

deploy:
	helm upgrade johnny-5-http .helm

set-version:
	.helm/set-version.sh