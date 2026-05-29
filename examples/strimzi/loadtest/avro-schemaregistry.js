import { Writer, SchemaRegistry, CODEC_SNAPPY, SCHEMA_TYPE_AVRO } from "k6/x/kafka";
import { uuidv4 } from "https://jslib.k6.io/k6-utils/1.4.0/index.js";

const BOOTSTRAP_SERVERS = __ENV.BOOTSTRAP_SERVERS || "kafka-cluster-kafka-bootstrap.kafka:9092";
const SCHEMA_REGISTRY_URL = __ENV.SCHEMA_REGISTRY_URL || "http://apicurio-registry-app-service.kafka:8080/apis/ccompat/v7";
const TOPIC = "k6-avro";

export const options = {
  vus: 10,
  duration: "30s",
  thresholds: {
    kafka_writer_error_count: ["count==0"],
  },
};

const keySchema = JSON.stringify({
  type: "record",
  name: "K6EventKey",
  namespace: "io.example.k6",
  fields: [{ name: "eventId", type: "string" }],
});

const valueSchema = JSON.stringify({
  type: "record",
  name: "K6Event",
  namespace: "io.example.k6",
  fields: [
    { name: "eventId", type: "string" },
    { name: "eventType", type: "string" },
    { name: "vuId", type: "int" },
    { name: "iteration", type: "int" },
    { name: "timestamp", type: "long" },
    { name: "message", type: "string" },
  ],
});

const writer = new Writer({
  brokers: [BOOTSTRAP_SERVERS],
  topic: TOPIC,
  compression: CODEC_SNAPPY,
});

const schemaRegistry = new SchemaRegistry({ url: SCHEMA_REGISTRY_URL });

export default function () {
  const eventId = uuidv4();

  const key = schemaRegistry.serialize({
    data: { eventId },
    schema: { schema: keySchema },
    schemaType: SCHEMA_TYPE_AVRO,
  });

  const value = schemaRegistry.serialize({
    data: {
      eventId,
      eventType: "load-test-event",
      vuId: __VU,
      iteration: __ITER,
      timestamp: Date.now(),
      message: "avro load test message",
    },
    schema: { schema: valueSchema },
    schemaType: SCHEMA_TYPE_AVRO,
  });

  writer.produce({
    messages: [
      {
        key,
        value,
        headers: {
          "content-type": "application/avro",
          "x-source": "k6-load-test",
        },
      },
    ],
  });
}

export function teardown() {
  writer.close();
}
