#!/bin/bash

source ../helpers.sh
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add coredns https://coredns.github.io/helm
helm repo update
helm upgrade --install coredns-etcd bitnami/etcd --set auth.rbac.create=false --namespace dns-sample --create-namespace
sleep 3
ETCD_SERVICE_IP=$(kubectl get svc -n dns-sample coredns-etcd -o jsonpath="{.spec.clusterIP}")

templateConfigFile "values-template.yaml" "values.yaml"

helm upgrade --install coredns coredns/coredns --values=values.yaml --namespace dns-sample --create-namespace
helm upgrade --install external-dns bitnami/external-dns --namespace dns-sample --create-namespace --set coredns.etcdEndpoints=http://${ETCD_SERVICE_IP}:2379 --set provider=coredns

echo "Waiting 10 seconds!"
sleep 10
echo "Deploy sample ingress!"
kubectl delete ingress -n demo httpbin
kubectl apply -n demo -f update-httpbin-ingress.yaml
