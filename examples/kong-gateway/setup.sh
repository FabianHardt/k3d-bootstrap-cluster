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
excluded_kinds = (
    'kind: ValidatingAdmissionPolicy',
    'kind: ValidatingAdmissionPolicyBinding',
)
print('\n---\n'.join(d for d in docs if not any(kind in d for kind in excluded_kinds)))
" | kubectl apply --server-side -f -

# Enable Gateway API support in cert-manager now that the CRDs are installed
helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
  --set config.kind="ControllerConfiguration" \
  --set config.enableGatewayAPI=true \
  --set config.featureGates.ServerSideApply=true
kubectl rollout restart deployment cert-manager -n cert-manager
kubectl wait deployment cert-manager -n cert-manager --for=condition=Available=true --timeout=120s

# include OpenBao setup first
OPENBAO_EXISTS=$(kubectl get ns openbao || echo "false")

if [[ "${OPENBAO_EXISTS}" == "false" ]]
then
cd ../openbao/
KONG_FLAG=Yes bash setup.sh
else
echo "Skipping OpenBao deployment. Already there."
fi

# Remove HAProxy Ingress - replace with Kong Ingress
HAPROXY_EXISTS=$(kubectl get ns ingress-haproxy 2>/dev/null || echo "false")
if [[ "${HAPROXY_EXISTS}" == "false" ]]
then
echo "Skipping deletion of HAProxy ingress..."
else
kubectl delete -f ../../manifests/haproxy-helm.yaml || true

kubectl delete ingress -n demo httpbin || true
kubectl delete ingress -n openbao openbao || true
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

echo "\nDeploying PostgreSQL TLS passthrough demo"

kubectl apply -f certificate-postgres.yaml

echo "Waiting for cert-manager to issue postgres-tls certificate from Vault..."
kubectl wait certificate postgres-tls -n demo --for=condition=Ready --timeout=120s

kubectl apply -f postgres.yaml
kubectl rollout status deployment/postgres -n demo --timeout=120s

kubectl apply -f tlsroute-postgres.yaml

echo ""
echo "TLSRoute passthrough demos ready."
echo ""
echo "--- httpbin TLS backend ---"
echo "  kubectl port-forward -n kong svc/kong-gateway-proxy 9443:9443"
echo "  curl --cacert ../vault/root-certs/bundle.pem \\"
echo "    --resolve 'httpbin-tls.example.com:9443:127.0.0.1' \\"
echo "    https://httpbin-tls.example.com:9443/"
echo ""
echo "--- PostgreSQL TLS backend ---"
echo "  # Option 1: ephemeral pod inside the cluster (no local tools needed)"
echo "  kubectl run -it --rm psql-test \\"
echo "    --image=postgres:17-alpine \\"
echo "    --restart=Never \\"
echo "    -- sh -c 'psql \"hostaddr=\$(getent hosts kong-gateway-proxy.kong.svc.cluster.local \\"
echo "      | awk '"'"'{print \$1}'"'"' | head -1) \\"
echo "      host=postgres.example.com port=9443 \\"
echo "      sslmode=require sslnegotiation=direct \\"
echo "      user=demo password=demo dbname=demo\"'"
echo ""
echo "  # Option 2: Docker from outside the cluster"
echo "  kubectl port-forward -n kong svc/kong-gateway-proxy 5432:9443 &"
echo "  docker run --rm -it \\"
echo "    -v \"\$(pwd)/../vault/root-certs/bundle.pem:/bundle.pem:ro\" \\"
echo "    --add-host \"postgres.example.com:host-gateway\" \\"
echo "    postgres:17-alpine \\"
echo "    psql \"host=postgres.example.com port=5432 sslmode=require sslnegotiation=direct user=demo password=demo dbname=demo sslrootcert=/bundle.pem\""
echo ""
echo "  # Option 3: local psql (requires libpq 17, not 18+)"
echo "  kubectl port-forward -n kong svc/kong-gateway-proxy 5432:9443 &"
echo "  psql \"host=postgres.example.com port=5432 sslmode=require sslnegotiation=direct user=demo password=demo dbname=demo sslrootcert=../vault/root-certs/bundle.pem\""