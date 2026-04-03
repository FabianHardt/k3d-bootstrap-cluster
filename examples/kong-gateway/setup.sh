#!/bin/bash
set -o errexit

source helpers.sh

helm repo add kong https://charts.konghq.com
helm repo update

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

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