#!/bin/bash

LICENSE_FILE=license.json

# Central Kong component versions (single source of truth)
source "$(dirname "${BASH_SOURCE[0]}")/../../kong-versions.env"
# kong/kong sub-chart version bundled in kong/ingress ${KONG_INGRESS_CHART_VERSION}
KONG_SUBCHART_VERSION=3.2.0

installIngressController() {
	# Preconditions
kubectl create namespace kong || true

# Helm only auto-installs CRDs from the top-level chart's crds/ directory.
# kong/ingress has no crds/ directory — the configuration.konghq.com CRDs live
# in the bundled kong/kong sub-chart and must be applied explicitly.
TMPDIR=$(mktemp -d)
helm pull kong/kong --version "${KONG_SUBCHART_VERSION}" --untar --untardir "${TMPDIR}"
kubectl apply -f "${TMPDIR}/kong/crds/"
rm -rf "${TMPDIR}"

kubectl apply -f gateway-class.yaml
kubectl apply -f gateway.yaml

helm upgrade --install kong kong/ingress --version "${KONG_INGRESS_CHART_VERSION}" --values values.yaml --namespace kong \
  --set gateway.image.tag="${KONG_GATEWAY_VERSION}" \
  --set controller.ingressController.image.repository=kong/kubernetes-ingress-controller \
  --set controller.ingressController.image.tag="${KONG_KIC_VERSION}"

if [[ -f ${LICENSE_FILE} ]]; then
echo "${LICENSE_FILE} exists. Using it!"

echo "
apiVersion: configuration.konghq.com/v1alpha1
kind: KongLicense
metadata:
  name: kong-license
rawLicenseString: '$(cat "${LICENSE_FILE}")'
" | kubectl apply -f -
fi

echo "Waiting for Kong Ingress Controller Pods to be ready..."
kubectl -n kong wait --for=condition=Available=true --timeout=120s deployment/kong-gateway
}
