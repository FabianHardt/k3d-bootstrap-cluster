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

# Remove NGINX Ingress - replace with Kong Ingress
NGINX_EXISTS=$(kubectl get ns ingress-nginx || echo "false")
if [[ "${NGINX_EXISTS}" == "false" ]]
then
echo "Skipping deletion of NGINX ingress..."
else
kubectl delete -f ../../manifests/nginx-helm.yaml || true
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission || true

kubectl delete ingress -n demo httpbin || true
kubectl delete ingress -n vault vault || true
fi

cd ../kong-gateway/

# Install Kong Ingress controller
installIngressController

kubectl delete pod --field-selector=status.phase==Succeeded -A

kubectl apply -n demo -f httproute-httpbin-svc.yaml
kubectl apply -n kong -f httproute-kong-manager.yaml