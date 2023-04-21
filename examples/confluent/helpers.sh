#!/bin/bash

installConfluentOperator() {
helm upgrade --install confluent-operator \
  --values confluent-operator-values.yaml \
  --namespace confluent --create-namespace \
  confluentinc/confluent-for-kubernetes

  kubectl wait pod -n confluent $(kubectl -n confluent get pods --no-headers -o custom-columns=":metadata.name") --for condition=Ready --timeout=180s
}

installConfluentPlatform() {
  kubectl config set-context --current --namespace confluent
  echo "wait for confluent operator to be up and running"
  kubectl wait pod -n confluent $(kubectl -n confluent get pods --no-headers -o custom-columns=":metadata.name") --for condition=Ready --timeout=180s

  kubectl apply -f https://raw.githubusercontent.com/confluentinc/confluent-kubernetes-examples/master/quickstart-deploy/confluent-platform.yaml
}


createIngressResource() {
INGRESS_CLASS_NAME=$1
echo "
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: confluent-controlcenter
  namespace: confluent
  annotations:
    ingress.kubernetes.io/ssl-redirect: 'false'
spec:
  ingressClassName: $INGRESS_CLASS_NAME
  rules:
  - host: confluent.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: controlcenter
            port:
              number: 9021" | kubectl apply -f -
}