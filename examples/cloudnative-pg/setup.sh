#!/bin/bash
set -o errexit

source ../../helpers.sh

# Kong Gateway is the sole ingress controller in this cluster — pgAdmin is
# exposed via a Gateway API HTTPRoute.

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
helm upgrade --install pgadmin4 runix/pgadmin4 \
  --values pgadmin-values-kong.yaml \
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
echo "    URL:      http://pgadmin.127-0-0-1.nip.io:8080"
echo "    Email:    admin@example.com"
echo "    Password: admin"
echo ""
echo "  PostgreSQL superuser credentials:"
echo "    kubectl get secret sample-pg-superuser -n cloudnative-pg -o jsonpath='{.data.username}' | base64 -d"
echo "    kubectl get secret sample-pg-superuser -n cloudnative-pg -o jsonpath='{.data.password}' | base64 -d"
echo "================================================================"
