# Sample K3d Cluster

In this small compilation, an example K3d cluster, including a local container registry, is created.

### Preconditions

You should have installed *k3d* on your system. See official installation guide: https://k3d.io/v5.4.6/#installation


### Sample Cluster incl. demo deployments

The creation of the cluster and a simple sample deployment from the local registry can be called up as follows:

```bash
bash create-sample.sh
```

### More details

The default parameters look like this:

```yaml
---
apiVersion: k3d.io/v1alpha4
kind: Simple
metadata:
  name: spielwiese
servers: 3
agents: 3
ports:
  - port: 8080:80
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
      "ocregistry.localhost":
        endpoint:
          - http://ocregistry.localhost:5002
options:
  k3d:
    wait: true

```

A cluster is created with **3 master and 3 worker** nodes. In addition, a local **registry** and an external **load balancer** are created in front of the cluster. This cluster is installed with **Calico** instead of default Flannel.

When the start script is called, an **httpbin deployment** is then carried out in the *demo* namespace. 
The container from https://kennethreitz.org/ is used here.

This pod is published via both **Ingress** and **NodePort**. So you have an example for both variants.