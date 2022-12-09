#!/bin/bash
set -o errexit

kubectl create ns keycloak || true
kubectl create configmap -n keycloak keycloak-config-realm --from-file=kong-realm.json=kong-realm.json || true
helm upgrade --install keycloak bitnami/keycloak --namespace keycloak --values values.yaml
