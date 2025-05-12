#!/bin/bash
set -o errexit

source ../../helpers.sh

CLUSTER_NAME=$(kubectl config current-context | cut -c 5-)

helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install vault hashicorp/vault --values "vault-values.yaml" --namespace vault --create-namespace

kubectl wait --for=jsonpath='{.status.phase}'=Running pod vault-0 -n vault --timeout=300s || exit 1
# echo "Waiting 60 seconds!"
# sleep 60
kubectl -n vault exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 \
      -format=json > init-keys.json
VAULT_UNSEAL_KEY=$(cat init-keys.json | jq -r ".unseal_keys_b64[]")
echo "Unseal-Key: ${VAULT_UNSEAL_KEY}"

kubectl -n vault exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
VAULT_ROOT_TOKEN=$(cat init-keys.json | jq -r ".root_token")
echo "Vault-Root-Token: ${VAULT_ROOT_TOKEN}"

kubectl -n vault exec vault-0 -- vault login $VAULT_ROOT_TOKEN
kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault secrets enable pki
kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault secrets tune -max-lease-ttl=8760h pki

###########
kubectl -n vault cp root-certs/bundle.pem vault/vault-0:/tmp/
kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault write /pki/config/ca pem_bundle=@/tmp/bundle.pem
###########

# kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault write pki/root/generate/internal \
#     common_name=example.com \
#     ttl=8760h
kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault write pki/config/urls \
    issuing_certificates="http://vault.vault:8200/v1/pki/ca" \
    crl_distribution_points="http://vault.vault:8200/v1/pki/crl"
kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault write pki/roles/example-com \
    allowed_domains=example.com \
    allow_subdomains=true \
    max_ttl=72h
kubectl -n vault exec --stdin=true vault-0 -- vault policy write pki - <<EOF
path "pki*"                             { capabilities = ["read", "list"] }
path "pki/sign/example-com"             { capabilities = ["create", "update"] }
path "pki/issue/example-com"            { capabilities = ["create"] }
EOF
kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault auth enable kubernetes
K8S_IP=$(kubectl -n vault exec vault-0 -- sh -c 'echo $KUBERNETES_PORT_443_TCP_ADDR')
echo $K8S_IP
kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault write auth/kubernetes/config \
    kubernetes_host="https://$K8S_IP:443"
kubectl -n vault exec --stdin=true --tty=true vault-0 -- vault write auth/kubernetes/role/issuer \
    bound_service_account_names=issuer \
    bound_service_account_namespaces=cert-manager \
    policies=pki \
    ttl=20m

helm upgrade --install cert-manager jetstack/cert-manager --set crds.enabled=true --namespace cert-manager --create-namespace

# cert-manager configuration
kubectl -n cert-manager delete serviceaccount issuer || true
kubectl -n cert-manager create serviceaccount issuer

K8S_VERSION=$(kubectl get nodes k3d-${CLUSTER_NAME}-agent-0 -o json | jq .status.nodeInfo.kubeletVersion | cut -c 3-6)
if [ $K8S_VERSION \> 1.23 ]
then
kubectl -n cert-manager delete secret issuer-token-secret || true
echo "K8s version is greater than 1.24!"
echo 'apiVersion: v1
kind: Secret
metadata:
  name: issuer-token-secret
  namespace: cert-manager
  annotations:
    kubernetes.io/service-account.name: issuer
type: kubernetes.io/service-account-token' | kubectl apply -f -
fi

ISSUER_SECRET_REF=$(kubectl get secrets -n cert-manager --output=json | jq -r '.items[].metadata | select(.name|startswith("issuer-token-")).name')
echo $ISSUER_SECRET_REF
echo "
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
  namespace: cert-manager
spec:
  vault:
    server: http://vault.vault.svc.cluster.local:8200
    path: pki/sign/example-com
    auth:
      kubernetes:
        mountPath: /v1/auth/kubernetes
        role: issuer
        secretRef:
          name: ${ISSUER_SECRET_REF}
          key: token" | kubectl apply -f -

echo '
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com
  namespace: demo
spec:
  secretName: example-com-tls
  issuerRef:
    kind: ClusterIssuer
    name: vault-issuer
  commonName: www.example.com
  dnsNames:
  - www.example.com' | kubectl apply -f -

kubectl -n demo apply -f cert-ingress.yaml