#!/bin/bash
set -o errexit

source helpers.sh

checkPrerequisites

configureClusterctl

initializeCAPI

removeHttpbinFromManagementCluster

createWorkloadCluster

getWorkloadKubeconfig

waitForWorkloadNodes

deployHttpbinOnWorkloadCluster

# mergeWorkloadKubeconfig switches the active context to the workload cluster.
# Switch back so subsequent commands (scale-workers.sh, teardown.sh) pick up the right context.
kubectl config use-context "${MGMT_CONTEXT}" > /dev/null
echo "Active context restored to: ${MGMT_CONTEXT}"
