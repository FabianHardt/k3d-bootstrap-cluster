# Hashicorp Vault and cert-manager

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

### Show Vault UI

Actually there is no port exposed to outside the cluster. You have to use *port-forward*:

```bash
kubectl port-forward -n vault vault-0 8200
```

After that you can open Vault-UI in a browser of your choice: http://localhost:8200/ui/