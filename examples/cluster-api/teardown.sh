#!/bin/bash
set -o errexit

source helpers.sh

top "Deleting workload cluster"

kubectl --context "${MGMT_CONTEXT}" delete cluster "${WORKLOAD_CLUSTER}" --ignore-not-found

echo "Waiting for workload cluster to be fully deleted..."
kubectl --context "${MGMT_CONTEXT}" wait cluster/"${WORKLOAD_CLUSTER}" \
  --for=delete --timeout=600s 2>/dev/null || true

removeWorkloadKubeconfig

rm -f "${WORKLOAD_KUBECONFIG}"
echo "Removed ${WORKLOAD_KUBECONFIG}"

bottom

top "Re-deploying httpbin on management cluster"

kubectl --context "${MGMT_CONTEXT}" apply -n demo \
  -f ../../httpbin/sample-ingress-haproxy.yaml || true

bottom

echo "Teardown complete."
