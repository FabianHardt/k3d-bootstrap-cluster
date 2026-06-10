#!/bin/bash
set -o errexit

source ../../helpers.sh

CLUSTER_NAME=$(kubectl config current-context | cut -c 5-)

helm repo add openbao https://openbao.github.io/openbao-helm
helm repo add jetstack https://charts.jetstack.io
helm repo update || true

helm upgrade --install openbao openbao/openbao --values openbao-values-kong.yaml --namespace openbao --create-namespace

kubectl wait --for=jsonpath='{.status.phase}'=Running pod openbao-0 -n openbao --timeout=300s || exit 1

kubectl -n openbao exec openbao-0 -- bao operator init -key-shares=1 -key-threshold=1 \
      -format=json > init-keys.json
BAO_UNSEAL_KEY=$(cat init-keys.json | jq -r ".unseal_keys_b64[]")
echo "Unseal-Key: ${BAO_UNSEAL_KEY}"

kubectl -n openbao exec openbao-0 -- bao operator unseal $BAO_UNSEAL_KEY
BAO_ROOT_TOKEN=$(cat init-keys.json | jq -r ".root_token")
echo "OpenBao-Root-Token: ${BAO_ROOT_TOKEN}"

kubectl -n openbao exec openbao-0 -- bao login $BAO_ROOT_TOKEN
kubectl -n openbao exec --stdin=true --tty=true openbao-0 -- bao secrets enable pki
kubectl -n openbao exec --stdin=true --tty=true openbao-0 -- bao secrets tune -max-lease-ttl=8760h pki

kubectl -n openbao cp root-certs/bundle.pem openbao/openbao-0:/tmp/
ISSUER_ID=$(kubectl -n openbao exec openbao-0 -- \
    bao write -format=json /pki/config/ca pem_bundle=@/tmp/bundle.pem | \
    jq -r '.data.imported_issuers[0]')
kubectl -n openbao exec openbao-0 -- bao write pki/config/issuers default=$ISSUER_ID
kubectl -n openbao exec --stdin=true --tty=true openbao-0 -- bao write pki/config/urls \
    issuing_certificates="http://openbao.openbao:8200/v1/pki/ca" \
    crl_distribution_points="http://openbao.openbao:8200/v1/pki/crl"
kubectl -n openbao exec --stdin=true --tty=true openbao-0 -- bao write pki/roles/example-com \
    allowed_domains=example.com \
    allow_subdomains=true \
    allow_glob_domains=true \
    max_ttl=72h
kubectl -n openbao exec --stdin=true openbao-0 -- bao policy write pki - <<EOF
path "pki*"                             { capabilities = ["read", "list"] }
path "pki/sign/example-com"             { capabilities = ["create", "update"] }
path "pki/issue/example-com"            { capabilities = ["create"] }
EOF
kubectl -n openbao exec --stdin=true --tty=true openbao-0 -- bao auth enable kubernetes
K8S_IP=$(kubectl -n openbao exec openbao-0 -- sh -c 'echo $KUBERNETES_PORT_443_TCP_ADDR')
echo $K8S_IP
kubectl -n openbao exec --stdin=true --tty=true openbao-0 -- bao write auth/kubernetes/config \
    kubernetes_host="https://$K8S_IP:443"
kubectl -n openbao exec --stdin=true --tty=true openbao-0 -- bao write auth/kubernetes/role/issuer \
    bound_service_account_names=issuer \
    bound_service_account_namespaces=cert-manager \
    policies=pki \
    ttl=20m

helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
  --set config.kind="ControllerConfiguration"

# cert-manager configuration
kubectl -n cert-manager delete serviceaccount issuer || true
kubectl -n cert-manager create serviceaccount issuer

K8S_MINOR=$(kubectl get nodes "k3d-${CLUSTER_NAME}-agent-0" -o json | jq -r .status.nodeInfo.kubeletVersion | sed -E 's/^v[0-9]+\.([0-9]+).*/\1/')
if [ "$K8S_MINOR" -gt 23 ]
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
  name: openbao-issuer
  namespace: cert-manager
spec:
  vault:
    server: http://openbao.openbao.svc.cluster.local:8200
    path: pki/sign/example-com
    auth:
      kubernetes:
        mountPath: /v1/auth/kubernetes
        role: issuer
        secretRef:
          name: ${ISSUER_SECRET_REF}
          key: token" | kubectl apply -f -

# Wildcard certificate in kong namespace — used by the Gateway for TLS termination
echo "
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com-wildcard
  namespace: kong
spec:
  secretName: example-com-tls
  issuerRef:
    kind: ClusterIssuer
    name: openbao-issuer
  commonName: '*.example.com'
  dnsNames:
  - '*.example.com'" | kubectl apply -f -
# Update the Kong Gateway to add the HTTPS listener with the wildcard certificate
kubectl apply -f gateway-kong.yaml
kubectl apply -f httproute-httpbin.yaml
kubectl apply -f httproute-openbao.yaml
