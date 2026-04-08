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

helm repo add kyverno https://kyverno.github.io/kyverno
helm repo add policy-reporter https://kyverno.github.io/policy-reporter

helm repo update
helm upgrade --install kyverno kyverno/kyverno --namespace kyverno --create-namespace
helm upgrade --install policy-reporter policy-reporter/policy-reporter --create-namespace -n policy-reporter --set metrics.enabled=true --set api.enabled=true --set kyvernoPlugin.enabled=true --set ui.enabled=true --set ui.plugins.kyverno=true

if [ "${INGRESS_MODE}" == "haproxy" ]; then
  kubectl apply -n policy-reporter -f policy-reporter-ingress.yml
elif [ "${INGRESS_MODE}" == "kong" ]; then
  kubectl apply -f httproute-policy-reporter.yaml
fi

# Deploy samples - Pod Security Policies
kubectl apply -k https://github.com/kyverno/policies/pod-security

# Example for mutating policy
kubectl apply -f role-ns-admin.yml
kubectl apply -f label-ns-policy.yml
