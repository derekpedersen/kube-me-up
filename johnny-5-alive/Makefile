build:
	docker build ./ -t johnny-5-alive:latest --no-cache

run: build
	docker-compose up -d

http-deploy:
	helm install johnny-5-http .helm/http

https-deploy:
	helm install johnny-5-https .helm/https

set-version:
	.helm/set-version.sh