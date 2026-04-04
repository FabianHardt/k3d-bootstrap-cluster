#!/bin/bash
set -o errexit

source helpers.sh

bold=$(tput bold)
normal=$(tput sgr0)

echo "Using management cluster context: ${bold}${MGMT_CONTEXT}${normal}"
echo "Tip: CAPI resources always live on the management cluster, regardless of your current kubeconfig/context."
echo ""

CURRENT=$(kubectl --context "${MGMT_CONTEXT}" get machinedeployment \
  "${WORKLOAD_CLUSTER}-md-0" -n default \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "unknown")

echo ""
echo "Current worker replicas: ${bold}${CURRENT}${normal}"
echo ""

read -p "Desired number of workers [${bold}${CURRENT}${normal}]: " INPUT

if [ -z "${INPUT}" ]; then
  if ! [[ "${CURRENT}" =~ ^[0-9]+$ ]]; then
    echo "Unable to determine current worker replica count. Please enter a numeric value." >&2
    exit 1
  fi
  DESIRED="${CURRENT}"
else
  DESIRED="${INPUT}"
fi

if ! [[ "${DESIRED}" =~ ^[0-9]+$ ]]; then
  echo "Desired number of workers must be a non-negative integer." >&2
  exit 1
fi
if [ "${DESIRED}" = "${CURRENT}" ]; then
  echo "No change requested."
  exit 0
fi

scaleWorkers "${DESIRED}"
