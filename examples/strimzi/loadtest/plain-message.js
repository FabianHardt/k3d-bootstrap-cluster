import { Writer, Reader, CODEC_SNAPPY } from "k6/x/kafka";

const BOOTSTRAP_SERVERS = __ENV.BOOTSTRAP_SERVERS || "kafka-cluster-kafka-bootstrap.kafka:9092";
const TOPIC = "k6-plain-message";

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

const reader = new Reader({
  brokers: [BOOTSTRAP_SERVERS],
  groupTopics: [TOPIC],
  groupId: "k6-plain-consumer",
});

export default function () {
  writer.produce({
    messages: [
      {
        key: `vu-${__VU}-iter-${__ITER}`,
        value: `plain message from VU ${__VU}, iteration ${__ITER}, ts=${Date.now()}`,
        headers: {
          "x-source": "k6-load-test",
        },
      },
    ],
  });

  reader.consume({ limit: 10 });
}

export function teardown() {
  writer.close();
  reader.close();
}
