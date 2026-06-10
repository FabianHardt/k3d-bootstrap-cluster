# What is K3d Bootstrap Cluster?

This project creates an k3d demo cluster. It comes with an interactive setup, which allows you to setup a Kubernetes cluster for demo and showcase purposes.

`k3d-bootstrap-cluster` uses [k3d](https://github.com/k3d-io/k3d) as base.

## Optional components

Every cluster ships with **Kong Gateway (Gateway API)** as the sole ingress controller (Traefik is disabled; Flannel is replaced by Cilium by default, or by Calico when selected). Kong installs Gateway API CRDs v1.5.1, Kong Ingress Controller (v3.5.6), a `GatewayClass`, and a `Gateway`. httpbin is exposed via `HTTPRoute`.

If you want to experiment with classic Ingress alongside Kong, install the [HAProxy Ingress showcase](/showcases/haproxy.html) after the cluster is up.

During interactive setup (`bash create-sample.sh`) you can choose the following optional components:

| Component | Default | Description |
|-----------|---------|-------------|
| **Cilium CNI** | Yes | Replaces Flannel. eBPF-based networking with Kubernetes NetworkPolicy support. Mutually exclusive with Calico. |
| **Calico CNI** | No | Replaces Flannel. Enables Kubernetes NetworkPolicy support (needed for the Calico NetworkPolicies showcase). Mutually exclusive with Cilium. |
| **Kubernetes Dashboard (Headlamp)** | No | Web UI for cluster inspection. |
| **httpbin sample** | Yes | Deploys the httpbin demo app from the local registry into the `demo` namespace. |
| **Cluster API (CAPI)** | No | Enables Docker socket mount needed for CAPD-based workload clusters. |
