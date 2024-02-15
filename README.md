# K3d Bootstrap Cluster

This project creates an k3d demo cluster. It comes with an interactive setup, which allows you to setup a Kubernetes cluster for demo and showcase purposes.

### Preconditions

- You should have installed *k3d* with it's dependencies on your system. See official installation guide: https://k3d.io/v5.5.1/#installation
  - Min k3d version: v5.5.1

- For the [Manual examples](#Manual examples) you should have installed HELM > 3.0. See official installation guide: https://helm.sh/docs/intro/install/
- jq needs to be installed on your system. See official installation guide:https://stedolan.github.io/jq/download/
- For Confluent (Kafka/Schema-Registry) it'S necessary to assign 16GB RAM to Docker, otherwise it won't deploy successfully

### Sample Cluster incl. demo deployments

The creation of the cluster and a simple sample deployment from the local registry can be called up as follows:

:warning:  If a cluster with the same name already exists, it will be deleted before recreating it!

```bash
bash create-sample.sh
# sudo rights are needed, cause the script adds an dummy entry for the registry to /etc/hosts
# you will be asked for your users password
```

You will be asked some questions about the cluster deployment, like numer of nodes, Ingress ports and the deployment of **Calico CNI** instead of default Flannel installation. It's also possible to deploy **NGINX Ingress Controller** instead of Traefik.

At least you have the option to deploy **httpbin sample deployment**, which is deployed to the namespace *demo*.
The container from https://kennethreitz.org/ is used here. The sample uses the Ingress, also a *NodePort* is exposed, to demonstrate this in k3d. A PVC is created and mounted to the httpbin container.
The httpbin demo is deployed from the **local running container registry**, just for demo purpose, to show the usage of a user defined registry with k3d.

*Optional (K8s > 1.24 needed):* Kubernetes Dashboard can be deployed on your sample cluster. After successful deployment you can browse the [dashboard](https://dashboard.127-0-0-1.nip.io:8081/#/login). The nessecary login token you can get with the following command: `kubectl -n k8s-dashboard describe secrets dashboard-admin-token | grep token:`

After running this script you can visit the Demo HTTPBin Application by typing `127-0-0-1.nip.io:<Load-Balancer-Port>` in your Browser. If you are using an other `DEMO_DOMAIN` you can use `<Cluster-Name>.<DEMO_DOMAIN>:<Load-Balancer-Port>` (e.q. `demo.example.com:8080`).

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
  - port: <RANDOM PORT>:30001
    nodeFilters:
      - agents:*
  - port: <RANDOM PORT>:30053/udp
    nodeFilters:
      - servers:*
  - port: <RANDOM PORT>:30053/tcp
    nodeFilters:
      - servers:*
registries:
  create:
    name: registry.localhost
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

## Manual examples

There are some samples included, which are not deployed automatically. They are useful to demonstrate the usage of some commonly used Kubernetes tools.

Samples included under the **examples** folder:

- ExternalDNS - https://github.com/kubernetes-sigs/external-dns

  - Intallation is documented here [README](examples/external-dns/README.md)
- Vault https://github.com/hashicorp/vault & cert-manager https://github.com/cert-manager/cert-manager
  - Installation is documented here [README](examples/vault/README.md)
- External Secrets Operator (ESO) - https://github.com/external-secrets/external-secrets
  - Installation is documented here [README](examples/external-secrets/README.md)
- Kong API Gateway (Enterprise) - https://github.com/Kong/kong
  - Installation is documented here [README](examples/kong-gateway/README.md)
- Kuma Service Mesh - https://github.com/kumahq/kuma
  - Installation is documented here [README](examples/kuma-mesh/README.md)
- Confluent for Kubernetes (Kafka + Schema Registry) - https://docs.confluent.io/operator/current/overview.html
  - Installation is documented here [README](examples/confluent/README.md)


### Troubleshooting

This k3d cluster deployment uses **nip.io** DNS resolution for demo purposes. DNS names for registry and demo Ingresses are resolved to local IP. Example: registry.127-0-0-1.nip.io is resolved to static IP 127.0.0.1.

**Caution:** In some cases your network-router doesn't allow to resolve IPs of your own, or private IP address range. As a workaround you can change the ENV variable `DEMO_DOMAIN` in *helpers.sh*. This will automatically add the registry entry in your local /etc/hosts file. But it doesn't add any sample Ingress hostnames to your local /etc/hosts, you have to do this manually.
