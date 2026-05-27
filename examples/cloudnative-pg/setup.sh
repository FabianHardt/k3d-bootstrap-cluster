#!/bin/bash
set -o errexit

source ../../helpers.sh

# ---------------------------------------------------------------------------
# Determine ingress mode.
# Explicit flags take precedence; otherwise auto-detect from the cluster.
#   HAPROXY_FLAG=Yes  → HAProxy IngressClass + Ingress resources
#   KONG_FLAG=Yes     → Kong GatewayClass + Gateway API HTTPRoute resources
# ---------------------------------------------------------------------------
if [ "${HAPROXY_FLAG}" == "Yes" ]; then
  INGRESS_MODE="haproxy"
elif [ "${KONG_FLAG}" == "Yes" ]; then
  INGRESS_MODE="kong"
elif kubectl get ingressclass haproxy &>/dev/null 2>&1; then
  echo "Auto-detected HAProxy ingress controller"
  INGRESS_MODE="haproxy"
elif kubectl get namespace kong &>/dev/null 2>&1 || kubectl get gatewayclass kong &>/dev/null 2>&1; then
  echo "Auto-detected Kong Gateway"
  INGRESS_MODE="kong"
else
  echo "No ingress controller detected — pgAdmin will be accessible via port-forward only."
  INGRESS_MODE="none"
fi

# ---------------------------------------------------------------------------
# Install CloudNativePG operator
# ---------------------------------------------------------------------------
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo add runix https://helm.runix.net
helm repo update || true

helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --create-namespace \
  --wait

kubectl wait --for=condition=Available deployment/cnpg-cloudnative-pg \
  -n cnpg-system --timeout=120s

# ---------------------------------------------------------------------------
# Create sample PostgreSQL cluster via CNPG Cluster CRD
# ---------------------------------------------------------------------------
kubectl apply -f cluster.yaml

echo "Waiting for PostgreSQL cluster to be ready..."
kubectl wait --for=condition=Ready cluster/sample-pg \
  -n cloudnative-pg --timeout=300s

# ---------------------------------------------------------------------------
# Install pgAdmin 4
# ---------------------------------------------------------------------------
if [ "${INGRESS_MODE}" == "kong" ]; then
  PGADMIN_VALUES="pgadmin-values-kong.yaml"
else
  PGADMIN_VALUES="pgadmin-values.yaml"
fi

helm upgrade --install pgadmin4 runix/pgadmin4 \
  --values "${PGADMIN_VALUES}" \
  --namespace pgadmin \
  --create-namespace \
  --wait

kubectl wait --for=condition=Available deployment/pgadmin4 \
  -n pgadmin --timeout=120s

# ---------------------------------------------------------------------------
# Print connection info
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  CloudNativePG + pgAdmin Setup Complete"
echo "================================================================"
echo ""
echo "  PostgreSQL cluster: sample-pg (namespace: cloudnative-pg)"
echo "  Primary service:    sample-pg-rw.cloudnative-pg.svc:5432"
echo "  Read-only service:  sample-pg-ro.cloudnative-pg.svc:5432"
echo ""
echo "  pgAdmin UI:"
if [ "${INGRESS_MODE}" == "haproxy" ] || [ "${INGRESS_MODE}" == "kong" ]; then
  echo "    URL:      http://pgadmin.127-0-0-1.nip.io:8080"
  echo "    Email:    admin@example.com"
  echo "    Password: admin"
else
  echo "    kubectl port-forward svc/pgadmin4 -n pgadmin 8888:80"
  echo "    URL:      http://localhost:8888"
  echo "    Email:    admin@example.com"
  echo "    Password: admin"
fi
echo ""
echo "  PostgreSQL superuser credentials:"
echo "    kubectl get secret sample-pg-superuser -n cloudnative-pg -o jsonpath='{.data.username}' | base64 -d"
echo "    kubectl get secret sample-pg-superuser -n cloudnative-pg -o jsonpath='{.data.password}' | base64 -d"
echo "================================================================"
