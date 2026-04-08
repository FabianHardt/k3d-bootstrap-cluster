# OpenBao and cert-manager

[OpenBao](https://openbao.org) is an open-source fork of HashiCorp Vault, maintained by the Linux Foundation after Vault's license change to BSL. The API and CLI are fully compatible — the only visible difference is the `bao` command instead of `vault`.

### Precondition

Cluster has to be deployed with the *httpbin* sample. Otherwise this demo wouldn't work.

### Installation

You can start the installation script of OpenBao and cert-manager with the included shell script.
Set one of the following flags to control how the httpbin and OpenBao UI are exposed:

```bash
cd examples/openbao

# With HAProxy Ingress Controller
HAPROXY_FLAG=Yes bash setup.sh

# With Kong Gateway (Gateway API / HTTPRoute)
KONG_FLAG=Yes bash setup.sh
```

If neither flag is set, OpenBao and cert-manager are installed without creating any Ingress or HTTPRoute resources.

The following components are installed with the *setup.sh*:

- OpenBao - HELM Chart (namespace: `openbao`)
- Configuration of OpenBao server
  - Configure key-share and key-threshold
  - Unseal OpenBao server
  - Enable PKI, import Root CA
  - Create role to issue certificates for domain *example.com*
  - Enable Kubernetes auth, add policy for service account *issuer*
- Install cert-manager - HELM Chart
- Create service account *issuer* in cert-manager namespace
- Create `ClusterIssuer` named `openbao-issuer` (connection to OpenBao)
- Create certificate for *www.example.com* — places K8s secret with key, ca and cert in demo namespace
- Configure Ingress in demo namespace to secure httpbin Ingress with an OpenBao-signed certificate

### Test Ingress

The *httpbin* Ingress is updated by this sample deployment. You can test the Ingress by adding the following entries to your */etc/hosts* file:

```bash
# Append to /etc/hosts
[...]

127.0.0.1		httpbin.example.com
127.0.0.1		openbao.example.com
```

After that you can open *httpbin* with the URL: https://httpbin.example.com:8081.
When you have added the Root CA to your system Truststore, or your browser the connection should be secured correctly. You can find the Root CA certificate under: `examples/openbao/root-certs/rootCACert.pem`.

### Show OpenBao UI

The OpenBao UI is exposed via Ingress, you can open it in a browser: https://openbao.example.com:8081/ui
