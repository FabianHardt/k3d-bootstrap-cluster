# HAProxy Ingress Controller

[HAProxy Ingress](https://haproxy-ingress.github.io) is an Ingress controller implementation for Kubernetes built on top of HAProxy.

The cluster's default ingress is **Kong Gateway (Gateway API)**. This showcase installs HAProxy Ingress as an additional, secondary ingress class so that you can experiment with classic `Ingress` resources alongside the Gateway API setup.

### Precondition

A running k3d-bootstrap-cluster (Kong Gateway is already installed by `create-sample.sh`).

### Installation

```bash
cd examples/haproxy
bash setup.sh
```

The script installs:

- Namespace `ingress-haproxy`
- `IngressClass` named `haproxy` (non-default — Kong remains the cluster default)
- HAProxy Ingress Controller Helm chart (version `0.14.7`)

### Usage

HAProxy will only handle Ingress resources that explicitly select its `IngressClass`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: demo
spec:
  ingressClassName: haproxy
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

Traffic still enters the cluster through the same loadbalancer ports (`8080` / `8081`) configured at bootstrap. HAProxy and Kong share the cluster but route only the resources they own (`IngressClass` for HAProxy, `Gateway` / `HTTPRoute` for Kong).

### Uninstall

```bash
helm uninstall haproxy-ingress -n ingress-haproxy
kubectl delete ingressclass haproxy
kubectl delete namespace ingress-haproxy
```
