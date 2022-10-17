#!/bin/bash
set -o errexit

CLUSTER_NAME=demo
SERVERS=1
AGENTS=1
HTTP_PORT=8080
HTTPS_PORT=8081
NGINX_FLAG=Yes
CALICO_FLAG=Yes

source helpers.sh

# Configuration of cluster
configValues
configureEtcHosts
uninstallCluster

# Get actual directory
export ACT_DIR=$(pwd)
top "Actual directory"
echo "$ACT_DIR"
bottom

rm -f k3d-cluster.yaml temp.yaml
( echo "cat <<EOF >k3d-cluster.yaml";
  cat k3d-cluster-template.yaml;
  echo "EOF";
) >temp.yaml
. temp.yaml
cat k3d-cluster.yaml
rm -f temp.yaml

# Create K8s cluster
top "Creating K3D cluster"
k3d cluster create -c k3d-cluster.yaml
bottom

#TODO: add PV

# Get images to local registry
docker pull kennethreitz/httpbin
docker tag kennethreitz/httpbin ${REGISTRY_NAME}.localhost:5002/kennethreitz/httpbin
docker push ${REGISTRY_NAME}.localhost:5002/kennethreitz/httpbin

# Deploy demo app
kubectl create ns demo
kubectl create deployment httpbin -n demo --image=${REGISTRY_NAME}.localhost:5002/kennethreitz/httpbin
kubectl apply -n demo -f sample-svc-nodeport.yaml
if (($NGINX_FLAG == 1)); then
    kubectl apply -n demo -f sample-ingress-nginx.yaml
else
    kubectl apply -n demo -f sample-ingress.yaml
fi