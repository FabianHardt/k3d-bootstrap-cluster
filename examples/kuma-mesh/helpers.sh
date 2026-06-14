#!/bin/bash

installKumaStandalone() {
# Fix: detect the active CNI so Kuma chains onto the right conflist (see CHANGELOG).
local cni_conf
if kubectl -n kube-system get daemonset cilium >/dev/null 2>&1; then
  cni_conf=05-cilium.conflist
elif kubectl -n kube-system get daemonset calico-node >/dev/null 2>&1; then
  cni_conf=10-calico.conflist
else
  cni_conf=10-flannel.conflist
fi
echo "Kuma CNI will chain onto the primary CNI conflist: ${cni_conf}"

helm upgrade --install kuma kuma/kuma \
    --values standalone-cp-values.yaml \
    --set cni.confName="${cni_conf}" \
    --namespace kuma-cp --create-namespace
kubectl wait deployment kuma-control-plane -n kuma-cp --for=condition=Available=true --timeout=300s
# Wait for the mutating webhook to be ready before any sidecar injection can happen
kubectl wait --for=condition=Ready pod -l app=kuma-control-plane -n kuma-cp --timeout=120s
}

configureMeshIngress() {
# Kong Gateway is the sole ingress controller in this cluster — expose the
# Kuma GUI via a Gateway API HTTPRoute.
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kuma-gui
  namespace: kuma-cp
spec:
  parentRefs:
  - name: kong
    namespace: kong
    kind: Gateway
  hostnames:
  - kuma-gui.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: kuma-control-plane
      port: 5681
EOF
}
