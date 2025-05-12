#!/bin/bash

LICENSE_FILE=license.json

installIngressController() {
	# Preconditions
kubectl create namespace kong || true

kubectl apply -f gateway-class.yaml
kubectl apply -f gateway.yaml

helm upgrade --install kong kong/ingress --values values.yaml --namespace kong

if [[ -f ${LICENSE_FILE} ]]; then
echo "${LICENSE_FILE} exists. Using it!"

echo "
apiVersion: configuration.konghq.com/v1alpha1
kind: KongLicense
metadata:
  name: kong-license
rawLicenseString: '$(cat "${LICENSE_FILE}")'
" | kubectl apply -f -
fi

echo "Waiting for Kong Ingress Controller Pods to be ready..."
kubectl -n kong wait --for=condition=Available=true --timeout=120s deployment/kong-gateway
}
