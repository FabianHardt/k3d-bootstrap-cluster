#!/bin/bash
set -o errexit

source ../../helpers.sh

# Kong Gateway is the sole ingress controller in this cluster — Kafka UIs,
# the HTTP Bridge, and Apicurio Registry are exposed via Gateway API
# HTTPRoutes (or, for the Apicurio operator that only supports Ingress,
# Ingresses bound to the Kong IngressClass).

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

# Expose the Bridge via Kong Gateway (Ingress bound to the kong IngressClass)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-bridge
  namespace: kafka
  annotations:
    kubernetes.io/ingress.class: kong
spec:
  ingressClassName: kong
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

# Registry instance — operator reconciles the app/ui deployments, services, and
# the operator-managed Ingresses for each component (bound to the Kong
# IngressClass).
export INGRESS_CLASS="kong"
export SCHEMA_REGISTRY_HOST="schema-registry.127-0-0-1.nip.io"
export SCHEMA_REGISTRY_UI_HOST="schema-registry-ui.127-0-0-1.nip.io"
export API_URL="http://${SCHEMA_REGISTRY_HOST}:8080/apis/registry/v3"
export UI_ORIGIN="http://${SCHEMA_REGISTRY_UI_HOST}:8080"
templateConfigFile "registry/apicurio-registry-template.yaml" "registry/apicurio-registry.yaml"
kubectl apply -f registry/apicurio-registry.yaml

kubectl wait apicurioregistry3/apicurio-registry \
  -n kafka --for=condition=Ready --timeout=300s

# ---------------------------------------------------------------------------
# Deploy kafka-ui
# ---------------------------------------------------------------------------
helm upgrade --install kafka-ui kafbat-ui/kafka-ui \
  --namespace kafka \
  --values kafka-ui/kafka-ui-values-kong.yaml \
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
echo "  Kafka cluster:       kafka-cluster (namespace: kafka)"
echo "  Bootstrap (plain):   kafka-cluster-kafka-bootstrap.kafka:9092  (in-cluster)"
echo "  Bootstrap (TLS):     kafka-cluster-kafka-bootstrap.kafka:9093  (in-cluster)"
echo ""
echo "  HTTP Bridge:"
echo "    URL:  http://kafka-bridge.127-0-0-1.nip.io:8080"
echo ""
echo "  Apicurio Registry:"
echo "    UI:   http://schema-registry-ui.127-0-0-1.nip.io:8080"
echo "    API:  http://schema-registry.127-0-0-1.nip.io:8080/apis/ccompat/v7"
echo ""
echo "  kafka-ui:"
echo "    URL:  http://kafka-ui.127-0-0-1.nip.io:8080"
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
