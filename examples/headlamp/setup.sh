#!/bin/bash
set -o errexit

BASE_DIR=$(dirname $0)

if kubectl get ingressclass haproxy &>/dev/null 2>&1; then
  echo "Auto-detected HAProxy ingress controller"
  VALUES_FILE="${BASE_DIR}/values-ingress-haproxy.yaml"
elif kubectl get namespace kong &>/dev/null 2>&1 || kubectl get gatewayclass kong &>/dev/null 2>&1; then
  echo "Auto-detected Kong Gateway"
  VALUES_FILE="${BASE_DIR}/values-route-kong.yaml"
elif kubectl get ingressclass traefik &>/dev/null 2>&1; then
  echo "Auto-detected Traefik ingress controller"
  VALUES_FILE="${BASE_DIR}/values-ingress-traefik.yaml"
else
  echo "No ingress controller detected — skipping ingress/route creation."
fi

helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update || true
helm upgrade --install headlamp headlamp/headlamp --namespace kube-system ${VALUES_FILE:+-f "${VALUES_FILE}"}

kubectl wait deployment headlamp \
  -n kube-system \
  --for=condition=Available=true \
  --timeout=120s

LOGIN_TOKEN=$(kubectl create token headlamp --namespace kube-system)

echo ""
echo "Login to headlamp via https://dashboard.127-0-0-1.nip.io:8081 with token: "
echo "${LOGIN_TOKEN}"
