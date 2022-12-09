#!/bin/bash

LICENSE_FILE=license.json

installControlPlane()
{
# Preconditions
kubectl create namespace kong-cp || true

kubectl delete secret kong-config-secret -n kong-cp || true

kubectl create secret generic kong-config-secret -n kong-cp \
    --from-literal=portal_session_conf='{"storage":"kong","secret":"superfhasecret","cookie_name":"portal_session","cookie_samesite":"off","cookie_secure":false}' \
    --from-literal=admin_gui_session_conf='{"storage":"kong","secret":"superfhasecret","cookie_name":"admin_session","cookie_samesite":"off","cookie_secure":false}' \
    --from-literal=pg_host="enterprise-postgresql.kong-cp.svc.cluster.local" \
    --from-literal=kong_admin_password=kong \
    --from-literal=password=kong

if [ -f "$LICENSE_FILE" ]; then
  echo "$LICENSE_FILE exists. Using it!"
  kubectl create secret generic kong-enterprise-license --from-file=license=$LICENSE_FILE -n kong-cp --dry-run=client -o yaml | kubectl apply -f -
else
  echo "$LICENSE_FILE does not exists. Using free version!"
  kubectl create secret generic kong-enterprise-license --from-literal=license="'{}'" -n kong-cp --dry-run=client -o yaml | kubectl apply -f -
fi

echo "
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kong-wildcard-crt
  namespace: kong-cp
spec:
  secretName: kong-wildcard-crt
  issuerRef:
    kind: ClusterIssuer
    name: vault-issuer
  commonName: '*.example.com'
  dnsNames:
    - '*.example.com'" | kubectl apply -f -

helm upgrade --install kong kong/kong --values cp-values.yaml --namespace kong-cp --create-namespace
}

installDataPlane()
{
# Preconditions
kubectl create namespace kong-dp || true

if [ -f "$LICENSE_FILE" ]; then
  echo "$LICENSE_FILE exists. Using it!"
  kubectl create secret generic kong-enterprise-license --from-file=license=$LICENSE_FILE -n kong-dp --dry-run=client -o yaml | kubectl apply -f -
else
  echo "$LICENSE_FILE does not exists. Using free version!"
  kubectl create secret generic kong-enterprise-license --from-literal=license="'{}'" -n kong-dp --dry-run=client -o yaml | kubectl apply -f -
fi

echo "
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kong-wildcard-crt
  namespace: kong-dp
spec:
  secretName: kong-wildcard-crt
  issuerRef:
    kind: ClusterIssuer
    name: vault-issuer
  commonName: '*.example.com'
  dnsNames:
    - '*.example.com'" | kubectl apply -f -

helm upgrade --install kong kong/kong --values dp-values.yaml --namespace kong-dp --create-namespace
}

installIngressController()
{
echo 'Wait for kong controlplane deployment to become ready'
kubectl wait deployment -n kong-cp kong-kong --for condition=Available=True --timeout=300s
helm upgrade --install kong-ing kong/kong --values ing-values.yaml --namespace kong-cp --create-namespace
}