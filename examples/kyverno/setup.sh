#!/bin/bash

source ../../helpers.sh

helm repo add kyverno https://kyverno.github.io/kyverno
helm repo add policy-reporter https://kyverno.github.io/policy-reporter

helm repo update
helm upgrade --install kyverno kyverno/kyverno --namespace kyverno --create-namespace
helm upgrade --install policy-reporter policy-reporter/policy-reporter --create-namespace -n policy-reporter --set metrics.enabled=true --set api.enabled=true --set kyvernoPlugin.enabled=true --set ui.enabled=true --set ui.plugins.kyverno=true

kubectl apply -n policy-reporter -f policy-reporter-ingress.yml

# Deploy samples - Pod Security Policies
kubectl apply -k https://github.com/kyverno/policies/pod-security

# Example for mutating policy
kubectl apply -f role-ns-admin.yml
kubectl apply -f label-ns-policy.yml
