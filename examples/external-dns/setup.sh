#!/bin/bash

source ../../helpers.sh

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

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add coredns https://coredns.github.io/helm
helm repo update
helm upgrade --install coredns-etcd bitnami/etcd --set auth.rbac.create=false --namespace dns-sample --create-namespace
sleep 3
ETCD_SERVICE_IP=$(kubectl get svc -n dns-sample coredns-etcd -o jsonpath="{.spec.clusterIP}")

templateConfigFile "values-template.yaml" "values.yaml"

helm upgrade --install coredns coredns/coredns --values=values.yaml --namespace dns-sample --create-namespace
helm upgrade --install external-dns bitnami/external-dns --namespace dns-sample --create-namespace --set coredns.etcdEndpoints=http://${ETCD_SERVICE_IP}:2379 --set provider=coredns

echo "Waiting 10 seconds!"
sleep 10
if [ "${INGRESS_MODE}" == "haproxy" ]; then
  echo "Deploy sample ingress!"
  kubectl delete ingress -n demo httpbin || true
  kubectl apply -n demo -f update-httpbin-ingress.yaml
elif [ "${INGRESS_MODE}" == "kong" ]; then
  echo "Deploy sample HTTPRoute!"
  kubectl apply -n demo -f httproute-httpbin.yaml
fi
