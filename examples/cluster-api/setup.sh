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
