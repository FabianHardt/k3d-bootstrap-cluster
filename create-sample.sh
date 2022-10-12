#!/bin/bash

# Prepare local /etc/hosts - add container registry hostname
grep -qxF '# Local K8s registry' /etc/hosts || echo "# Local K8s registry
127.0.0.1 ocregistry.localhost
# End of section" | sudo tee -a /etc/hosts

# Create K8s cluster
k3d cluster create -c k3d-cluster.yaml

# Get images to local registry
docker pull kennethreitz/httpbin
docker tag kennethreitz/httpbin ocregistry.localhost:5002/kennethreitz/httpbin
docker push ocregistry.localhost:5002/kennethreitz/httpbin

# Deploy demo app
kubectl create ns demo
kubectl create deployment httpbin -n demo --image=ocregistry.localhost:5002/kennethreitz/httpbin
kubectl apply -n demo -f sample-svc-nodeport.yaml
kubectl apply -n demo -f sample-ingress.yaml