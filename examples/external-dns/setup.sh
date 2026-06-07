#!/bin/bash

source ../../helpers.sh

# Kong Gateway is the sole ingress controller in this cluster — ExternalDNS
# watches Gateway API HTTPRoutes and registers DNS records based on them.

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo add coredns https://coredns.github.io/helm
helm repo update

# etcd is deployed as a plain manifest using registry.k8s.io/etcd (no Bitnami dependency)
kubectl apply -f etcd.yaml
kubectl rollout status deployment/coredns-etcd -n dns-sample --timeout=120s

ETCD_SERVICE_IP=$(kubectl get svc -n dns-sample coredns-etcd -o jsonpath="{.spec.clusterIP}")

templateConfigFile "values-template.yaml" "values.yaml"

helm upgrade --install coredns coredns/coredns --values=values.yaml --namespace dns-sample --create-namespace

# external-dns: official chart (registry.k8s.io/external-dns/external-dns image)
# Watches Services and Gateway API HTTPRoutes (Kong is the sole ingress).
helm upgrade --install external-dns external-dns/external-dns \
  --namespace dns-sample --create-namespace \
  --set provider.name=coredns \
  --set "env[0].name=ETCD_URLS" \
  --set "env[0].value=http://${ETCD_SERVICE_IP}:2379" \
  --set policy=sync \
  --set "sources[0]=service" \
  --set "sources[1]=gateway-httproute"

echo "Waiting 10 seconds!"
sleep 10
echo "Deploy sample HTTPRoute!"
kubectl apply -n demo -f httproute-httpbin.yaml
