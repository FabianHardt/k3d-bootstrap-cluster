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

top "Cleaning up workload routing resources"

# The capi-demo namespace contains an Ingress that catches all traffic (host: *, path: /).
# It must be removed before re-deploying httpbin, otherwise HAProxy will keep routing to the
# now-deleted workload cluster Endpoints and return 503.
kubectl --context "${MGMT_CONTEXT}" delete namespace capi-demo --ignore-not-found 2>/dev/null || true
echo "Removed capi-demo namespace."

bottom

top "Re-deploying httpbin on management cluster"

kubectl --context "${MGMT_CONTEXT}" apply -f - <<'EOF' || true
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
      - name: httpbin
        image: kennethreitz/httpbin
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: demo
spec:
  selector:
    app: httpbin
  ports:
  - port: 80
    targetPort: 80
EOF
kubectl --context "${MGMT_CONTEXT}" apply -n demo \
  -f ../../httpbin/sample-ingress-haproxy.yaml || true

bottom

echo "Teardown complete."
