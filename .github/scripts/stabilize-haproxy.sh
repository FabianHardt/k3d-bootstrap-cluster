#!/bin/bash
# CI workaround for haproxy-ingress on k3d/GitHub runners.
#
# haproxy-ingress runs with publishService enabled and fatals at startup when
# its LoadBalancer service has no .status.loadBalancer.ingress entries
# ("service ingress-haproxy/haproxy-ingress does not (yet) have ingress
# points"). On k3d, klipper-lb does not reliably populate that status (see the
# same workaround in examples/external-dns/setup.sh), which leaves the
# controller in CrashLoopBackOff on the runners.
#
# Publish the node IPs into the service status, restart the crashing pod to
# skip the backoff, and wait for the controller to come up. No-op when the
# cluster runs without HAProxy or the controller is already healthy.
set -o errexit

if ! kubectl get deployment haproxy-ingress -n ingress-haproxy &>/dev/null; then
  echo "HAProxy ingress not installed - nothing to do."
  exit 0
fi

if kubectl -n ingress-haproxy rollout status deployment/haproxy-ingress --timeout=60s; then
  echo "HAProxy ingress is healthy."
  exit 0
fi

echo "HAProxy ingress is not ready - publishing node IPs into the service status."
LB_INGRESS_JSON=$(kubectl get nodes -o json | jq -c \
  '[.items[].status.addresses[] | select(.type=="InternalIP") | {ip: .address}]')
kubectl patch svc haproxy-ingress -n ingress-haproxy --subresource=status --type=merge \
  -p "{\"status\":{\"loadBalancer\":{\"ingress\":${LB_INGRESS_JSON}}}}"

kubectl -n ingress-haproxy delete pod -l app.kubernetes.io/name=haproxy-ingress --ignore-not-found
kubectl -n ingress-haproxy rollout status deployment/haproxy-ingress --timeout=300s
echo "HAProxy ingress recovered."
