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

The setup script auto-detects your ingress controller and configures access accordingly.

**With an ingress controller (HAProxy, Traefik, or Kong):**

The Headlamp UI is exposed via `Ingress` or `HTTPRoute`. Open it in a browser: https://dashboard.127-0-0-1.nip.io:8081/

**Without an ingress controller:**

Use a port-forward instead:

```bash
kubectl port-forward -n kube-system svc/headlamp 8080:80
```

Then open: http://localhost:8080