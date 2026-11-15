#!/usr/bin/env bash
# Records what the numbers depend on: CPU and memory visible to the container, the host
# description you pass in HOST_INFO, versions and executor size. Read-only;
# writes $OUT_DIR/$MACHINE_ID/machine.txt and versions.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

mkdir -p "$OUT_DIR/$MACHINE_ID"
{
  echo "machine_id: $MACHINE_ID"
  echo "host_info: ${HOST_INFO:-not given (docker run -e HOST_INFO='...')}"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "kernel: $(uname -srm)"
  echo "cpu: $(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^ +/, "", $2); print $2; exit}')"
  echo "cpus_visible: $(nproc)"
  echo "memory_visible_gb: $MEM_GB"
  echo "executor: cores=$CORES heap=$EXEC_MEM offheap=$OFFHEAP driver=$DRIVER_MEM"
  echo "iterations: warmup=$WARMUP measured=$ITERATIONS"
} | tee "$OUT_DIR/$MACHINE_ID/machine.txt"

{
  echo "spark: $SPARK_VERSION"
  echo "iceberg: $ICEBERG_VERSION"
  echo "comet: $COMET_VERSION ($(basename "$COMET_JAR"), published jar from Maven Central)"
  echo "tpchgen-cli: $(tpchgen-cli --version)"
  echo "java: $(java -version 2>&1 | head -1)"
  echo "async-profiler: $ASPROF_VERSION"
} > "$OUT_DIR/$MACHINE_ID/versions.txt"
