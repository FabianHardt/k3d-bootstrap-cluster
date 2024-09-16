#!/bin/bash

# include Hashicorp Vault setup first
VAULT_EXISTS=$(kubectl get ns vault || echo "false")

if [ "$VAULT_EXISTS" == "false" ]
then
cd ../vault/
bash setup.sh
else
echo "Skipping vault deployment. Already there."
fi

# Remove NGINX Ingress - will be replaced with Kong Gateway resp. an Operator-based Gateway
NGINX_EXISTS=$(kubectl get ns ingress-nginx || echo "false")
if [ "$NGINX_EXISTS" == "false" ]
then
echo "Skipping deletion of NGINX ingress..."
else
kubectl delete -f ../../manifests/nginx-helm.yaml || true
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission || true
kubectl delete ingress -n demo httpbin
fi

echo "\nInstall Gateway API extension"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

echo "\nUpdating cert-manager to work with Gateway API"
helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager \
  --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
  --set config.kind="ControllerConfiguration" \
  --set config.enableGatewayAPI=true

kubectl rollout restart deployment cert-manager -n cert-manager

kubectl -n cert-manager wait --for=condition=Available=true --timeout=120s deployment/cert-manager

cd ../kong-gateway-operator/

echo "\nInstall Kong Gateway Operator"
helm repo add kong https://charts.konghq.com
helm repo update kong

helm upgrade --install kgo kong/gateway-operator -n kong-system --create-namespace --set image.tag=1.2

kubectl -n kong-system wait --for=condition=Available=true --timeout=120s deployment/kgo-gateway-operator-controller-manager

kubectl apply -f gateway-configuration.yaml

echo "\nConfigure HTTPRoute for httpbin"
kubectl apply -f httproute-httpbin.yaml
