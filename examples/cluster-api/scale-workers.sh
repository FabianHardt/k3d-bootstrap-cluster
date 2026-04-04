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
DESIRED=${INPUT:-${CURRENT}}

if [ "${DESIRED}" = "${CURRENT}" ]; then
  echo "No change requested."
  exit 0
fi

scaleWorkers "${DESIRED}"
