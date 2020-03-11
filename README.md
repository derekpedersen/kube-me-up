# GKE Nginx Ingress Controller #

This project contains the definitions for the GKE Nginx Ingress controller.

## Deployment via Helm ##

This project utilizes the Helm chart for installing the Nginx Ingress Controller.

### install ###

`helm install nginx-ingress stable/nginx-ingress --set controller.publishService.enabled=true`

### upgrade ###

`helm upgrade nginx-ingress stable/nginx-ingress --set controller.publishService.enabled=true`

## Cert Manager ##

https://github.com/jetstack/cert-manager

https://cert-manager.io/docs/installation/kubernetes/

### cluster issuer ###

This is needed to know where to get the certificates from.

## New Site ##

Here are the steps to adding a new site:

1. Deploy the applications via their own helm charts
2. Add a `rules` entry to the [ingress.yaml file](ingress.yaml)
    ```yaml
    - host: pedersen.io
    http:
      paths:
      - backend:
          serviceName: dp-spa-vue-test
          servicePort: 80
        path: /
    ```
3. `kubectl apply -f ingress.yaml` 
4. Your application should now be exposed to the interwebs!    

