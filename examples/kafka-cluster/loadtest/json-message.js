import { Writer, CODEC_SNAPPY } from "k6/x/kafka";
import { uuidv4 } from "https://jslib.k6.io/k6-utils/1.4.0/index.js";
import { b64encode } from "k6/encoding";

const BOOTSTRAP_SERVERS = __ENV.BOOTSTRAP_SERVERS || "kafka-cluster-kafka-bootstrap.kafka:9092";
const TOPIC = "k6-json";

export const options = {
  vus: 10,
  duration: "30s",
  thresholds: {
    kafka_writer_error_count: ["count==0"],
  },
};

const writer = new Writer({
  brokers: [BOOTSTRAP_SERVERS],
  topic: TOPIC,
  compression: CODEC_SNAPPY,
});

export default function () {
  const eventId = uuidv4();

  writer.produce({
    messages: [
      {
        key: b64encode(JSON.stringify({ eventId })),
        value: b64encode(JSON.stringify({
          eventId,
          eventType: "load-test-event",
          source: "k6-load-test",
          vuId: __VU,
          iteration: __ITER,
          timestamp: Date.now(),
          payload: {
            message: "json load test message",
            sequence: __VU * 1000 + __ITER,
          },
        })),
        headers: {
          "content-type": "application/json",
          "x-source": "k6-load-test",
        },
      },
    ],
  });
}

export function teardown() {
  writer.close();
}
