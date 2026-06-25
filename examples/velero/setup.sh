#!/bin/bash
set -o errexit

source ../../helpers.sh

# ---------------------------------------------------------------------------
# Dependency: SeaweedFS (S3-compatible backup target). Deploy it if missing.
# ---------------------------------------------------------------------------
SEAWEEDFS_EXISTS=$(kubectl get ns seaweedfs --ignore-not-found -o name)

if [ -z "${SEAWEEDFS_EXISTS}" ]; then
  echo "SeaweedFS not found — deploying it as Velero's backup target."
  cd ../seaweedfs/
  bash setup.sh velero
  cd ../velero/
else
  echo "SeaweedFS already present — ensuring 'velero' bucket exists."
  SEAWEEDFS_POD="$(kubectl -n seaweedfs get pod \
    -l app.kubernetes.io/component=seaweedfs-all-in-one \
    -o jsonpath='{.items[0].metadata.name}')"
  kubectl -n seaweedfs exec "${SEAWEEDFS_POD}" -- \
    sh -c "echo 's3.bucket.create -name velero' | weed shell -master localhost:9333 -filer localhost:8888" \
    || true
fi

# ---------------------------------------------------------------------------
# Install Velero via Helm, configured against the in-cluster SeaweedFS S3.
# ---------------------------------------------------------------------------
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --values velero-values.yaml

kubectl -n velero rollout status deployment/velero --timeout=300s
kubectl -n velero rollout status daemonset/node-agent --timeout=300s

# ---------------------------------------------------------------------------
# Deploy the demo workload (namespace demo-velero with an nginx + PVC).
# ---------------------------------------------------------------------------
kubectl apply -f demo-app.yaml
kubectl -n demo-velero rollout status deployment/nginx --timeout=120s

# ---------------------------------------------------------------------------
# Expose the demo nginx via a Kong Gateway HTTPRoute so that the restored page
# can be visited from the host browser, making the recovery visually obvious.
# ---------------------------------------------------------------------------
kubectl apply -f nginx-httproute-kong.yaml
NGINX_URL="http://nginx-velero.127-0-0-1.nip.io:8080/"

# The default httpbin sample HTTPRoute in namespace `demo` has no host filter
# and therefore catches any request — including requests to nginx-velero.*
# once the demo-velero namespace is gone. That would hide the "disaster" step
# in `demo.sh`, where we expect the URL to fail. Remove the wildcard route so
# the recovery story is unambiguous.
echo "Removing wildcard httpbin route (would mask the disaster step)…"
kubectl delete httproute httpbin -n demo --ignore-not-found

echo ""
echo "Velero is ready."
echo "Demo nginx is exposed at:  ${NGINX_URL}"
echo ""
echo "Next step: run the end-to-end demo:"
echo "    bash demo.sh"
echo ""
echo "Tip: install the Velero CLI for richer UX:"
echo "    https://velero.io/docs/main/basic-install/#install-the-cli"
