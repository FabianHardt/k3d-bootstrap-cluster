#!/bin/bash

installKumaStandalone() {
helm upgrade --install kuma kuma/kuma \
    --values standalone-cp-values.yaml \
    --namespace kuma-cp --create-namespace
}

configureMeshForKongIngress() {
createIngressResource kong

kubectl annotate ns kong-dp kuma.io/sidecar-injection="enabled" --overwrite
sleep 2 # wait to register the namespace as mesh-component by the controlplane
kubectl -n kong-dp delete po --all
echo 'Wait for kong dataplane to start with sidecar'
kubectl wait pod -n kong-dp $(kubectl -n kong-dp get pods --no-headers -o custom-columns=":metadata.name") --for condition=Ready --timeout=180s
}

createIngressResource() {
INGRESS_CLASS_NAME=$1
echo "
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kuma-gui
  namespace: kuma-cp
  annotations:
    nginx.ingress.kubernetes.io/app-root: '/gui'
    ingress.kubernetes.io/ssl-redirect: 'false'
spec:
  ingressClassName: $INGRESS_CLASS_NAME
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
              number: 5681" | kubectl apply -f -
}