#!/bin/bash
set -o errexit

# Installs HAProxy Ingress Controller as a secondary ingress class alongside
# the cluster's default Kong Gateway. Self-contained: no dependency on
# other showcases or bootstrap flags.

HAPROXY_NAMESPACE=ingress-haproxy
HAPROXY_VERSION=0.14.7

echo "Installing HAProxy Ingress Controller (namespace: ${HAPROXY_NAMESPACE})"

helm repo add haproxy-ingress https://haproxy-ingress.github.io/charts || true
helm repo update haproxy-ingress

kubectl create namespace "${HAPROXY_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Register a non-default IngressClass for HAProxy.
# Note: this does NOT replace Kong — set ingressClassName: haproxy on Ingress
# resources that should be routed through this controller.
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: haproxy
spec:
  controller: haproxy-ingress.github.io/controller
EOF

helm upgrade --install haproxy-ingress haproxy-ingress/haproxy-ingress \
  --namespace "${HAPROXY_NAMESPACE}" \
  --version "${HAPROXY_VERSION}" \
  --set controller.ingressClass=haproxy \
  --set-string controller.config.use-forwarded-headers=true

kubectl -n "${HAPROXY_NAMESPACE}" wait deployment/haproxy-ingress \
  --for condition=Available=True --timeout=300s

echo "HAProxy Ingress Controller installed."
echo "To use it, create Ingress resources with:  ingressClassName: haproxy"
