#!/bin/bash
set -o errexit

source helpers.sh

helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

installConfluentOperator

installConfluentPlatform

KONG_EXISTS=$(kubectl get ns kong-cp || echo "false")
if [ "$KONG_EXISTS" == "false" ]
then
  createIngressResource nginx
else
  createIngressResource kong
fi
