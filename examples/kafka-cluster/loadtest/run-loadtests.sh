#!/bin/bash
set -o errexit

NAMESPACE="kafka"
IMAGE="mostafamoradian/xk6-kafka:1.3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test to run: plain-message | json-message | avro-schemaregistry | all (default)
TEST="${1:-all}"

run_test() {
  local name="$1"
  local script="$2"

  echo ""
  echo "-----------------------------------------------------------"
  echo "  Running: ${name}"
  echo "-----------------------------------------------------------"

  # Upload script as ConfigMap
  kubectl create configmap "k6-${name}" \
    --from-file="${script}=${SCRIPT_DIR}/${script}" \
    -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

  # Apply KafkaTopic CR so the topic is operator-managed
  topic_name="k6-${name%%-message}"
  topic_name="${topic_name%%-schemaregistry}"
  kubectl apply -f - <<EOF
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: ${topic_name}
  namespace: ${NAMESPACE}
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  partitions: 6
  replicas: 3
  config:
    cleanup.policy: delete
    retention.ms: "3600000"
EOF

  # Delete a leftover job from a previous run so kubectl apply does not fail
  kubectl delete job "k6-${name}" -n "${NAMESPACE}" --ignore-not-found

  # Run k6 Job inside the cluster
  kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-${name}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: k6
          image: ${IMAGE}
          command: ["k6", "run", "/scripts/${script}"]
          env:
            - name: BOOTSTRAP_SERVERS
              value: "kafka-cluster-kafka-bootstrap.kafka:9092"
            - name: SCHEMA_REGISTRY_URL
              value: "http://apicurio-registry-app-service.kafka:8080/apis/ccompat/v7"
          volumeMounts:
            - name: scripts
              mountPath: /scripts
          resources:
            requests:
              cpu: 500m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 512Mi
      volumes:
        - name: scripts
          configMap:
            name: k6-${name}
EOF

  echo "Waiting for k6-${name} job to complete..."
  kubectl wait job/"k6-${name}" \
    -n "${NAMESPACE}" --for=condition=Complete --timeout=180s 2>/dev/null || \
  kubectl wait job/"k6-${name}" \
    -n "${NAMESPACE}" --for=condition=Failed --timeout=10s 2>/dev/null || true

  echo ""
  echo "=== Results: ${name} ==="
  kubectl logs -n "${NAMESPACE}" -l "job-name=k6-${name}" --tail=-1
}

case "${TEST}" in
  plain-message)
    run_test "plain-message" "plain-message.js"
    ;;
  json-message)
    run_test "json-message" "json-message.js"
    ;;
  avro-schemaregistry)
    run_test "avro-schemaregistry" "avro-schemaregistry.js"
    ;;
  all)
    run_test "plain-message" "plain-message.js"
    run_test "json-message" "json-message.js"
    run_test "avro-schemaregistry" "avro-schemaregistry.js"
    ;;
  *)
    echo "Usage: $0 [plain-message|json-message|avro-schemaregistry|all]"
    exit 1
    ;;
esac

echo ""
echo "================================================================"
echo "  Load tests complete. Topics created:"
echo "    kubectl get kafkatopics -n ${NAMESPACE} -l strimzi.io/cluster=kafka-cluster"
echo ""
echo "  Inspect messages in kafka-ui:"
echo "    http://kafka-ui.127-0-0-1.nip.io:8080"
echo "================================================================"
