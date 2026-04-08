#!/bin/bash
set -o errexit

source ../../helpers.sh

# include OpenBao setup first
OPENBAO_EXISTS=$(kubectl get ns openbao || echo "false")

if [ "$OPENBAO_EXISTS" == "false" ]
then
cd ../openbao/
bash setup.sh
else
echo "Skipping OpenBao deployment. Already there."
fi

# configure OpenBao KV store
kubectl exec -n openbao --stdin=true --tty=true openbao-0 -- bao secrets enable -version=2 kv || true
kubectl exec -n openbao --stdin=true --tty=true openbao-0 -- bao kv put kv/supersecret hello=world

cd ../external-secrets/

# start with ESO installation
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --set installCRDs=true

kubectl wait deployment -n external-secrets external-secrets --for condition=Available=True --timeout=300s
kubectl wait deployment -n external-secrets external-secrets-webhook --for condition=Available=True --timeout=300s
kubectl wait deployment -n external-secrets external-secrets-cert-controller --for condition=Available=True --timeout=300s
kubectl wait --for condition=established crd/clustersecretstores.external-secrets.io --timeout=60s
kubectl wait --for condition=established crd/externalsecrets.external-secrets.io --timeout=60s

BAO_ROOT_TOKEN=$(cat ../openbao/init-keys.json | jq -r ".root_token")

echo "apiVersion: v1
kind: Secret
metadata:
  name: openbao-root-token
  namespace: external-secrets
stringData:
  token: ${BAO_ROOT_TOKEN}
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: openbao-backend
spec:
  provider:
    vault:
      server: http://openbao.openbao.svc.cluster.local:8200
      path: kv
      version: v2
      auth:
        tokenSecretRef:
          name: openbao-root-token
          namespace: external-secrets
          key: token" | kubectl apply -f -

# templating method - get values from OpenBao and map them to an user defined key
echo 'apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: example-secret
  namespace: demo
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: openbao-backend
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

# simple method - get key/values from OpenBao 1:1
echo 'apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: example-secret2
  namespace: demo
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: openbao-backend
    kind: ClusterSecretStore
  target:
    name: k8s-secret2
    creationPolicy: Owner
  dataFrom:
  - extract:
      key: supersecret' | kubectl apply -f -
