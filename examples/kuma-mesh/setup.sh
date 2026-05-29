#!/bin/bash
set -o errexit

source helpers.sh

helm repo add kuma https://kumahq.github.io/charts
helm repo update || true

installKumaStandalone

KONG_EXISTS=$(kubectl get ns kong 2>/dev/null || echo "false")
if [ "$KONG_EXISTS" == "false" ]
then
cd ../kong-gateway/
bash setup.sh
else
echo "Skipping Kong deployment, already installed."
fi

cd ../kuma-mesh/
configureMeshIngress

kubectl create configmap grafana-dashboard-kuma \
    --namespace kuma-cp \
    --from-file=kuma-mesh.json=grafana-dashboard-kuma.json \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap grafana-dashboard-kuma -n kuma-cp grafana_dashboard=true --overwrite

DEMO_DEPLOYED=$(kubectl get ns demo || echo "false")
if [ "$DEMO_DEPLOYED" != "false" ]; then
    kubectl annotate ns demo kuma.io/sidecar-injection="enabled" --overwrite
    sleep 2 # wait to register the namespace as mesh-component by the controlplane
    kubectl -n demo delete po --all
fi
