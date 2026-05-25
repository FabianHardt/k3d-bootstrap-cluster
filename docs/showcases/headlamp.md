# Headlamp Kubernetes Dashboard

### Description

[Headlamp](https://headlamp.dev/) is a web-based Kubernetes dashboard. It provides an intuitive interface for managing and monitoring Kubernetes clusters, allowing users to visualize cluster resources, view logs, and perform various administrative tasks. In this showcase, we will deploy Headlamp on our k3d cluster to demonstrate how it can be used for cluster inspection and management. More details here:

- https://headlamp.dev/docs/latest/
- https://github.com/kubernetes-sigs/headlamp

### Installation

You can install Headlamp with the following startup command:

```bash
cd examples/headlamp
bash setup.sh
```

A token for logging in to the dashboard can be created with the following command:

```bash
kubectl create token headlamp --namespace kube-system
```

### Show Headlamp UI

The Headlamp UI is exposed via `Ingress` or `HTTPRoute`, you can open Headlamp in a browser of your choice: https://dashboard.127-0-0-1.nip.io:8081/