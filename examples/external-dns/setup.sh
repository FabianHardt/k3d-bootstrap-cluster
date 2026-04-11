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
# Sources depend on ingress mode: Ingress resources for HAProxy, HTTPRoutes for Kong
if [ "${INGRESS_MODE}" == "kong" ]; then
  EXTERNAL_DNS_SOURCES=("--set" "sources[0]=service" "--set" "sources[1]=gateway-httproute")
else
  EXTERNAL_DNS_SOURCES=("--set" "sources[0]=service" "--set" "sources[1]=ingress")
fi

helm upgrade --install external-dns external-dns/external-dns \
  --namespace dns-sample --create-namespace \
  --set provider.name=coredns \
  --set "env[0].name=ETCD_URLS" \
  --set "env[0].value=http://${ETCD_SERVICE_IP}:2379" \
  --set policy=sync \
  "${EXTERNAL_DNS_SOURCES[@]}"

echo "Waiting 10 seconds!"
sleep 10
if [ "${INGRESS_MODE}" == "haproxy" ]; then
  echo "Deploy sample ingress!"
  kubectl delete ingress -n demo httpbin || true
  kubectl apply -n demo -f update-httpbin-ingress.yaml

  # k3d's klipper servicelb does not populate .status.loadBalancer on the
  # HAProxy service, so the ingress controller cannot publish the Ingress
  # status address. Patch it manually with the node IPs so that the
  # controller sets Ingress .status and ExternalDNS can register the record.
  LB_INGRESS_JSON=$(kubectl get nodes -o json | jq -c '[.items[].status.addresses[] | select(.type=="InternalIP") | {ip: .address}]')
  kubectl patch svc haproxy-ingress -n ingress-haproxy --subresource=status --type=merge \
    -p "{\"status\":{\"loadBalancer\":{\"ingress\":${LB_INGRESS_JSON}}}}"

  # Annotate the Ingress once to trigger an immediate status reconciliation
  kubectl annotate ingress httpbin -n demo external-dns-trigger="$(date +%s)" --overwrite

elif [ "${INGRESS_MODE}" == "kong" ]; then
  echo "Deploy sample HTTPRoute!"
  kubectl apply -n demo -f httproute-httpbin.yaml
fi
