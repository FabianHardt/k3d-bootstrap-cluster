#!/bin/bash
set -o errexit

source ../../helpers.sh
# include Hashicorp Vault setup first

VAULT_EXISTS=$(kubectl get ns vault || echo "false")

if [ "$VAULT_EXISTS" == "false" ]
then
cd ../vault/
bash setup.sh
else
echo "Skipping vault deployment. Already there."
fi

# configure Vault KV store
kubectl exec -n vault --stdin=true --tty=true vault-0 -- vault secrets enable -version=2 kv || true
kubectl exec -n vault --stdin=true --tty=true vault-0 -- vault kv put kv/supersecret hello=world

cd ../external-secrets/

# start with ESO installation
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --set installCRDs=true

kubectl wait deployment -n external-secrets external-secrets --for condition=Available=True --timeout=300s
kubectl wait deployment -n external-secrets external-secrets-webhook --for condition=Available=True --timeout=300s
kubectl wait deployment -n external-secrets external-secrets-cert-controller --for condition=Available=True --timeout=300s

VAULT_ROOT_TOKEN=$(cat ../vault/init-keys.json | jq -r ".root_token")

echo "apiVersion: v1
kind: Secret
metadata:
  name: vault-root-token
  namespace: external-secrets
stringData:
  token: ${VAULT_ROOT_TOKEN}
---
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: http://vault-internal.vault.svc.cluster.local:8200
      path: kv
      version: v2
      auth:
        tokenSecretRef:
          name: vault-root-token
          namespace: external-secrets
          key: token" | kubectl apply -f -

# templating method - get values from Vault and map them to an user defined key
echo 'apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: example-secret
  namespace: demo
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: k8s-secret
    template:
      data:
        helloKey: "{{ .hello }}"
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: supersecret' | kubectl apply -f -

# simple method - get key/values from Vault 1:1
echo 'apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: example-secret2
  namespace: demo
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: k8s-secret2
    creationPolicy: Owner
  dataFrom:
  - extract:
      key: supersecret' | kubectl apply -f -
