#!/bin/bash

# include OpenBao setup first
OPENBAO_EXISTS=$(kubectl get ns openbao || echo "false")

if [ "$OPENBAO_EXISTS" == "false" ]
then
cd ../openbao/
bash setup.sh
else
echo "Skipping OpenBao deployment. Already there."
fi

echo "\nInstall Gateway API extension"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

echo "\nUpdating cert-manager to work with Gateway API"
helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager \
  --set crds.enabled=true \
  --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
  --set config.kind="ControllerConfiguration" \
  --set config.enableGatewayAPI=true

kubectl rollout restart deployment cert-manager -n cert-manager

kubectl -n cert-manager wait --for=condition=Available=true --timeout=120s deployment/cert-manager

cd ../kong-gateway-operator/

echo "\nInstall Kong Gateway Operator"
helm repo add kong https://charts.konghq.com
helm repo update kong

helm upgrade --install kgo kong/gateway-operator -n kong-system --create-namespace --reset-values

kubectl -n kong-system wait --for=condition=Available=true --timeout=120s deployment/kgo-gateway-operator-controller-manager

# GatewayClass "kong" may already exist from kong-gateway example with a different controllerName — recreate it
kubectl delete gatewayclass kong --ignore-not-found
kubectl apply -f gateway-configuration.yaml

echo "\nConfigure HTTPRoute for httpbin"
kubectl apply -f httproute-httpbin.yaml
