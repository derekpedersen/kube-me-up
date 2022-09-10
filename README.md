# Kube-Me-Up 

Kube Me Up!

This project is all about being able to quickly spin up a `kubernetes-scluster` with all the tools necessary to start handling web traffic. 

## GKE

The docs for getting started with `GKE` can be found [here](https://cloud.google.com/kubernetes-engine/docs/deploy-app-cluster).

## EKS

The docs for getting started with `EKS` can be found [here](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html).

## Ingress Nginx

`ingress-nginx` allows us to configure an HTTP load balanger for applications running on our `kubernetes-cluster`.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && \
  helm repo update && \
  helm install quickstart ingress-nginx/ingress-nginx
```

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

The `cert-manager` can be installed following these [instructions](https://cert-manager.io/docs/installation/helm/).

```bash
helm repo add jetstack https://charts.jetstack.io && \
  helm repo update && \
  helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.9.1 --set installCRDs=true
```

Should give you a response similar to,

```bash
NAME: cert-manager
LAST DEPLOYED: Sun Aug 28 10:46:13 2022
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
cert-manager v1.9.1 has been deployed successfully!

In order to begin issuing certificates, you will need to set up a ClusterIssuer
or Issuer resource (for example, by creating a 'letsencrypt-staging' issuer).

More information on the different types of issuers and how to configure them
can be found in our documentation:

https://cert-manager.io/docs/configuration/

For information on how to configure cert-manager to automatically provision
Certificates for Ingress resources, take a look at the `ingress-shim`
documentation:

https://cert-manager.io/docs/usage/ingress/
```

Then run `kubectl apply -f cluster_issuer.yaml` to create the `ClusterIssuer`.

[Quickstart](https://cert-manager.io/docs/tutorials/acme/nginx-ingress/) for working with `nginx ingress`.

And if we use the `ingress` annotations as mentioned above we can make it a bit more dynamic.

```bash
kubectl get ingresses
NAME                   CLASS    HOSTS                      ADDRESS          PORTS     AGE
celebrityskateboards   <none>   celebrityskateboards.com   35.227.178.140   80, 443   23h
johnny-5-alive         <none>   alive.pedersen.io          35.227.178.140   80, 443   23h
pedersen-spa           <none>   pedersen.io                35.227.178.140   80, 443   24h
skatepark-api          <none>   celebrityskateboards.com   35.227.178.140   80, 443   24h
```
And we can now service `SSL` traffice for those hosts. 