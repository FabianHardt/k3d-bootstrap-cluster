# Hashicorp Vault

Installation with HELM:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com

helm upgrade --install vault hashicorp/vault --namespace vault --create-namespace

# Optional in DEV Mode
helm upgrade --install vault hashicorp/vault --namespace vault --create-namespace --set "server.dev.enabled=true"
```

Anschließend kann Vault innerhalb des Clusters erreicht werden. Für den Zugriff von Außen müsste ein NodePort oder Ingress konfiguriert werden.

### CA Config

TODO: https://learn.hashicorp.com/tutorials/vault/kubernetes-cert-manager

TODO: Externer CoreDNS Server - external-dns --> Dann mit dynamischen Ingress Hosts simulieren
https://github.com/kubernetes-sigs/external-dns