import { Writer, CODEC_SNAPPY } from "k6/x/kafka";
import { b64encode } from "k6/encoding";

const BOOTSTRAP_SERVERS = __ENV.BOOTSTRAP_SERVERS || "kafka-cluster-kafka-bootstrap.kafka:9092";
const TOPIC = "k6-plain";

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
  writer.produce({
    messages: [
      {
        key: b64encode(`vu-${__VU}-iter-${__ITER}`),
        value: b64encode(`plain message from VU ${__VU}, iteration ${__ITER}, ts=${Date.now()}`),
        headers: {
          "x-source": "k6-load-test",
        },
      },
    ],
  });

}

export function teardown() {
  writer.close();
}
