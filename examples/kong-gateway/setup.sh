#!/bin/bash
set -o errexit

source helpers.sh

helm repo add kong https://charts.konghq.com
helm repo update

# include Hashicorp Vault setup first
VAULT_EXISTS=$(kubectl get ns vault || echo "false")

if [ "$VAULT_EXISTS" == "false" ]
then
cd ../vault/
bash setup.sh
else
echo "Skipping vault deployment. Already there."
fi

# Remove NGINX Ingress - replace with Kong Ingress
kubectl delete -f ../../manifests/nginx-helm.yaml || true
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission || true

cd ../kong-gateway/

# Install Kong Controlplane
installControlPlane

# Install Kong Dataplane
installDataPlane

# Install Kong Ingress controller
installIngressController

kubectl apply -n demo -f httpbin-ingress-kong.yaml