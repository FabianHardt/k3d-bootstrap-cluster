#!/bin/bash
set -o errexit

kubectl create namespace monitoring || true
kubectl label ns monitoring kuma.io/sidecar-injection=enabled --overwrite

echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update || true

echo "Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --values prometheus-values.yaml

echo "Deploying Tempo..."
helm upgrade --install tempo grafana/tempo \
  --namespace monitoring \
  --values tempo-values.yaml

echo "Deploying Grafana..."
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml

echo "Waiting for Prometheus to be ready..."
kubectl wait deployment prometheus-server -n monitoring --for=condition=Available=true --timeout=120s

echo "Waiting for Tempo to be ready..."
kubectl rollout status statefulset/tempo -n monitoring --timeout=120s

echo "Waiting for Grafana to be ready..."
kubectl wait deployment grafana -n monitoring --for=condition=Available=true --timeout=120s

echo "Applying Grafana route..."
kubectl apply -f grafana-route.yaml

echo "Monitoring stack deployed (Prometheus + Grafana + Tempo)."

echo "--- Monitoring & Observability ---"
echo "  Grafana:    https://grafana.example.com:8081 (admin / admin)"
echo "  Dashboards: Kong AI Gateway | Kuma Service Mesh"
echo "  Tracing:    Grafana Explore → Tempo datasource (Kong + Kuma → OTLP)"
echo ""