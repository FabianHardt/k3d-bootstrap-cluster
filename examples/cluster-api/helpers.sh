#!/bin/bash

MGMT_CONTEXT="k3d-demo"
WORKLOAD_CLUSTER="workload-cluster"
WORKLOAD_KUBECONFIG="workload-kubeconfig.yaml"

bold=$(tput bold)
normal=$(tput sgr0)

top() {
  echo -e "\n\n${bold}${1}${normal}\n-------------------------------------"
}

bottom() {
  echo -e "-------------------------------------"
}

checkPrerequisites() {
  top "Checking prerequisites"

  if ! command -v clusterctl &> /dev/null; then
    echo "ERROR: clusterctl not found. Install via:"
    echo "  brew install clusterctl"
    echo "  or: https://cluster-api.sigs.k8s.io/user/quick-start.html#install-clusterctl"
    exit 1
  fi

  if ! kubectl config get-contexts "${MGMT_CONTEXT}" &> /dev/null; then
    echo "ERROR: Management cluster context '${MGMT_CONTEXT}' not found."
    echo "Please run create-sample.sh first (with CAPI flag enabled)."
    exit 1
  fi

  # Verify Docker socket is accessible from within the cluster
  if ! kubectl --context "${MGMT_CONTEXT}" run docker-sock-test \
    --image=busybox --restart=Never --rm -it \
    --overrides='{"spec":{"volumes":[{"name":"sock","hostPath":{"path":"/var/run/docker.sock"}}],"containers":[{"name":"busybox","image":"busybox","command":["ls","/var/run/docker.sock"],"volumeMounts":[{"name":"sock","mountPath":"/var/run/docker.sock"}]}]}}' \
    &> /dev/null; then
    echo "ERROR: Docker socket not accessible inside the management cluster."
    echo "Please recreate the cluster with CAPI_FLAG=Yes in create-sample.sh."
    exit 1
  fi

  echo "All prerequisites satisfied."
  bottom
}

configureClusterctl() {
  top "Configuring clusterctl for k3s provider"
  # Using --config flag in clusterctl init directly - no need to copy globally.
  echo "Using $(pwd)/clusterctl.yaml as clusterctl config."
  bottom
}

initializeCAPI() {
  top "Initializing Cluster API on management cluster"

  kubectl config use-context "${MGMT_CONTEXT}"

  export EXP_CLUSTER_RESOURCE_SET=true
  export CLUSTER_TOPOLOGY=true

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  clusterctl init \
    --config "${SCRIPT_DIR}/clusterctl.yaml" \
    --core cluster-api \
    --bootstrap k3s \
    --control-plane k3s \
    --infrastructure docker

  echo "Waiting for CAPI core components..."
  kubectl wait deployment -n capi-system capi-controller-manager \
    --for condition=Available=True --timeout=300s

  echo "Waiting for CAPD..."
  kubectl wait deployment -n capd-system capd-controller-manager \
    --for condition=Available=True --timeout=300s

  echo "Waiting for k3s bootstrap provider..."
  kubectl wait deployment -n capi-k3s-bootstrap-system capi-k3s-bootstrap-controller-manager \
    --for condition=Available=True --timeout=300s

  echo "Waiting for k3s control-plane provider..."
  kubectl wait deployment -n capi-k3s-control-plane-system capi-k3s-control-plane-controller-manager \
    --for condition=Available=True --timeout=300s

  bottom
}

removeHttpbinFromManagementCluster() {
  top "Removing httpbin from management cluster"

  kubectl --context "${MGMT_CONTEXT}" delete ingress httpbin -n demo --ignore-not-found
  kubectl --context "${MGMT_CONTEXT}" delete deployment httpbin -n demo --ignore-not-found
  kubectl --context "${MGMT_CONTEXT}" delete service httpbin -n demo --ignore-not-found

  echo "httpbin removed from management cluster."
  bottom
}

createWorkloadCluster() {
  top "Creating workload cluster via Cluster API"

  kubectl --context "${MGMT_CONTEXT}" apply -f workload-cluster.yaml

  echo "Waiting for control plane to be available (this takes several minutes)..."
  kubectl --context "${MGMT_CONTEXT}" wait clusters.cluster.x-k8s.io/"${WORKLOAD_CLUSTER}" \
    -n default \
    --for condition=ControlPlaneAvailable=True --timeout=600s

  echo "Waiting for control plane machine to be Running..."
  kubectl --context "${MGMT_CONTEXT}" wait machines.cluster.x-k8s.io \
    -n default \
    -l cluster.x-k8s.io/cluster-name="${WORKLOAD_CLUSTER}",cluster.x-k8s.io/control-plane \
    --for condition=Ready=True --timeout=600s

  bottom
}

patchWorkloadKubeconfig() {
  LB_PORT=$(docker inspect "${WORKLOAD_CLUSTER}-lb" \
    --format '{{(index (index .NetworkSettings.Ports "6443/tcp") 0).HostPort}}' 2>/dev/null)
  if [ -z "${LB_PORT}" ]; then
    echo "WARNING: Could not determine LB port, kubeconfig may not work from host"
    return
  fi
  if sed --version >/dev/null 2>&1; then
    sed -i -E "s|https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:6443|https://127.0.0.1:${LB_PORT}|g" \
      "${WORKLOAD_KUBECONFIG}"
  else
    sed -i '' -E "s|https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:6443|https://127.0.0.1:${LB_PORT}|g" \
      "${WORKLOAD_KUBECONFIG}"
  fi
  echo "Kubeconfig server patched to 127.0.0.1:${LB_PORT}"
}

getWorkloadKubeconfig() {
  top "Retrieving workload cluster kubeconfig"

  clusterctl get kubeconfig "${WORKLOAD_CLUSTER}" -n default > "${WORKLOAD_KUBECONFIG}"

  # CAPD uses internal Docker IPs - patch to use the LB's host port instead
  patchWorkloadKubeconfig

  echo "Kubeconfig saved to ${WORKLOAD_KUBECONFIG} (patched to 127.0.0.1:${LB_PORT})"

  bottom
}

waitForWorkloadNodes() {
  top "Waiting for workload cluster nodes"

  KUBECONFIG="${WORKLOAD_KUBECONFIG}" kubectl wait nodes --all \
    --for condition=Ready --timeout=300s

  echo ""
  KUBECONFIG="${WORKLOAD_KUBECONFIG}" kubectl get nodes

  bottom
}

connectWorkloadClusterToMgmtNetwork() {
  top "Connecting workload cluster to management network"

  MGMT_NETWORK=$(docker inspect "k3d-${MGMT_CONTEXT#k3d-}-server-0" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || \
    docker inspect "k3d-demo-server-0" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')

  echo "Management network: ${MGMT_NETWORK}"

  for CONTAINER in $(docker ps --filter "name=${WORKLOAD_CLUSTER}" --format "{{.Names}}"); do
    ALREADY=$(docker inspect "${CONTAINER}" \
      --format "{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}} {{end}}" | grep -c "${MGMT_NETWORK}" || true)
    if [ "${ALREADY}" -eq 0 ]; then
      docker network connect "${MGMT_NETWORK}" "${CONTAINER}"
      echo "Connected ${CONTAINER} to ${MGMT_NETWORK}"
    else
      echo "${CONTAINER} already in ${MGMT_NETWORK}"
    fi
  done

  bottom
}

deployHttpbinOnWorkloadCluster() {
  top "Deploying httpbin on workload cluster"

  KUBECONFIG="${WORKLOAD_KUBECONFIG}" kubectl apply -f httpbin-workload.yaml

  KUBECONFIG="${WORKLOAD_KUBECONFIG}" kubectl wait deployment httpbin -n demo \
    --for condition=Available=True --timeout=300s

  bottom

  connectWorkloadClusterToMgmtNetwork

  top "Exposing httpbin via management cluster ingress"

  # Get the worker's IP on the management network (set after connectWorkloadClusterToMgmtNetwork)
  MGMT_NETWORK=$(docker inspect "k3d-demo-server-0" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
  WORKER_CONTAINER=$(docker ps --filter "name=${WORKLOAD_CLUSTER}-md" --format "{{.Names}}" | head -1)
  WORKER_IP=$(docker inspect "${WORKER_CONTAINER}" \
    --format "{{(index .NetworkSettings.Networks \"${MGMT_NETWORK}\").IPAddress}}")

  kubectl --context "${MGMT_CONTEXT}" apply -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: capi-demo
---
apiVersion: v1
kind: Endpoints
metadata:
  name: httpbin-workload
  namespace: capi-demo
subsets:
  - addresses:
      - ip: ${WORKER_IP}
    ports:
      - port: 30080
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin-workload
  namespace: capi-demo
spec:
  ports:
    - port: 80
      targetPort: 30080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbin-workload
  namespace: capi-demo
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: haproxy
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: httpbin-workload
                port:
                  number: 80
EOF

  echo ""
  echo "HTTPBin is accessible via the management cluster load balancer:"
  echo "  http://127-0-0-1.nip.io:8080"
  echo ""
  echo "To use the workload cluster directly: export KUBECONFIG=${WORKLOAD_KUBECONFIG}"

  bottom
}

scaleWorkers() {
  REPLICAS=$1
  top "Scaling worker nodes to ${REPLICAS}"

  kubectl --context "${MGMT_CONTEXT}" scale machinedeployment \
    "${WORKLOAD_CLUSTER}-md-0" -n default --replicas="${REPLICAS}"

  # Background loop: connect new containers to mgmt network + remove CAPD cloud-provider taint
  MGMT_NETWORK=$(docker inspect "k3d-demo-server-0" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
  (
    DEADLINE=$(( $(date +%s) + 600 ))
    while [ "$(date +%s)" -lt "${DEADLINE}" ]; do
      # Connect new containers to management network
      for CONTAINER in $(docker ps --filter "name=${WORKLOAD_CLUSTER}" --format "{{.Names}}"); do
        ALREADY=$(docker inspect "${CONTAINER}" \
          --format "{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}} {{end}}" \
          2>/dev/null | grep -c "${MGMT_NETWORK}" || true)
        if [ "${ALREADY}" -eq 0 ]; then
          docker network connect "${MGMT_NETWORK}" "${CONTAINER}" 2>/dev/null && \
            echo "  Connected ${CONTAINER} to ${MGMT_NETWORK}"
        fi
      done
      # Remove cloud-provider taint that CAPD sets - breaks the bootstrap deadlock in local Docker demos
      KUBECONFIG="${WORKLOAD_KUBECONFIG}" kubectl get nodes \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[*].key}{"\n"}{end}' \
        2>/dev/null | grep "cloudprovider.kubernetes.io/uninitialized" | awk '{print $1}' | \
      while read -r NODE; do
        KUBECONFIG="${WORKLOAD_KUBECONFIG}" kubectl taint node "${NODE}" \
          node.cloudprovider.kubernetes.io/uninitialized- 2>/dev/null && \
          echo "  Removed cloud-provider taint from ${NODE}"
      done
      sleep 5
    done
  ) &
  CONNECT_PID=$!

  echo "Waiting for ${REPLICAS} machines to be ready..."
  SECONDS=0
  while true; do
    READY=$(kubectl --context "${MGMT_CONTEXT}" get machinedeployment \
      "${WORKLOAD_CLUSTER}-md-0" -n default \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    [ "${READY}" = "${REPLICAS}" ] && break
    [ "${SECONDS}" -ge 600 ] && echo "Timeout waiting for machines" && kill "${CONNECT_PID}" 2>/dev/null && exit 1
    echo "  Ready: ${READY:-0}/${REPLICAS} — waiting..."
    sleep 10
  done

  kill "${CONNECT_PID}" 2>/dev/null || true
  wait "${CONNECT_PID}" 2>/dev/null || true

  echo ""
  KUBECONFIG="${WORKLOAD_KUBECONFIG}" kubectl get nodes

  bottom
}
