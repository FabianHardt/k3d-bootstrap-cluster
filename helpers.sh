#!/bin/bash

# bold text (fall back to plain text when no terminal is attached, e.g. in CI)
bold=$(tput bold 2>/dev/null || true)
normal=$(tput sgr0 2>/dev/null || true)
yes_no="(${bold}Y${normal}es/${bold}N${normal}o)"

read_value ()
{
  # NON_INTERACTIVE=1 skips the prompt and accepts the default (CI usage)
  if [ "${NON_INTERACTIVE:-0}" = "1" ]
  then
      INPUT_VALUE=$2
      echo "${1} [${2}]: ${2} (non-interactive)"
      return
  fi
  read -p "${1} [${bold}${2}${normal}]: " INPUT_VALUE
  if [ "${INPUT_VALUE}" = "" ]
  then
      INPUT_VALUE=$2
  fi
}

top()
{
  echo -e "\n\n${bold}${1}${normal}\n-------------------------------------"
}

bottom()
{
  echo -e "-------------------------------------"
}

configValues ()
{
  DEMO_DOMAIN=127-0-0-1.nip.io
  REGISTRY_NAME=registry
  # shellcheck disable=SC2034  # used via templateConfigFile (k3d-cluster-template.yaml)
  REGISTRY_FLAG=$(isYes "Yes")
  read_value "Cluster Name" "${CLUSTER_NAME}"
  CLUSTER_NAME=${INPUT_VALUE}
  read_value "Number of Masters" "${SERVERS}"
  SERVERS=${INPUT_VALUE}
  read_value "Number of Workers" "${AGENTS}"
  AGENTS=${INPUT_VALUE}
  read_value "LoadBalancer HTTP Port" "${HTTP_PORT}"
  HTTP_PORT=${INPUT_VALUE}
  read_value "LoadBalancer HTTPS Port" "${HTTPS_PORT}"
  HTTPS_PORT=${INPUT_VALUE}
  read_value "Registry Port" "${REGISTRY_PORT}"
  REGISTRY_PORT=${INPUT_VALUE}
  # shellcheck disable=SC2034  # used via templateConfigFile (k3d-cluster-template.yaml)
  HTTPBIN_NODEPORT=$((30000 + RANDOM % 40000))
  # shellcheck disable=SC2034  # used via templateConfigFile (k3d-cluster-template.yaml)
  EXTDNS_NODEPORT=$((30000 + RANDOM % 40000))
  read_value "Install Kong Gateway (Gateway API)? ${yes_no}" "${KONG_FLAG}"
  KONG_FLAG=$(isYes ${INPUT_VALUE})
  if (($KONG_FLAG == 1)); then
    HAPROXY_FLAG=No
  fi
  read_value "Install HAProxy Ingress? ${yes_no}" "${HAPROXY_FLAG}"
  HAPROXY_FLAG=$(isYes ${INPUT_VALUE})
  if (($KONG_FLAG == 1)) && (($HAPROXY_FLAG == 1)); then
    echo "ERROR: Kong Gateway and HAProxy are mutually exclusive. Please choose only one." >&2
    exit 1
  fi
  read_value "Install Calico Network? ${yes_no}" "${CALICO_FLAG}"
  CALICO_FLAG=$(isYes ${INPUT_VALUE})
  read_value "Install Headlamp Dashboard? ${yes_no}" "${DASHBOARD_FLAG}"
  DASHBOARD_FLAG=$(isYes ${INPUT_VALUE})
  read_value "Deploy httpbin sample? ${yes_no}" "${HTTPBIN_SAMPLE_FLAG}"
  HTTPBIN_SAMPLE_FLAG=$(isYes ${INPUT_VALUE})
  read_value "Enable Cluster API (CAPI) support? ${yes_no}" "${CAPI_FLAG}"
  CAPI_FLAG=$(isYes ${INPUT_VALUE})
}

isYes()
{
  if [ "${1}" = "Yes" ] || [ "${1}" = "yes" ] || [ "${1}" = "Y" ]  || [ "${1}" = "y" ];
  then
    echo 1
  else
    echo 0
  fi
}

configureEtcHosts()
{
top "Creating DEMO_DOMAIN entry in /etc/hosts"
# Prepare local /etc/hosts - add container registry hostname
grep -qxF '# Local K8s registry' /etc/hosts || echo "# Local K8s registry
127.0.0.1 ${REGISTRY_NAME}-${CLUSTER_NAME}.${DEMO_DOMAIN}
127.0.0.1 ${CLUSTER_NAME}.${DEMO_DOMAIN}
# End of section" | sudo tee -a /etc/hosts
echo 'Created /etc/hosts entry for local registry!'
bottom
}

uninstallCluster()
{
  top "Deleting ${CLUSTER_NAME} cluster if already exists"
  k3d cluster delete $CLUSTER_NAME || true
  bottom
}

templateConfigFile()
{
    rm -f $2 temp.yaml
  ( echo "cat <<EOF >$2";
    cat $1;
    echo "EOF";
  ) >temp.yaml
  . temp.yaml
  cat $2
  rm -f temp.yaml
}

deployKong()
{
  top "Installing Kong Gateway (Gateway API)"

  helm repo add kong https://charts.konghq.com || true
  helm repo update kong

  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

  kubectl create namespace kong || true

  # The kong/ingress chart bundles kong/kong as a sub-chart whose crds/ directory
  # Helm does not auto-install (Helm only processes crds/ from the top-level chart).
  # Install them explicitly from the matching sub-chart version.
  KONG_SUBCHART_TMPDIR=$(mktemp -d)
  helm pull kong/kong --version 3.2.0 --untar --untardir "${KONG_SUBCHART_TMPDIR}"
  kubectl apply -f "${KONG_SUBCHART_TMPDIR}/kong/crds/"
  rm -rf "${KONG_SUBCHART_TMPDIR}"

  kubectl apply -f manifests/kong-gateway-class.yaml
  kubectl apply -f manifests/kong-gateway.yaml

  helm upgrade --install kong kong/ingress \
    --namespace kong \
    --version 0.24.0 \
    --values manifests/kong-values.yaml

  kubectl -n kong wait --for=condition=Available=true --timeout=300s deployment/kong-gateway

  bottom
}

deploySamples()
{
  # Get images to local registry
  docker pull kennethreitz/httpbin
  docker tag kennethreitz/httpbin ${REGISTRY_NAME}-${CLUSTER_NAME}.${DEMO_DOMAIN}:${REGISTRY_PORT}/kennethreitz/httpbin
  docker push ${REGISTRY_NAME}-${CLUSTER_NAME}.${DEMO_DOMAIN}:${REGISTRY_PORT}/kennethreitz/httpbin

  templateConfigFile "httpbin/httpbin-template.yaml" "httpbin/httpbin.yaml"

  # Deploy demo app
  kubectl apply -n demo -f httpbin/httpbin.yaml
  if (($HAPROXY_FLAG == 1)); then
      top "Waiting for HAProxy ingress to become available"
      sleep 10;
      kubectl wait job/helm-install-haproxy-ingress -n kube-system --for=condition=complete --timeout=600s
      kubectl wait deployment -n ingress-haproxy haproxy-ingress --for condition=Available=True --timeout=600s
      kubectl apply -n demo -f httpbin/sample-ingress-haproxy.yaml
      bottom
  elif (($KONG_FLAG == 1)); then
      top "Applying HTTPRoute for httpbin via Kong Gateway API"
      kubectl apply -n demo -f httpbin/sample-httproute-kong.yaml
      bottom
  else
      kubectl apply -n demo -f httpbin/sample-ingress.yaml
  fi
}