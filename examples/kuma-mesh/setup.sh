#!/bin/bash
set -o errexit

source helpers.sh

helm repo add kuma https://kumahq.github.io/charts
helm repo update

installKumaStandalone

KONG_EXISTS=$(kubectl get ns kong-cp || echo "false")
if [ "$KONG_EXISTS" == "false" ]
then
cd ../kong-gateway/
bash setup.sh
else
echo "Skipping kong deployment, already installed"
fi

cd ../kuma-mesh/
configureMeshForKongIngress


DEMO_DEPLOYED=$(kubectl get ns demo || echo "false")
if [ "$DEMO_DEPLOYED" != "false" ]; then
kubectl annotate ns demo kuma.io/sidecar-injection="enabled" --overwrite
sleep 2 # wait to register the namespace as mesh-component by the controlplane
kubectl -n demo delete po --all
fi
