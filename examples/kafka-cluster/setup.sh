#!/bin/bash
set -o errexit

source ../../helpers.sh

# ---------------------------------------------------------------------------
# Determine ingress mode.
# Explicit flags take precedence; otherwise auto-detect from the cluster.
#   HAPROXY_FLAG=Yes  → HAProxy IngressClass
#   KONG_FLAG=Yes     → Kong IngressClass
# ---------------------------------------------------------------------------
if [ "${HAPROXY_FLAG}" == "Yes" ]; then
  INGRESS_MODE="haproxy"
elif [ "${KONG_FLAG}" == "Yes" ]; then
  INGRESS_MODE="kong"
elif kubectl get ingressclass haproxy &>/dev/null 2>&1; then
  echo "Auto-detected HAProxy ingress controller"
  INGRESS_MODE="haproxy"
elif kubectl get namespace kong &>/dev/null 2>&1 || kubectl get gatewayclass kong &>/dev/null 2>&1; then
  echo "Auto-detected Kong Gateway"
  INGRESS_MODE="kong"
else
  echo "No ingress controller detected — UIs will be accessible via port-forward only."
  INGRESS_MODE="none"
fi

# ---------------------------------------------------------------------------
# Install Strimzi operator
# Requires at least 3 worker nodes for the required pod anti-affinity to be
# satisfied. Run 'k3d cluster create ... --agents 3' before running this script.
# ---------------------------------------------------------------------------

helm repo add kafbat-ui https://kafbat.github.io/helm-charts
helm repo update || true

kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -

# Strimzi 1.0.0 is published via OCI — no helm repo add needed.
helm upgrade --install strimzi-kafka-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
  --namespace strimzi-system \
  --create-namespace \
  --version 1.0.0 \
  --values strimzi-operator-values.yaml \
  --wait

kubectl wait deployment/strimzi-cluster-operator \
  -n strimzi-system --for=condition=Available=true --timeout=120s

# ---------------------------------------------------------------------------
# Deploy Kafka cluster (KRaft combined mode, 3 brokers)
# ---------------------------------------------------------------------------

kubectl apply -f cluster/kafka-node-pool.yaml
kubectl apply -f cluster/kafka-cluster.yaml

echo "Waiting for Kafka cluster to become ready (this may take several minutes)..."
kubectl wait kafka/kafka-cluster \
  -n kafka --for=condition=Ready --timeout=600s

# ---------------------------------------------------------------------------
# Deploy Kafka HTTP Bridge
# ---------------------------------------------------------------------------
kubectl apply -f cluster/kafka-bridge.yaml

kubectl wait kafkabridge/kafka-bridge \
  -n kafka --for=condition=Ready --timeout=180s

# Expose the Bridge via Ingress
if [ "${INGRESS_MODE}" != "none" ]; then
  kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-bridge
  namespace: kafka
  annotations:
    kubernetes.io/ingress.class: ${INGRESS_MODE}
spec:
  ingressClassName: ${INGRESS_MODE}
  rules:
    - host: kafka-bridge.127-0-0-1.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kafka-bridge-bridge-service
                port:
                  number: 8080
EOF
fi

# ---------------------------------------------------------------------------
# Deploy Apicurio Registry Operator + Registry instance (Kafka SQL storage)
# ---------------------------------------------------------------------------
APICURIO_VERSION="3.2.4"
APICURIO_NS="apicurio-system"

kubectl create namespace "${APICURIO_NS}" --dry-run=client -o yaml | kubectl apply -f -

curl -sSL "https://raw.githubusercontent.com/Apicurio/apicurio-registry/refs/tags/v${APICURIO_VERSION}/operator/install/apicurio-registry-operator-${APICURIO_VERSION}.yaml" \
  | sed "s/PLACEHOLDER_NAMESPACE/${APICURIO_NS}/g" \
  | kubectl -n "${APICURIO_NS}" apply -f -

kubectl wait deployment/apicurio-registry-operator-v${APICURIO_VERSION} \
  -n "${APICURIO_NS}" --for=condition=Available=true --timeout=120s

# Kafka SQL journal topic (unlimited retention, compaction off — raw event log)
kubectl apply -f registry/apicurio-journal-topic.yaml

# Registry instance — operator reconciles and creates app/ui deployments + services
kubectl apply -f registry/apicurio-registry.yaml

kubectl wait apicurioregistry3/apicurio-registry \
  -n kafka --for=condition=Ready --timeout=300s

# Expose the Registry API via Ingress (service created by the operator)
if [ "${INGRESS_MODE}" != "none" ]; then
  kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apicurio-registry
  namespace: kafka
  annotations:
    kubernetes.io/ingress.class: ${INGRESS_MODE}
spec:
  ingressClassName: ${INGRESS_MODE}
  rules:
    - host: schema-registry.127-0-0-1.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: apicurio-registry-app-service
                port:
                  number: 8080
EOF
fi

# ---------------------------------------------------------------------------
# Deploy kafka-ui
# ---------------------------------------------------------------------------
if [ "${INGRESS_MODE}" == "kong" ]; then
  UI_VALUES="kafka-ui/kafka-ui-values-kong.yaml"
else
  UI_VALUES="kafka-ui/kafka-ui-values.yaml"
fi


helm upgrade --install kafka-ui kafbat-ui/kafka-ui \
  --namespace kafka \
  --values "${UI_VALUES}" \
  --wait \
  --timeout 3m

kubectl wait deployment/kafka-ui \
  -n kafka --for=condition=Available=true --timeout=120s

# ---------------------------------------------------------------------------
# Create sample topic via GitOps-style KafkaTopic CR
# ---------------------------------------------------------------------------
kubectl apply -f cluster/sample-topic.yaml

# ---------------------------------------------------------------------------
# Print connection info
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  Strimzi Kafka Cluster Setup Complete"
echo "================================================================"
echo ""
KAFKA_NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "  Kafka cluster:       kafka-cluster (namespace: kafka)"
echo "  Bootstrap (plain):   kafka-cluster-kafka-bootstrap.kafka:9092  (in-cluster)"
echo "  Bootstrap (TLS):     kafka-cluster-kafka-bootstrap.kafka:9093  (in-cluster)"
echo "  Bootstrap (external): ${KAFKA_NODE_IP}:32100  (NodePort)"
echo "    Broker 0: ${KAFKA_NODE_IP}:32000"
echo "    Broker 1: ${KAFKA_NODE_IP}:32001"
echo "    Broker 2: ${KAFKA_NODE_IP}:32002"
echo ""
echo "  HTTP Bridge:"
if [ "${INGRESS_MODE}" != "none" ]; then
  echo "    URL:  http://kafka-bridge.127-0-0-1.nip.io:8080"
else
  echo "    kubectl port-forward svc/kafka-bridge-bridge-service -n kafka 8080:8080"
  echo "    URL:  http://localhost:8080"
fi
echo ""
echo "  Apicurio Registry:"
if [ "${INGRESS_MODE}" != "none" ]; then
  echo "    UI:   http://schema-registry.127-0-0-1.nip.io:8080/ui"
  echo "    API:  http://schema-registry.127-0-0-1.nip.io:8080/apis/ccompat/v7"
else
  echo "    kubectl port-forward svc/apicurio-registry -n kafka 8080:8080"
  echo "    UI:   http://localhost:8080/ui"
  echo "    API:  http://localhost:8080/apis/ccompat/v7"
fi
echo ""
echo "  kafka-ui:"
if [ "${INGRESS_MODE}" != "none" ]; then
  echo "    URL:  http://kafka-ui.127-0-0-1.nip.io:8080"
else
  echo "    kubectl port-forward svc/kafka-ui -n kafka 8888:80"
  echo "    URL:  http://localhost:8888"
fi
echo ""
echo "  Sample topic:        sample-topic (6 partitions, RF=3)"
echo ""
echo "  Inspect topic list:"
echo "    kubectl get kafkatopics -n kafka"
echo ""
echo "  NOTE: Write operations in kafka-ui are enabled by default."
echo "        Restrict access via RBAC for production workloads."
echo ""
echo "  Load tests (plain, JSON, Avro via Schema Registry):"
echo "    cd loadtest && bash run-loadtests.sh"
echo "    See loadtest/README.md for details."
echo "================================================================"
