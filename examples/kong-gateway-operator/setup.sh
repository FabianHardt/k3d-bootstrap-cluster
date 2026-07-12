#!/bin/bash

# Kong component versions (chart + KIC) come from the central kong-versions.env.
source "$(dirname "${BASH_SOURCE[0]}")/../../kong-versions.env"

# include OpenBao setup first
OPENBAO_EXISTS=$(kubectl get ns openbao || echo "false")

if [ "$OPENBAO_EXISTS" == "false" ]
then
cd ../openbao/ || exit 1
bash setup.sh
else
echo "Skipping OpenBao deployment. Already there."
fi

echo "\nInstall Gateway API extension"
kubectl delete validatingadmissionpolicy safe-upgrades.gateway.networking.k8s.io --ignore-not-found
kubectl delete validatingadmissionpolicybinding safe-upgrades.gateway.networking.k8s.io --ignore-not-found
curl -sL https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml | \
  python3 -c "
import sys
docs = sys.stdin.read().split('\n---\n')
excluded_kinds = (
    'kind: ValidatingAdmissionPolicy',
    'kind: ValidatingAdmissionPolicyBinding',
)
print('\n---\n'.join(d for d in docs if not any(kind in d for kind in excluded_kinds)))
" | kubectl apply --server-side -f -

echo "\nUpdating cert-manager to work with Gateway API"
helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager \
  --set crds.enabled=true \
  --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
  --set config.kind="ControllerConfiguration" \
  --set config.enableGatewayAPI=true

kubectl rollout restart deployment cert-manager -n cert-manager

kubectl -n cert-manager wait --for=condition=Available=true --timeout=120s deployment/cert-manager

cd ../kong-gateway-operator/ || exit 1

echo "\nInstall Kong Gateway Operator"
helm repo add kong https://charts.konghq.com
helm repo update kong

# The base cluster ships KIC-managed Kong (create-sample's deployKong, Helm release
# "kong"); the Kong Operator manages its OWN Kong and its unified chart owns the same
# configuration.konghq.com CRDs. Unlike the legacy gateway-operator chart (CRDs in
# crds/, silently skipped if present), the new chart renders them as owned templates,
# so Helm refuses to adopt the KIC-owned CRDs ("invalid ownership metadata"). Remove
# the KIC install first — no Kong CRs exist yet on a fresh cluster, so this is safe.
helm uninstall kong -n kong 2>/dev/null || true
kubectl get crd -o name 2>/dev/null | grep 'configuration.konghq.com$' | xargs -r kubectl delete --ignore-not-found

# We install the Gateway API CRDs ourselves (experimental channel, above), so
# disable the chart's own Gateway API CRD install — otherwise its server-side apply
# conflicts with ours ("conflict ... gateway.networking.k8s.io/channel") and the
# whole helm install aborts. The KO conversion webhook (enabled by default) keeps
# the deprecated GatewayConfiguration v1beta1 appliable.
helm upgrade --install kgo kong/kong-operator --version "${KONG_OPERATOR_CHART_VERSION}" \
  -n kong-system --create-namespace --reset-values \
  --set gwapi-standard-crds.enabled=false \
  --set gwapi-experimental-crds.enabled=false

kubectl -n kong-system wait --for=condition=Available=true --timeout=120s deployment/kgo-kong-operator-controller-manager

# GatewayClass "kong" may already exist from kong-gateway example with a different controllerName — recreate it
kubectl delete gatewayclass kong --ignore-not-found
# Inject the central KIC version into the control-plane image before applying.
sed "s|__KONG_KIC_VERSION__|${KONG_KIC_VERSION}|" gateway-configuration.yaml | kubectl apply -f -

echo "\nConfigure HTTPRoute for httpbin"
kubectl apply -f httproute-httpbin.yaml
