#!/bin/bash

source ../../helpers.sh

# Remove httpbin NodePort (is reused later)
kubectl -n demo patch svc httpbin --type='json' -p '[{"op":"replace","path":"/spec/type","value":"ClusterIP"}]'

# Preconditions
kubectl create namespace keycloak || true

kubectl apply -n keycloak -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.6/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -n keycloak -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.6/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml

echo "Waiting 10 seconds!"
sleep 10
kubectl apply -n keycloak -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.6/kubernetes/kubernetes.yml

# Add Postgres DB
kubectl apply -n keycloak -f postgres.yml

# Get TLS secret for Keycloak
echo '
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: keycloak-tls
  namespace: keycloak
spec:
  secretName: keycloak-tls
  issuerRef:
    kind: ClusterIssuer
    name: vault-issuer
  commonName: keycloak.example.com
  dnsNames:
  - keycloak.example.com' | kubectl apply -f -

kubectl -n keycloak create secret generic keycloak-db-secret \
  --from-literal=username=testuser \
  --from-literal=password=testpassword

kubectl -n keycloak apply -f keycloak-service.yml
kubectl -n keycloak apply -f keycloak.yml

printf 'Keycloak is ready, here is your admin username:\n'
kubectl -n keycloak get secret test-keycloak-initial-admin -o jsonpath='{.data.username}' | base64 --decode
printf '...and password:\n'
kubectl -n keycloak get secret test-keycloak-initial-admin -o jsonpath='{.data.password}' | base64 --decode
