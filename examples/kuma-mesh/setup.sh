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
