# external-secrets

Install with HELM:

```bash
helm repo add external-secrets https://charts.external-secrets.io

helm install external-secrets \
   external-secrets/external-secrets \
    -n external-secrets \
    --create-namespace \
    --set installCRDs=true
```

Create secret store:

```bash
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault-internal.vault.svc.cluster.local:8200"
      path: "kv"
      version: "v2"
      auth:
        tokenSecretRef:
          name: "vault-root-token"
          namespace: external-secrets
          key: "token"
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-root-token
  namespace: external-secrets
stringData:
  token: "hvs.gqWy3ksSCvDSf9RhsZN4Byf2"

```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: test
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: example-secret
  namespace: test
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: k8s-secret
    creationPolicy: Owner
  data:
  - secretKey: supersecret

```

