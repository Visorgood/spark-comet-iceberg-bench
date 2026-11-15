# syntax=docker/dockerfile:1
# Everything the benchmark needs, pinned: Java 17 (Eclipse Temurin build of OpenJDK),
# Spark, Iceberg, Comet and the TPC-H generator.
# Build:  docker build -t spark-comet-iceberg-bench .
# Run:    see README.md
FROM eclipse-temurin:17-jdk-jammy

ARG SPARK_VERSION=4.1.3
ARG SCALA_BINARY=2.13
ARG ICEBERG_VERSION=1.11.0
ARG COMET_VERSION=1.2.0
ARG TPCHGEN_VERSION=4.0.0

ENV SPARK_VERSION=${SPARK_VERSION} \
    SCALA_BINARY=${SCALA_BINARY} \
    ICEBERG_VERSION=${ICEBERG_VERSION} \
    COMET_VERSION=${COMET_VERSION} \
    TPCHGEN_VERSION=${TPCHGEN_VERSION} \
    SPARK_HOME=/opt/spark \
    COMET_JAR=/opt/comet/comet-spark-spark4.1_${SCALA_BINARY}-${COMET_VERSION}.jar \
    BENCH_ROOT=/bench \
    WORK=/work \
    PYSPARK_PYTHON=python3 \
    PATH=/opt/venv/bin:/opt/spark/bin:${PATH}

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv procps curl ca-certificates tini bsdextrautils \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir "tpchgen-cli==${TPCHGEN_VERSION}"

COPY docker/verify_checksum.py /usr/local/bin/verify_checksum.py

# Spark, checked against the SHA-512 published by Apache
RUN set -eux; \
    name="spark-${SPARK_VERSION}-bin-hadoop3"; \
    url="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${name}.tgz"; \
    curl -fsSL -o "/tmp/${name}.tgz" "$url"; \
    curl -fsSL -o "/tmp/${name}.tgz.sha512" "$url.sha512"; \
    python3 /usr/local/bin/verify_checksum.py "/tmp/${name}.tgz" "/tmp/${name}.tgz.sha512" sha512; \
    tar xzf "/tmp/${name}.tgz" -C /opt; \
    mv "/opt/${name}" "$SPARK_HOME"; \
    rm -f /tmp/${name}.tgz*

# Iceberg Spark runtime (on Spark's classpath for every run) and the Comet jar
# (added only to Comet runs), both checked against Maven Central's SHA-1
RUN set -eux; \
    mvn="https://repo1.maven.org/maven2"; \
    ice="iceberg-spark-runtime-4.1_${SCALA_BINARY}"; \
    curl -fsSL -o "$SPARK_HOME/jars/${ice}-${ICEBERG_VERSION}.jar" "$mvn/org/apache/iceberg/${ice}/${ICEBERG_VERSION}/${ice}-${ICEBERG_VERSION}.jar"; \
    curl -fsSL -o /tmp/ice.sha1 "$mvn/org/apache/iceberg/${ice}/${ICEBERG_VERSION}/${ice}-${ICEBERG_VERSION}.jar.sha1"; \
    python3 /usr/local/bin/verify_checksum.py "$SPARK_HOME/jars/${ice}-${ICEBERG_VERSION}.jar" /tmp/ice.sha1 sha1; \
    comet="comet-spark-spark4.1_${SCALA_BINARY}"; \
    mkdir -p /opt/comet; \
    curl -fsSL -o "$COMET_JAR" "$mvn/org/apache/datafusion/${comet}/${COMET_VERSION}/${comet}-${COMET_VERSION}.jar"; \
    curl -fsSL -o /tmp/comet.sha1 "$mvn/org/apache/datafusion/${comet}/${COMET_VERSION}/${comet}-${COMET_VERSION}.jar.sha1"; \
    python3 /usr/local/bin/verify_checksum.py "$COMET_JAR" /tmp/comet.sha1 sha1; \
    rm -f /tmp/*.sha1

COPY env.sh /bench/env.sh
COPY scripts /bench/scripts
COPY sql /bench/sql
COPY bench /bench/bench
COPY docker/entrypoint.sh /bench/docker/entrypoint.sh
WORKDIR /bench
VOLUME /work
EXPOSE 8000 18080

ENTRYPOINT ["/usr/bin/tini", "--", "bash", "/bench/docker/entrypoint.sh"]
CMD ["all"]
