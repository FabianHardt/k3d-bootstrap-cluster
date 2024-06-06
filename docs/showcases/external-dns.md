# ExternalDNS

### Precondition

Cluster has to be deployed with the *httpbin* sample. Otherwise this demo wouldn't work.

### Installation

With this small script an etc, coredns and ExternalDNS is installed:

```bash
# Installation of etcd, coredns and ExternalDNS
cd examples/external-dns
bash setup.sh

# Test DNS queries with test container
kubectl run -it --rm --restart=Never --image=infoblox/dnstools:latest dnstools

# Answer - should be something sililar to this:
Name:	httpbin.example.com
Address: 172.21.0.5
Name:	httpbin.example.com
Address: 172.21.0.6
Name:	httpbin.example.com
Address: 172.21.0.7
Name:	httpbin.example.com
Address: 172.21.0.4
Name:	httpbin.example.com
Address: 172.21.0.8
Name:	httpbin.example.com
Address: 172.21.0.3
```

CoreDNS will have the following config after installation - where the IP is the service IP of the etcd installation:

```yaml
apiVersion: v1
data:
  Corefile: |-
    .:53 {
        etcd example.com {
            stubzones
            path /skydns
            endpoint http://10.43.60.159:2379
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
kind: ConfigMap
metadata:
  annotations:
    meta.helm.sh/release-name: coredns
    meta.helm.sh/release-namespace: dns-sample
  labels:
    app.kubernetes.io/instance: coredns
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: coredns
    helm.sh/chart: coredns-1.19.5
    k8s-app: coredns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: CoreDNS
  name: coredns-coredns
  namespace: dns-sample
```

After successful installation DNS is exposed to your host via NodePort 30053. You can test the DNS resoltion directly on your host:

```bash
# Look for the right port (external Docker port) in your Docker environment
# "docker ps", then look for loadbalancer container
dig @localhost httpbin.example.com -p <RANDOM PORT>
```

