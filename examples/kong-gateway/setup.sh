#!/bin/bash
set -o errexit

source helpers.sh

helm repo add kong https://charts.konghq.com
helm repo update

# Install Kong Controlplane
installControlPlane

# Install Kong Dataplane
installDataPlane

# Install Kong Ingress controller
installIngressController