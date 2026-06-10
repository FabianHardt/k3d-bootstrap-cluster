# What is K3d Bootstrap Cluster?

This project creates an k3d demo cluster. It comes with an interactive setup, which allows you to setup a Kubernetes cluster for demo and showcase purposes.

`k3d-bootstrap-cluster` uses [k3d](https://github.com/k3d-io/k3d) as base.

## Optional components

During interactive setup (`bash create-sample.sh`) you can choose the following optional components:

| Component | Default | Description |
|-----------|---------|-------------|
| **Kong Gateway (Gateway API)** | No | Replaces Traefik. Installs Gateway API CRDs v1.5.1, Kong Ingress Controller (v3.5.6) and a `GatewayClass`/`Gateway`. httpbin is exposed via `HTTPRoute`. Mutually exclusive with HAProxy. |
| **HAProxy Ingress Controller** | Yes | Replaces Traefik. httpbin is exposed via a standard `Ingress` resource. Mutually exclusive with Kong. |
| **Cilium CNI** | Yes | Replaces Flannel. eBPF-based networking with Kubernetes NetworkPolicy support. Mutually exclusive with Calico. |
| **Calico CNI** | No | Replaces Flannel. Enables Kubernetes NetworkPolicy support (needed for the Calico NetworkPolicies showcase). Mutually exclusive with Cilium. |
| **Kubernetes Dashboard (Headlamp)** | No | Web UI for cluster inspection. |
| **httpbin sample** | Yes | Deploys the httpbin demo app from the local registry into the `demo` namespace. |
| **Cluster API (CAPI)** | No | Enables Docker socket mount needed for CAPD-based workload clusters. |
