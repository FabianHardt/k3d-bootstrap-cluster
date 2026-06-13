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

checkPrerequisites()
{
  top "Checking prerequisites"

  # Required CLI tools. k3d drives the container engine through the Docker
  # API, so a Docker-compatible CLI + engine is mandatory.
  missing=""
  for tool in docker k3d kubectl helm jq
  do
    command -v "${tool}" >/dev/null 2>&1 || missing="${missing} ${tool}"
  done
  if [ -n "${missing}" ]
  then
    echo "ERROR: missing required tool(s):${missing}"
    echo "Install them and make sure they are on your PATH (see README.md)."
    exit 1
  fi

  # A reachable Docker engine is required. This catches a stopped Docker
  # Desktop / Colima, and Rancher Desktop configured with the containerd
  # engine (no Docker socket, so k3d cannot run).
  if ! docker info >/dev/null 2>&1
  then
    echo "ERROR: cannot reach a Docker engine ('docker info' failed)."
    echo "  - Docker Desktop / Colima: make sure the VM is running."
    echo "  - Rancher Desktop: choose the 'dockerd (moby)' container engine,"
    echo "    not 'containerd' — k3d needs a Docker socket."
    exit 1
  fi

  echo "All required tools found; Docker engine reachable."
  bottom
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
  read_value "Install Cilium Network? ${yes_no}" "${CILIUM_FLAG}"
  CILIUM_FLAG=$(isYes ${INPUT_VALUE})
  if (($CILIUM_FLAG == 1)); then
    CALICO_FLAG=No
  fi
  read_value "Install Calico Network? ${yes_no}" "${CALICO_FLAG}"
  CALICO_FLAG=$(isYes ${INPUT_VALUE})
  if (($CILIUM_FLAG == 1)) && (($CALICO_FLAG == 1)); then
    echo "ERROR: Cilium and Calico are mutually exclusive. Please choose only one." >&2
    exit 1
  fi
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

deployCilium()
{
  top "Installing Cilium CNI"

  CILIUM_VERSION=1.19.4

  # Pull on the host and import: in-node pulls can stall on NATed networks
  # (e.g. Docker Desktop), and the nodes have no CNI yet anyway.
  docker pull quay.io/cilium/cilium:v${CILIUM_VERSION}
  docker pull quay.io/cilium/operator-generic:v${CILIUM_VERSION}

  # Import a single-platform tarball for the node architecture. Docker
  # Desktop / Rancher Desktop with the containerd image store keep the full
  # multi-arch index locally even after a "--platform" pull, so
  # "k3d image import <image>" exports the index and the node-side ctr aborts
  # on the absent other-platform blobs ("content digest sha256:...: not
  # found"). "docker save --platform" exports only the node's platform, which
  # imports cleanly. Daemons without that flag (older Docker, whose classic
  # store is single-platform anyway) fall back to a plain import. The arch is
  # derived from uname(1) so it does not depend on the runtime being Docker.
  case "$(uname -m)" in
    x86_64 | amd64) NODE_ARCH=amd64 ;;
    aarch64 | arm64) NODE_ARCH=arm64 ;;
    *) NODE_ARCH="$(uname -m)" ;;
  esac
  if docker save --help 2>&1 | grep -q -- '--platform'
  then
    CILIUM_IMG_TAR=$(mktemp -t cilium-images.XXXXXX)
    docker save --platform "linux/${NODE_ARCH}" \
      quay.io/cilium/cilium:v${CILIUM_VERSION} \
      quay.io/cilium/operator-generic:v${CILIUM_VERSION} \
      -o "${CILIUM_IMG_TAR}"
    k3d image import -c ${CLUSTER_NAME} "${CILIUM_IMG_TAR}"
    rm -f "${CILIUM_IMG_TAR}"
  else
    k3d image import -c ${CLUSTER_NAME} \
      quay.io/cilium/cilium:v${CILIUM_VERSION} \
      quay.io/cilium/operator-generic:v${CILIUM_VERSION}
  fi

  helm repo add cilium https://helm.cilium.io || true
  helm repo update cilium

  # Installed from the host: a k3s HelmChart job pod would never be scheduled
  # on the CNI-less, NotReady nodes (chicken-and-egg).
  helm upgrade --install cilium cilium/cilium \
    --namespace kube-system \
    --version ${CILIUM_VERSION} \
    --values manifests/cilium-values.yaml

  kubectl rollout status daemonset/cilium -n kube-system --timeout=600s
  kubectl wait node --all --for=condition=Ready --timeout=300s

  bottom
}

deployKong()
{
  top "Installing Kong Gateway (Gateway API)"

  helm repo add kong https://charts.konghq.com || true
  helm repo update kong

  # Install experimental Gateway API CRDs (superset of standard).
  # Remove the ValidatingAdmissionPolicy that blocks experimental-on-top-of-standard
  # upgrades — Kuma and other mesh controllers need the experimental CRDs.
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

  top "Applying HTTPRoute for httpbin via Kong Gateway API"
  kubectl apply -n demo -f httpbin/sample-httproute-kong.yaml
  bottom
}
