# derekpedersen.com nginx proxy #

# Docker

## Build
- docker build ./ -t nginx-proxy

## Run
- docker run -d --rm -it -p 80:80 --name=nginx-proxy-container -t nginx-proxy

## GCR
- docker tag nginx-proxy us.gcr.io/derekpedersen-195304/nginx-proxy:latest
- gcloud docker -- push us.gcr.io/derekpedersen-195304/nginx-proxy:latest

# Kubernetes

## kube-cert-manager

This project relies on the kube-cert-manager for managing lets encrypt.

You'll need to create the certificate secret definitions
```
kubectl create -f ./certificate-derekpedersen-io.yaml
```

# Adding a site

1. Create a cloud dns entry.
2. Create a certificate for the domain.
    ```
    kubectl create -f ./kubernetes/certificate-derekpedersen-io.yaml
    ```
3. Create a nginx site entry. 
4. Run `make build && make publish`
5. Update the kubernetes deployment file to have the certificates mounted on the image.
5. Apply the updated deployment.
    ```
    kubectl create -f ./kubernetes/deployment.yaml
    ```


## derekpedersen.com
Expects api to be on port 8080.