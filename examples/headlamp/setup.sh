#!/bin/bash
set -o errexit

BASE_DIR=$(dirname "${BASH_SOURCE[0]}")

if kubectl get ingressclass haproxy &>/dev/null; then
  echo "Auto-detected HAProxy ingress controller"
  VALUES_FILE="${BASE_DIR}/values-ingress-haproxy.yaml"
elif kubectl get gatewayclass kong &>/dev/null; then
  echo "Auto-detected Kong Gateway"
  VALUES_FILE="${BASE_DIR}/values-route-kong.yaml"
elif kubectl get ingressclass traefik &>/dev/null; then
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
if [ -n "${VALUES_FILE:-}" ]; then
  echo "Login to Headlamp via https://dashboard.127-0-0-1.nip.io:8081"
else
  echo "No ingress configured. Access Headlamp via port-forward:"
  echo "  kubectl port-forward -n kube-system svc/headlamp 9080:80"
  echo "Then open: http://localhost:9080"
fi
echo ""
echo "Token (sensitive — do not share):"
echo "${LOGIN_TOKEN}"
