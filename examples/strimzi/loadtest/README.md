# Strimzi Kafka — Load Tests

Load tests for the Strimzi Kafka showcase using [k6](https://k6.io) with the [xk6-kafka](https://github.com/mostafa/xk6-kafka) extension. Tests run as Kubernetes Jobs inside the cluster so they reach the internal Kafka bootstrap and Schema Registry services directly — no external exposure needed.

## Prerequisites

- The Strimzi showcase must be installed and ready (`../setup.sh`)
- `kubectl` configured against the k3d cluster

## Tests

| Script | Topic | Serialization | Schema Registry |
|--------|-------|---------------|-----------------|
| `plain-message.js` | `k6-plain` | UTF-8 string | No |
| `json-message.js` | `k6-json` | `JSON.stringify()` | No |
| `avro-schemaregistry.js` | `k6-avro` | Avro (Confluent wire format) | Yes |

Each test runs **10 VUs for 30 seconds** by default. All three topics are created as `KafkaTopic` CRs (RF=3, 6 partitions) so they are reconciled by the Strimzi entity operator.

## Running the Tests

Run all three tests in sequence:

```bash
bash run-loadtests.sh
```

Or run a specific test:

```bash
bash run-loadtests.sh plain-message
bash run-loadtests.sh json-message
bash run-loadtests.sh avro-schemaregistry
```

The script will:
1. Create a `KafkaTopic` CR for the test topic
2. Upload the k6 script as a `ConfigMap`
3. Run a Kubernetes `Job` using the `mostafamoradian/xk6-kafka` image
4. Stream the k6 summary output on completion

## Inspecting Results

Once a test completes, inspect the produced messages in **kafka-ui**:

```
http://kafka-ui.127-0-0-1.nip.io:8080
```

Navigate to **Topics → k6-plain / k6-json / k6-avro → Messages**.

For Avro messages, Schema Registry schemas are visible at:

```
http://schema-registry.127-0-0-1.nip.io:8080/subjects
```

Or from inside the cluster:

```bash
kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://schema-registry.kafka:8081/subjects | tr ',' '\n'
```

## Customising the Tests

The k6 scripts read their configuration from environment variables. To change VUs, duration, or target endpoints, edit the `env` block in `run-loadtests.sh` or override them at the Job level:

| Variable | Default | Description |
|----------|---------|-------------|
| `BOOTSTRAP_SERVERS` | `kafka-cluster-kafka-bootstrap.kafka:9092` | Kafka bootstrap address |
| `SCHEMA_REGISTRY_URL` | `http://schema-registry.kafka:8081` | Schema Registry URL |

VU count and duration are controlled by the `options` export at the top of each `.js` file.

## Running k6 Locally (Alternative)

If you have a custom k6 binary with xk6-kafka built in, and the Kafka services are port-forwarded:

```bash
# Forward Kafka and Schema Registry
kubectl port-forward svc/kafka-cluster-kafka-bootstrap -n kafka 9092:9092 &
kubectl port-forward svc/schema-registry -n kafka 8081:8081 &

# Run a test
BOOTSTRAP_SERVERS=localhost:9092 \
SCHEMA_REGISTRY_URL=http://localhost:8081 \
k6 run plain-message.js
```

Build a local xk6-kafka binary:

```bash
xk6 build --with github.com/mostafa/xk6-kafka
```
