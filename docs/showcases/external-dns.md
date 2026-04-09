# ExternalDNS

### Precondition

Cluster has to be deployed with the *httpbin* sample. Otherwise this demo wouldn't work.

### Components

| Component | Source |
|-----------|--------|
| etcd | Plain Kubernetes manifest (`etcd.yaml`) using `registry.k8s.io/etcd:3.5.16-0` |
| CoreDNS | Helm chart `coredns/coredns` |
| ExternalDNS | Official Helm chart `external-dns/external-dns` (`registry.k8s.io/external-dns/external-dns`) |

### Installation

```bash
cd examples/external-dns

# With HAProxy Ingress Controller (auto-detected if not set)
HAPROXY_FLAG=Yes bash setup.sh

# With Kong Gateway (Gateway API / HTTPRoute)
KONG_FLAG=Yes bash setup.sh
```

If neither flag is set, the ingress mode is auto-detected from the cluster.

ExternalDNS is configured with the CoreDNS provider. It watches Ingress resources (HAProxy mode) or HTTPRoutes (Kong mode) and writes DNS records into etcd, which CoreDNS serves.

### How it works

1. **etcd** is deployed as a single-pod Deployment — CoreDNS and ExternalDNS use it as the DNS record store.
2. **CoreDNS** is configured with the `etcd` plugin for the `example.com` zone and exposed via NodePort `30053`.
3. **ExternalDNS** watches Ingress/HTTPRoute resources and registers A records in etcd using the Ingress controller's LoadBalancer IP.
4. **HAProxy Ingress Controller** must have `publishService.enabled: true` (already set in `manifests/haproxy-helm.yaml`) so that the Ingress `.status.loadBalancer` is populated — ExternalDNS reads that IP as the DNS target.

### CoreDNS configuration

After installation the generated ConfigMap looks like this (etcd endpoint IP varies):

```yaml
apiVersion: v1
kind: ConfigMap
data:
  Corefile: |-
    .:53 {
        etcd example.com {
            stubzones
            path /skydns
            endpoint http://10.43.x.x:2379
        }
        debug
        errors
        health {
            lameduck 5s
        }
        ready
        reload
        loadbalance
    }
```

### Test DNS resolution

CoreDNS is exposed on NodePort `30053`, which k3d maps to a random host port. Look up the port with:

```bash
docker ps --format '{{.Ports}}' | grep 30053
# e.g. 0.0.0.0:49625->30053/udp
```

Then query directly from your host:

```bash
dig @localhost httpbin.example.com -p <PORT>
```

Expected answer:

```
;; ANSWER SECTION:
httpbin.example.com.  30  IN  A  172.25.0.4
```

The IP is the ClusterIP of the HAProxy LoadBalancer service (or Kong Gateway service in Kong mode).

You can also run an in-cluster test:

```bash
kubectl run -it --rm --restart=Never --image=infoblox/dnstools:latest dnstools
# Inside the container:
# nslookup httpbin.example.com <coredns-service-ip>
```
