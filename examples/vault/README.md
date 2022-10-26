# Hashicorp Vault and cert-manager

You can start the installation script of Hashicorp Vault and cert-manager with the included shell script:

```bash
cd examples/vault
bash setup.sh
```

Vault is installed via HELM Chart. After installation a PKI is configured - Vault interacts as a Root CA now.
Kubernetes authentication is configured in Vault, which is necessary to authenticate from K8s Cluster to Vault.

