# GKE Nginx Ingress Controller #

This project contains the definitions for the GKE Nginx Ingress controller.

## Deployment via Helm ##

This project utilizes the Helm chart for installing the Nginx Ingress Controller.

### install ###

`helm install nginx-ingress stable/nginx-ingress --set controller.publishService.enabled=true`

### upgrade ###

`helm upgrade nginx-ingress stable/nginx-ingress --set controller.publishService.enabled=true`
