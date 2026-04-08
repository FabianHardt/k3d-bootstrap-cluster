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
# ---------------------------------------------------------------------------
# Determine ingress mode.
# Explicit flags take precedence; otherwise auto-detect from the cluster.
#   HAPROXY_FLAG=Yes  → HAProxy IngressClass + Ingress resources
#   KONG_FLAG=Yes     → Kong GatewayClass + Gateway API HTTPRoute resources
# ---------------------------------------------------------------------------
if [ "${HAPROXY_FLAG}" == "Yes" ]; then
  INGRESS_MODE="haproxy"
elif [ "${KONG_FLAG}" == "Yes" ]; then
  INGRESS_MODE="kong"
elif kubectl get ingressclass haproxy &>/dev/null 2>&1; then
  echo "Auto-detected HAProxy ingress controller"
  INGRESS_MODE="haproxy"
elif kubectl get namespace kong &>/dev/null 2>&1 || kubectl get gatewayclass kong &>/dev/null 2>&1; then
  echo "Auto-detected Kong Gateway"
  INGRESS_MODE="kong"
else
  echo "No ingress controller detected — skipping ingress/route creation."
  INGRESS_MODE="none"
fi

if [ "${INGRESS_MODE}" == "haproxy" ]; then
  kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kuma-gui
  namespace: kuma-cp
  annotations:
    haproxy-ingress.github.io/app-root: '/gui'
    ingress.kubernetes.io/ssl-redirect: 'false'
spec:
  ingressClassName: haproxy
  rules:
  - host: kuma-gui.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kuma-control-plane
            port:
              number: 5681
EOF
elif [ "${INGRESS_MODE}" == "kong" ]; then
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
fi
}

configureMeshForKongIngress() {
kubectl annotate ns kong-dp kuma.io/sidecar-injection="enabled" --overwrite
sleep 2 # wait to register the namespace as mesh-component by the controlplane
kubectl -n kong-dp delete po --all
echo 'Wait for kong dataplane to start with sidecar'
kubectl wait pod -n kong-dp $(kubectl -n kong-dp get pods --no-headers -o custom-columns=":metadata.name") --for condition=Ready --timeout=180s
}
