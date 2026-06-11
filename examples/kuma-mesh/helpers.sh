#!/bin/bash

installKumaStandalone() {
helm upgrade --install kuma kuma/kuma \
    --values standalone-cp-values.yaml \
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
