#!/bin/bash
set -o errexit

kubectl create ns keycloak || true
kubectl create configmap keycloak-config-realm --from-file=kong-realm.json=kong-realm.json || true
helm upgrade --install keycloak bitnami/keycloak --create-namespace --namespace keycloak --values values.yaml
