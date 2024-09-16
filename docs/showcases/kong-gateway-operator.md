# Kong Gateway Operator

### Precondition

Cluster has to be deployed with the *NGINX Ingress Controller* and the *HTTPBin example*.
**DNS preparation**

You can test Kong Ingress by adding the following entry to your */etc/hosts* file:

```bash
# Append to /etc/hosts
[...]

127.0.0.1		httpbin.example.com
```

### Installation

You can start the installation of the Kong Gateway Operator with the included shell script:

```bash
cd examples/kong-gateway-operator
bash setup.sh
```

The following components are installed with the *setup.sh*:

- Installs HashiCorp Vault for certificate management (from `examples/vault`)
  - Installs cert-manager HELM Chart
  - Creates a wildcard certificate for domain *example.com* - used for Kong Gateway
- Installs Gateway API CRDs
- Enables Kubernetes Gateway API support for cert-manager
- Installs Kong Gateway Operator instance using Kong Operator HELM Chart (to namespace *kong-system*) - https://github.com/Kong/charts/tree/main/charts/gateway-operator
- Configures Kong Gateway instance
  - Creates Namespace Kong
  - Creates GatewayClass, GatewayConfiguration and Gateway resources
  - After that Kong Gateway is available in the namespace *kong* and can be called with the URL: <a href="https://localhost:8081">https://localhost:8081</a>
- Creates HTTPRoute resource for the HTTPBin example
  - After that you can open *httpbin* with the URL: https://httpbin.example.com:8081/httpbin-api/v1/anything

> **NOTE**
>
> When you have added the Root CA to your system Truststore, or your browser the connection should be secured correctly. You can find the Root CA certificate under: `examples/vault/root-certs/rootCACert.pem`.