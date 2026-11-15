#!/usr/bin/env bash
# Records what the numbers depend on: the container's CPU and memory limits, executor
# size and versions. Writes $OUT_DIR/sf$SCALE/environment.txt, shown in the report.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

mkdir -p "$(out_dir)"
{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "cpu: $(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^ +/, "", $2); print $2; exit}') ($(uname -m))"
  echo "container limits: $CPUS CPUs, ${MEM_GB} GB memory (CPUs visible: $(nproc))"
  echo "executor: $CORES cores, heap $EXEC_MEM, off-heap $OFFHEAP; driver $DRIVER_MEM"
  echo "iterations per run: $WARMUP warm-up + $ITERATIONS measured"
  echo "spark $SPARK_VERSION, iceberg $ICEBERG_VERSION, comet $COMET_VERSION, $(tpchgen-cli --version)"
  echo "java: $(java -version 2>&1 | head -1)"
} | tee "$(out_dir)/environment.txt"
