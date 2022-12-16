# Kuma Service Mesh (Standalone Mode)

### Precondition

Cluster has to be deployed with the *Kong Ingress Controller*.

**DNS preparation**

You can test Kong Ingress by adding the following entry to your */etc/hosts* file:

```bash
# Append to /etc/hosts
[...]

127.0.0.1		kuma-gui.example.com
```

### Installation

You can start the installation of Kong API Gateway with the included shell script:

```bash
cd examples/kuma-mesh
bash setup.sh
```

The following components are installed with the *setup.sh*:

- Kuma HELM Chart is used to deploy Kuma Service Mesh - https://github.com/kumahq/charts
  - Installs Ku,a Control Plane instance to namespace *kuma-cp*

### Show Kuma Dashboard

If your local DNS settings (/etc/hosts) are set correctly, you can open the Kong Manager UI in your browser: https://kuma-gui.example.com:8081/gui
