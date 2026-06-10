#!/bin/bash
# CI workaround for haproxy-ingress on k3d/GitHub runners.
#
# haproxy-ingress runs with publishService enabled and exits ("service
# ingress-haproxy/haproxy-ingress does not (yet) have ingress points") as soon
# as its LoadBalancer service has no .status.loadBalancer.ingress entries —
# both at startup and whenever the service watch sees the status disappear.
# On the runners k3s/klipper populates that status briefly and then clears it
# again (locally it stays, see the related workaround in
# examples/external-dns/setup.sh), leaving the controller in CrashLoopBackOff.
# Patching the status back does not help: k3s actively reverts it to {}.
#
# Instead, drop the --publish-service argument from the deployment for the
# lifetime of the CI job. The controller then ignores the service status
# entirely; only the publishing of Ingress status addresses is lost, the
# traffic path is unaffected. manifests/haproxy-helm.yaml stays unchanged for
# local use. No-op when the cluster runs without HAProxy.
set -o errexit

if ! kubectl -n kube-system get helmchart haproxy-ingress &>/dev/null; then
  echo "HAProxy ingress not installed - nothing to do."
  exit 0
fi

kubectl -n kube-system wait job/helm-install-haproxy-ingress \
  --for=condition=complete --timeout=300s

for _ in $(seq 1 30); do
  kubectl -n ingress-haproxy get deployment haproxy-ingress &>/dev/null && break
  sleep 5
done

echo "Removing --publish-service from the haproxy-ingress deployment."
ARGS=$(kubectl -n ingress-haproxy get deployment haproxy-ingress -o json \
  | jq -c '[.spec.template.spec.containers[0].args[] | select(startswith("--publish-service") | not)]')
kubectl -n ingress-haproxy patch deployment haproxy-ingress --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":${ARGS}}]"

kubectl -n ingress-haproxy rollout status deployment/haproxy-ingress --timeout=300s
echo "HAProxy ingress is healthy."
