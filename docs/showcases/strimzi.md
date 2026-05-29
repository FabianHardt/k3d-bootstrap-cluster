# Strimzi Kafka Cluster

[Strimzi](https://strimzi.io) is a CNCF project that provides a Kubernetes operator for running Apache Kafka. It manages the full Kafka lifecycle — cluster provisioning, rolling upgrades, configuration management, topic and user creation — through Kubernetes custom resources.

This showcase deploys a production-sized, KRaft-based Kafka cluster (no ZooKeeper) with Confluent Schema Registry, Kafka HTTP Bridge, and [kafka-ui](https://github.com/provectus/kafka-ui) as a web management console. All cluster resources (topics, users) are managed exclusively via Strimzi CRDs, keeping cluster state fully declarative and reproducible from Git.

### Preconditions

- A running k3d cluster with **at least 3 worker nodes** — the production pod anti-affinity rule places one broker per node.

  ```bash
  k3d cluster create demo --agents 3
  ```

- The httpbin sample is not required for this showcase.

### Installation

```bash
cd examples/strimzi

# With HAProxy Ingress Controller
HAPROXY_FLAG=Yes bash setup.sh

# With Kong Gateway
KONG_FLAG=Yes bash setup.sh
```

If neither flag is set, the ingress controller is auto-detected from the cluster. If none is found, all UIs are accessible via port-forward only.

The following components are installed by `setup.sh`:

- **Strimzi operator** — Helm chart (namespace: `strimzi-system`), watches the `kafka` namespace
- **Kafka cluster** — `KafkaNodePool` + `Kafka` CRs (namespace: `kafka`)
  - 3 brokers in KRaft combined mode (each pod is both controller and broker)
  - Required pod anti-affinity — one broker per worker node
  - Production CPU/RAM sizing; 2 Gi storage per broker (reduced for local demo)
  - JVM heap: `-Xms1g -Xmx1g`
  - 7-day log retention, replication factor 3, min ISR 2, 6 default partitions
- **Kafka HTTP Bridge** — `KafkaBridge` CR (2 replicas), exposed via Ingress
  - Producer: `acks=all`, `linger.ms=5`, snappy compression
- **Apicurio Registry Operator** — installed from the official GitHub release manifest (namespace: `apicurio-system`)
- **Apicurio Registry** — `ApicurioRegistry3` CR (2 replicas), Kafka SQL storage
  - Schemas stored in the `kafkasql-journal` topic (RF=3, unlimited retention)
  - Confluent Schema Registry API compatibility exposed at `/apis/ccompat/v7`
- **kafka-ui** — Helm chart (1 replica), pre-wired to broker, Schema Registry, and Bridge

### Access kafka-ui

Open the management console at http://kafka-ui.127-0-0-1.nip.io:8080.

kafka-ui provides:
- Topic browser and message inspector
- Consumer group lag monitoring
- Schema Registry browser
- Kafka Connect / Bridge endpoint overview

> **Note:** Write operations (produce, delete topic, reset offsets) are enabled by default in this demo. Restrict them via kafka-ui RBAC configuration for production workloads.

### Access kafka-ui without Ingress

```bash
kubectl port-forward svc/kafka-ui -n kafka 8888:80
```

Then open: http://localhost:8888

### External Access (NodePort)

The cluster exposes a dedicated external listener on NodePort 32100 (bootstrap) with individual broker ports 32000–32002. This allows native Kafka clients and CLI tools running outside the cluster to connect directly.

Get the node IP:

```bash
kubectl get nodes -o wide
```

Connect from outside the cluster (replace `<NODE_IP>` with the value from above):

```bash
# kafkactl
kafkactl --brokers <NODE_IP>:32100 get topics

# kcat
kcat -b <NODE_IP>:32100 -L

# kafka-console-producer (Kafka CLI)
kafka-console-producer.sh --bootstrap-server <NODE_IP>:32100 --topic sample-topic
```

Example `kafkactl` context (`~/.config/kafkactl/config.yml`):

```yaml
contexts:
  k3d-kafka:
    brokers:
      - <NODE_IP>:32100
current-context: k3d-kafka
```

> **k3d on macOS:** Docker Desktop does not route container network IPs to the host. Use `kubectl port-forward svc/kafka-cluster-kafka-external-bootstrap -n kafka 32100:32100` as an alternative, or map the NodePorts at cluster creation time with `k3d cluster create demo --agents 3 -p "32000-32002:32000-32002@agent:0,1,2" -p "32100:32100@loadbalancer"`.

### Kafka HTTP Bridge

The Bridge exposes a REST API for producing and consuming Kafka messages over HTTP.

```bash
# Produce a message
curl -X POST http://kafka-bridge.127-0-0-1.nip.io:8080/topics/sample-topic \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  -d '{"records":[{"key":"hello","value":{"msg":"world"}}]}'

# List consumer groups
curl http://kafka-bridge.127-0-0-1.nip.io:8080/
```

### Apicurio Registry

Open the Apicurio Registry UI at http://schema-registry.127-0-0-1.nip.io:8080/ui.

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
apiVersion: kafka.strimzi.io/v1beta2
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

See [`loadtest/README.md`](../../examples/strimzi/loadtest/README.md) for details.

```bash
cd examples/strimzi/loadtest
bash run-loadtests.sh
```

### Service Addresses

| Listener | Address |
|----------|---------|
| Plain — in-cluster | `kafka-cluster-kafka-bootstrap.kafka:9092` |
| TLS — in-cluster | `kafka-cluster-kafka-bootstrap.kafka:9093` |
| External bootstrap — NodePort | `<NODE_IP>:32100` |
| External brokers — NodePort | `<NODE_IP>:32000` / `:32001` / `:32002` |
| Apicurio Registry (compat API) | `http://apicurio-registry-app-service.kafka:8080/apis/ccompat/v7` |
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
