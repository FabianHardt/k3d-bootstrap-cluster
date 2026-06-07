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
  kubectl -n seaweedfs exec seaweedfs-0 -- \
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
# Expose the demo nginx via Ingress (HAProxy) or HTTPRoute (Kong) so that the
# restored page can be visited from the host browser, making the recovery
# visually obvious. Auto-detect the ingress mode the same way the Kyverno
# showcase does.
# ---------------------------------------------------------------------------
if [ "${HAPROXY_FLAG}" == "Yes" ]; then
  INGRESS_MODE="haproxy"
elif [ "${KONG_FLAG}" == "Yes" ]; then
  INGRESS_MODE="kong"
elif kubectl get ingressclass haproxy &>/dev/null; then
  echo "Auto-detected HAProxy ingress controller"
  INGRESS_MODE="haproxy"
elif kubectl get namespace kong &>/dev/null || kubectl get gatewayclass kong &>/dev/null; then
  echo "Auto-detected Kong Gateway"
  INGRESS_MODE="kong"
else
  echo "No ingress controller detected — skipping ingress/route creation."
  INGRESS_MODE="none"
fi

NGINX_URL=""
if [ "${INGRESS_MODE}" == "haproxy" ]; then
  kubectl apply -f nginx-ingress-haproxy.yaml
  NGINX_URL="http://nginx-velero.127-0-0-1.nip.io:8080/"
elif [ "${INGRESS_MODE}" == "kong" ]; then
  kubectl apply -f nginx-httproute-kong.yaml
  NGINX_URL="http://nginx-velero.127-0-0-1.nip.io:8080/"
fi

# The default httpbin sample route in namespace `demo` has no host filter and
# therefore catches any request — including requests to nginx-velero.* once the
# demo-velero namespace is gone. That would hide the "disaster" step in
# `demo.sh`, where we expect the URL to fail. Remove the wildcard routes so the
# recovery story is unambiguous.
echo "Removing wildcard httpbin routes (would mask the disaster step)…"
kubectl delete httproute httpbin -n demo --ignore-not-found
kubectl delete ingress  httpbin -n demo --ignore-not-found

echo ""
echo "Velero is ready."
if [ -n "${NGINX_URL}" ]; then
  echo "Demo nginx is exposed at:  ${NGINX_URL}"
fi
echo ""
echo "Next step: run the end-to-end demo:"
echo "    bash demo.sh"
echo ""
echo "Tip: install the Velero CLI for richer UX:"
echo "    https://velero.io/docs/main/basic-install/#install-the-cli"
