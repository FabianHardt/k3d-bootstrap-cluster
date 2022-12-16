#!/bin/bash
set -o errexit

helm repo add kuma https://kumahq.github.io/charts
helm repo update

helm upgrade --install kuma kuma/kuma \
    --values kuma-cp-values.yaml \
    --namespace kuma-cp --create-namespace

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
  ingressClassName: kong
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

kubectl annotate ns kong-dp kuma.io/sidecar-injection="enabled" --overwrite

kubectl -n kong-dp delete po --all
echo 'Wait for kong dataplane to start with sidecar'

kubectl wait pod -n kong-dp $(kubectl -n kong-dp get pods --no-headers -o custom-columns=":metadata.name") --for condition=Available=True --timeout=300s
