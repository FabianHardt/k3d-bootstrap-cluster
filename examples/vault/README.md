# Hashicorp Vault and cert-manager

### Precondition

Cluster has to be deployed with the *httpbin* sample. Otherwise this demo wouldn't work.

### Installation

You can start the installation script of Hashicorp Vault and cert-manager with the included shell script:

```bash
cd examples/vault
bash setup.sh
```

The following components are installed with the *setup.sh*:

- Hashicorp Vault - HELM Chart
- Configuration of Vault server
  - Configure key-share and key-threshold
  - Unseal Vault server
  - Enable PKI, create Root CA
  - Create group to issue certificates for domain *example.com*
  - Enable Kubernetes auth, add policy for service account *issuer*
- Install cert-manager - HELM Chart
- Create service accoount *issuer* in demo namespace
- Create issuer (connection to Vault) in demo namespace
- Create certificate for *www.example.com* - place K8s secret with key, ca and cert in demo namespace
- Configure Ingress in demo namespace to secure httpbin Ingress with a Vault signed certificate

### Test Ingress

The *httpbin* Ingress is updated by this sample deployment. You can test the Ingress by adding the following entry to your */etc/hosts* file:

```bash
# Append to /etc/hosts
[...]

127.0.0.1		httpbin.example.com
```

After that you can open *httpbin* with the URL: https://httpbin.example.com:8081.
When you have added the Root CA to your system Truststore, or your browser the connection should be secured correctly. You can find the Root CA certificate under: `examples/vault/root-certs/rootCACert.pem`.

### Show Vault UI

The vault UI is exposed via Ingress, you can open Vault-UI in a browser of your choice: https://vault.127-0-0-1.nip.io:8081/ui