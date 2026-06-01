FROM ubuntu:24.04

ARG VERSION_TAG=2.0.0
ARG TARGETOS=linux
ARG TARGETARCH=aarch64

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates librdkafka1 openssl && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 12345 k6 && \
    useradd -u 12345 -g 12345 -m -s /bin/sh k6

RUN wget https://github.com/mostafa/xk6-kafka/releases/download/v2.0.0/xk6-kafka_v2.0.0_linux_arm64.tar.gz -O - | tar -xz -C /tmp && \
    ls -ltrh /tmp && \
    mv /tmp/xk6-kafka_v2.0.0_linux_arm64 /usr/bin/k6 && \
    chmod +x /usr/bin/k6
# COPY --chmod=0755 ./dist/xk6-kafka_${VERSION_TAG}_${TARGETOS}_${TARGETARCH} /usr/bin/k6

USER 12345
WORKDIR /home/k6
ENTRYPOINT ["k6"]