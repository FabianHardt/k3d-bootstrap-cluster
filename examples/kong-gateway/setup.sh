#!/bin/bash
set -o errexit

source helpers.sh

helm repo add kong https://charts.konghq.com
helm repo update

# Install experimental Gateway API CRDs.
# The manifest itself contains a ValidatingAdmissionPolicy that blocks upgrading from
# standard to experimental channel. We filter it out before applying so it cannot
# block the CRDs that follow it in the manifest.
kubectl delete validatingadmissionpolicy safe-upgrades.gateway.networking.k8s.io --ignore-not-found
kubectl delete validatingadmissionpolicybinding safe-upgrades.gateway.networking.k8s.io --ignore-not-found
curl -sL https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml | \
  python3 -c "
import sys
docs = sys.stdin.read().split('\n---\n')
print('\n---\n'.join(d for d in docs if 'kind: ValidatingAdmissionPolicy' not in d))
" | kubectl apply --server-side -f -

# include Hashicorp Vault setup first
VAULT_EXISTS=$(kubectl get ns vault || echo "false")

if [[ "${VAULT_EXISTS}" == "false" ]]
then
cd ../vault/
bash setup.sh
else
echo "Skipping vault deployment. Already there."
fi

# Remove HAProxy Ingress - replace with Kong Ingress
HAPROXY_EXISTS=$(kubectl get ns ingress-haproxy 2>/dev/null || echo "false")
if [[ "${HAPROXY_EXISTS}" == "false" ]]
then
echo "Skipping deletion of HAProxy ingress..."
else
kubectl delete -f ../../manifests/haproxy-helm.yaml || true

kubectl delete ingress -n demo httpbin || true
kubectl delete ingress -n vault vault || true
fi

cd ../kong-gateway/

# Install Kong Ingress controller
installIngressController

kubectl delete pod --field-selector=status.phase==Succeeded -A

kubectl apply -n demo -f httproute-httpbin-svc.yaml
kubectl apply -n kong -f httproute-kong-manager.yaml

echo "\nDeploying TLS passthrough demo (TLSRoute + Vault-signed cert)"

kubectl apply -f certificate-tls-backend.yaml

echo "Waiting for cert-manager to issue tls-backend certificate from Vault..."
kubectl wait certificate tls-backend -n demo --for=condition=Ready --timeout=120s

kubectl apply -f tls-backend.yaml
kubectl rollout status deployment/tls-backend -n demo --timeout=120s

kubectl apply -f tlsroute-httpbin-tls.yaml

echo ""
echo "TLSRoute passthrough demo ready."
echo "Test with port-forward:"
echo "  kubectl port-forward -n kong svc/kong-gateway-proxy 9443:9443"
echo "  curl --cacert examples/vault/root-certs/bundle.pem \\"
echo "    --resolve 'httpbin-tls.example.com:9443:127.0.0.1' \\"
echo "    https://httpbin-tls.example.com:9443/"