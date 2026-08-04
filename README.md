# Kube-Me-Up 

Kube Me Up!

This project is all about being able to quickly spin up a `kubernetes-cluster` with all the tools necessary to start handling web traffic. 

## GKE

The docs for getting started with `GKE` can be found [here](https://cloud.google.com/kubernetes-engine/docs/deploy-app-cluster).

## EKS

The docs for getting started with `EKS` can be found [here](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html).

## DOKS

The docs for getting started with `DOKS` can be found [here](https://docs.digitalocean.com/products/kubernetes/how-to/create-clusters/).

If you are using the DigitalOcean CLI, the basic cluster creation flow is:

```bash
doctl kubernetes cluster create <cluster-name> --region <region> --version <version> --node-pool "name=<pool-name>;size=s-2vcpu-4gb;count=3"
```

Once the cluster is ready, configure kubectl with:

```bash
doctl kubernetes cluster kubeconfig save <cluster-name>
```

### DOKS-specific notes

- DOKS works with the repo’s existing `johnny-5-alive` Helm chart and `cluster_issuer.yaml`.
- The Helm chart default ingress settings use `ingress.className: nginx`, which matches the standard DOKS nginx ingress controller.
- `cert-manager` HTTP01 challenge should work on DOKS as long as the nginx ingress controller is installed and reachable.
- The app’s ingress will expose a DigitalOcean LoadBalancer IP, which you can point your DNS records at.

## Ingress Nginx

`ingress-nginx` allows us to configure an HTTP load balancer for applications running on our `kubernetes-cluster`.

On DOKS, install the nginx ingress controller and register the `nginx` class:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && \
  helm repo update && \
  helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.ingressClassResource.name=nginx \
    --set controller.ingressClassResource.default=true
```

If you prefer the upstream manifest:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.1/deploy/static/provider/cloud/deploy.yaml
```

The chart and app defaults in this repo use `ingressClassName: nginx`, which is compatible with DOKS when the controller is installed this way.

```bash
NAME: quickstart
LAST DEPLOYED: Thu Sep  8 17:29:06 2022
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
It may take a few minutes for the LoadBalancer IP to be available.
You can watch the status by running 'kubectl --namespace default get services -o wide -w quickstart-ingress-nginx-controller'

An example Ingress that makes use of the controller:
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: example
    namespace: foo
  spec:
    ingressClassName: nginx
    rules:
      - host: www.example.com
        http:
          paths:
            - pathType: Prefix
              backend:
                service:
                  name: exampleService
                  port:
                    number: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
      - hosts:
        - www.example.com
        secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encoded key>
  type: kubernetes.io/tls
```

```bash
helm list
NAME                    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                                   APP VERSION                             
quickstart              default         1               2022-09-08 17:29:06.468490172 -0700 PDT deployed        ingress-nginx-4.2.5                     1.3.1                                   
```

```bash
kubectl get services
NAME                                            TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                      AGE
quickstart-ingress-nginx-controller             LoadBalancer   10.84.10.54    35.227.178.140   80:30912/TCP,443:32330/TCP   40h
quickstart-ingress-nginx-controller-admission   ClusterIP      10.84.15.49    <none>           443/TCP                      40h
```

We can now update a `DNS` entry to point to `35.227.178.140`.

## Cert-Manager

`cert-manager` is a cloud native certificate manager that allows the `kubernetes-cluster` to seamlessly handle and enforce SSL.

On DOKS, install `cert-manager` with Helm and its CRDs:

```bash
helm repo add jetstack https://charts.jetstack.io && \
  helm repo update && \
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --version v1.9.1 --set installCRDs=true
```

After install, verify the cert-manager pods are running:

```bash
kubectl get pods -n cert-manager
```

Then apply the issuer manifest from this repo:

```bash
kubectl apply -f cluster_issuer.yaml
```

The `cluster_issuer.yaml` in this repo uses ACME HTTP01 with the nginx ingress solver:

```yaml
spec:
  acme:
    solvers:
    - http01:
        ingress:
          class: nginx
```

That is compatible with DOKS when the nginx ingress controller is installed and the ingress class is set to `nginx`.

For DOKS, confirm the `johnny-5-alive` Helm ingress values include the cluster issuer annotation and nginx class:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

Then verify ingress and TLS state:

```bash
kubectl get ingress
kubectl get clusterissuer letsencrypt-prod
kubectl describe certificate
```

[Quickstart](https://cert-manager.io/docs/tutorials/acme/nginx-ingress/) for working with `nginx ingress`.
