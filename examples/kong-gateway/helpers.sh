#!/bin/bash

LICENSE_FILE=license.json
LICENSE_FILE_CONTENT={}

installIngressController()
{
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

# Preconditions
kubectl create namespace kong || true

kubectl delete secret kong-config-secret -n kong || true

kubectl create secret generic kong-config-secret -n kong \
    --from-literal=portal_session_conf='{"storage":"kong","secret":"superfhasecret","cookie_name":"portal_session","cookie_samesite":"off","cookie_secure":false}' \
    --from-literal=admin_gui_session_conf='{"storage":"kong","secret":"superfhasecret","cookie_name":"admin_session","cookie_samesite":"off","cookie_secure":false}' \
    --from-literal=pg_host="enterprise-postgresql.kong.svc.cluster.local" \
    --from-literal=kong_admin_password=kong \
    --from-literal=password=kong

kubectl apply -f gateway-class.yaml
kubectl apply -f gateway.yaml

helm upgrade --install kong kong/ingress --values values.yaml --namespace kong

if [ -f "$LICENSE_FILE" ]; then
  echo "$LICENSE_FILE exists. Using it!"
  LICENSE_FILE_CONTENT=$(cat $LICENSE_FILE)
fi

echo "
apiVersion: configuration.konghq.com/v1alpha1
kind: KongLicense
metadata:
 name: kong-license
rawLicenseString: '$(echo $LICENSE_FILE_CONTENT)'
" | kubectl apply -f -

echo "Waiting for Kong Ingress Controller Pods to be ready..."
kubectl -n kong wait --for=condition=Available=true --timeout=120s deployment/kong-gateway
}