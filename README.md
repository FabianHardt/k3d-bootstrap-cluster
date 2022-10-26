# Sample K3d Cluster

This project creates an k3d demo cluster. It comes with an interactive setup, which allows you to setup a Kubernetes cluster for demo and showcase purposes.

### Preconditions

You should have installed *k3d* with it's dependencies on your system. See official installation guide: https://k3d.io/v5.4.6/#installation


### Sample Cluster incl. demo deployments

The creation of the cluster and a simple sample deployment from the local registry can be called up as follows:

```bash
bash create-sample.sh
```

You will be asked some questions about the cluster deployment, like numer of nodes, Ingress ports and the deployment of **Calico CNI** instead of default Flannel installation. It's also possible to deploy **NGINX Ingress Controller** instead of Traefik.

At least you have the option to deploy **httpbin sample deployment**, which is deployed to the namespace *demo*.
The container from https://kennethreitz.org/ is used here. The sample uses the Ingress, also a *NodePort* is exposed, to demonstrate this in k3d. A PVC is created and mounted to the httpbin container.
The httpbin demo is deployed from the **local running container registry**, just for demo purpose, to show the usage of a user defined registry with k3d.

### More details

The default parameters look like this:

```yaml
---
apiVersion: k3d.io/v1alpha4
kind: Simple
metadata:
  name: demo
servers: 1
agents: 1
ports:
  - port: 8080:80
    nodeFilters:
      - loadbalancer
  - port: 8081:443
    nodeFilters:
      - loadbalancer
  - port: 30001:30001
    nodeFilters:
      - agents:*
registries:
  create:
    name: ocregistry.localhost
    host: "0.0.0.0"
    hostPort: "5002"
  config: |
    mirrors:
      "registry.localhost":
        endpoint:
          - http://registry.localhost:5002
options:
  k3d:
    wait: true

```

## Manual samples

There are some samples included, which are not deployed automatically. They are useful to demonstrate the usage of some commonly used Kubernetes tools.

Samples included under the **examples** folder:

- ExternalDNS - https://github.com/kubernetes-sigs/external-dns

  - Intallation is documented [here - README](examples/external-dns/README.md)
