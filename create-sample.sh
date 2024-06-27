#!/bin/bash
set -o errexit

CLUSTER_NAME=demo
SERVERS=1
AGENTS=1
HTTP_PORT=8080
HTTPS_PORT=8081
REGISTRY_PORT=5002
NGINX_FLAG=Yes
CALICO_FLAG=Yes
DASHBOARD_FLAG=No
HTTPBIN_SAMPLE_FLAG=Yes

source helpers.sh

export K3D_FIX_DNS=1
export K3D_FIX_MOUNTS=1

# Configuration of cluster
configValues
if [ $DEMO_DOMAIN != "127-0-0-1.nip.io" ]
then
  configureEtcHosts
fi
uninstallCluster

# Get actual directory
export ACT_DIR=$(pwd)
top "Actual directory"
echo "$ACT_DIR"
bottom

templateConfigFile "k3d-cluster-template.yaml" "k3d-cluster.yaml"

# Create K8s cluster
top "Creating K3D cluster"
k3d cluster create -c k3d-cluster.yaml
bottom

top "Update kubeconfig"
  sleep 5

  kubectl config use-context k3d-${CLUSTER_NAME}
  kubectl cluster-info
bottom

# add taint to server nodes
for (( i=0; i<$SERVERS; i++ ))
do
    kubectl taint nodes k3d-${CLUSTER_NAME}-server-${i} node-role.kubernetes.io/master:NoSchedule
done

# add role labels to worker nodes
for (( i=0; i<$AGENTS; i++ ))
do
    kubectl label nodes k3d-${CLUSTER_NAME}-agent-${i} node-role.kubernetes.io/worker=true node-role.kubernetes.io/data-plane=true
done

if (($HTTPBIN_SAMPLE_FLAG == 1)); then
  top "Provisioning Persistent Volume"
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: k3d-pv
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /k3dvol
EOF
  bottom
  deploySamples
fi
