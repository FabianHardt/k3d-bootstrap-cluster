# Strimzi Kafka Cluster

[Strimzi](https://strimzi.io) is a CNCF project that provides a Kubernetes operator for running Apache Kafka. It manages the full Kafka lifecycle — cluster provisioning, rolling upgrades, configuration management, topic and user creation — through Kubernetes custom resources.

This showcase deploys a production-sized, KRaft-based Kafka cluster (no ZooKeeper) with Apicurio Registry for schema management, Kafka HTTP Bridge, and [kafka-ui](https://github.com/kafbat/kafka-ui) (the community-maintained fork of the archived Provectus project) as a web management console. All cluster resources (topics, users) are managed exclusively via Strimzi CRDs, keeping cluster state fully declarative and reproducible from Git.

### Preconditions

- The demo cluster must have at least **3 worker nodes** — the production pod anti-affinity rule places one broker per node.
- The httpbin sample is not required for this showcase.

### Installation

```bash
cd examples/kafka-cluster
bash setup.sh
```

All UIs (kafka-ui, Apicurio Registry, HTTP Bridge) are exposed via Kong Gateway — the sole ingress controller in this cluster.

The following components are installed by `setup.sh`:

- **Strimzi operator** — Helm chart (namespace: `strimzi-system`), watches the `kafka` namespace
- **Kafka cluster** — `KafkaNodePool` + `Kafka` CRs (namespace: `kafka`)
  - 3 brokers in KRaft combined mode (each pod is both controller and broker)
  - Required pod anti-affinity — one broker per worker node
  - Production CPU/RAM sizing; 2 Gi storage per broker (reduced for local demo)
  - JVM heap: `-Xms512m -Xmx512m`
  - 7-day log retention, replication factor 3, min ISR 2, 6 default partitions
- **Kafka HTTP Bridge** — `KafkaBridge` CR (2 replicas), exposed via Kong Gateway
  - Producer: `acks=all`, `linger.ms=5`, snappy compression
- **Apicurio Registry Operator** — installed from the official GitHub release manifest (namespace: `apicurio-system`)
- **Apicurio Registry** — `ApicurioRegistry3` CR (2 replicas), Kafka SQL storage
  - Schemas stored in the `kafkasql-journal` topic (RF=3, unlimited retention)
  - Confluent Schema Registry API compatibility exposed at `/apis/ccompat/v7`
- **kafka-ui** — Helm chart from [kafbat](https://github.com/kafbat/helm-charts) (1 replica), pre-wired to the broker and Apicurio Schema Registry

### Access kafka-ui

Open the management console at http://kafka-ui.127-0-0-1.nip.io:8080.

kafka-ui provides:
- Topic browser and message inspector
- Consumer group lag monitoring
- Schema Registry browser (Apicurio via the Confluent-compatible API)

> **Note:** Write operations (produce, delete topic, reset offsets) are enabled by default in this demo. Restrict them via kafka-ui RBAC configuration for production workloads.

### Kafka HTTP Bridge

The Bridge exposes a REST API for producing and consuming Kafka messages over HTTP. See the [Strimzi HTTP Bridge docs](https://strimzi.io/docs/bridge/latest/) for the full API.

```bash
# Bridge version and health
curl http://kafka-bridge.127-0-0-1.nip.io:8080/
curl http://kafka-bridge.127-0-0-1.nip.io:8080/healthy

# List topics
curl http://kafka-bridge.127-0-0-1.nip.io:8080/topics

# List partitions of a topic
curl http://kafka-bridge.127-0-0-1.nip.io:8080/topics/sample-topic/partitions

# Produce a message
curl -X POST http://kafka-bridge.127-0-0-1.nip.io:8080/topics/sample-topic \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  -d '{"records":[{"key":"hello","value":{"msg":"world"}}]}'
```

> The Bridge API does not provide an endpoint to list consumer groups — use kafka-ui or the Kafka Admin API for that. The Bridge only manages consumer *instances* within a named group via `POST /consumers/{groupid}`.

### Apicurio Registry

Apicurio Registry v3 ships the REST API and the web UI as **separate Deployments and Services**. The setup script exposes both via Kong Gateway:

- API: http://schema-registry.127-0-0-1.nip.io:8080
- UI:  http://schema-registry-ui.127-0-0-1.nip.io:8080

Browse registered schemas via the Confluent-compatible REST API:

```bash
curl http://schema-registry.127-0-0-1.nip.io:8080/apis/ccompat/v7/subjects
```

Or from inside the cluster:

```bash
kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://apicurio-registry-app-service.kafka:8080/apis/ccompat/v7/subjects
```

### Managing Topics

Topics are managed via `KafkaTopic` CRs — no direct CLI or Admin API access:

```bash
# List all topics
kubectl get kafkatopics -n kafka

# Inspect the sample topic
kubectl describe kafkatopic sample-topic -n kafka
```

To create a new topic, apply a manifest:

```yaml
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: my-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  partitions: 6
  replicas: 3
  config:
    cleanup.policy: delete
    retention.ms: "604800000"
    min.insync.replicas: "2"
```

### Load Tests

The `loadtest/` subdirectory contains k6 load tests covering plain string, JSON, and Avro (via Schema Registry) message patterns. Tests run as Kubernetes Jobs inside the cluster.

See [`loadtest/README.md`](https://github.com/FabianHardt/k3d-bootstrap-cluster/blob/main/examples/kafka-cluster/loadtest/README.md) for details.

```bash
cd examples/kafka-cluster/loadtest
bash run-loadtests.sh
```

### Service Addresses

| Listener | Address |
|----------|---------|
| Plain — in-cluster | `kafka-cluster-kafka-bootstrap.kafka:9092` |
| TLS — in-cluster | `kafka-cluster-kafka-bootstrap.kafka:9093` |
| Apicurio Registry API (compat) | `http://apicurio-registry-app-service.kafka:8080/apis/ccompat/v7` |
| Apicurio Registry UI | `http://apicurio-registry-ui-service.kafka:8080` |
| HTTP Bridge | `http://kafka-bridge-bridge-service.kafka:8080` |

### Cleanup

```bash
kubectl delete kafkabridges,kafkas,kafkanodepools,kafkatopics --all -n kafka
kubectl delete apicurioregistry3 apicurio-registry -n kafka
kubectl delete namespace apicurio-system
helm uninstall kafka-ui -n kafka
helm uninstall strimzi-kafka-operator -n strimzi-system
kubectl delete namespace kafka strimzi-system
```
