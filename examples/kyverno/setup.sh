#!/bin/bash

source ../../helpers.sh

# Kong Gateway is the sole ingress controller in this cluster — Policy
# Reporter UI is exposed via a Gateway API HTTPRoute.

helm repo add kyverno https://kyverno.github.io/kyverno
helm repo add policy-reporter https://kyverno.github.io/policy-reporter

helm repo update
helm upgrade --install kyverno kyverno/kyverno --namespace kyverno --create-namespace
helm upgrade --install policy-reporter policy-reporter/policy-reporter --create-namespace -n policy-reporter --set metrics.enabled=true --set api.enabled=true --set kyvernoPlugin.enabled=true --set ui.enabled=true --set ui.plugins.kyverno=true

kubectl apply -f httproute-policy-reporter.yaml

# Deploy samples - Pod Security Policies
kubectl apply -k https://github.com/kyverno/policies/pod-security

# Example for mutating policy
kubectl apply -f role-ns-admin.yml
kubectl apply -f label-ns-policy.yml
