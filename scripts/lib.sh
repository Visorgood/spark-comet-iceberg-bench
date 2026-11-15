# shellcheck shell=bash
# Shared helpers and spark-submit arguments.
# Every run uses the same cluster shape, memory (off-heap included) and event-log settings;
# runs differ only by the lines in run_args(). The Iceberg runtime jar is already on
# Spark's classpath in the image; the Comet jar is added only to Comet runs.

# Directory for the outputs of the current machine and scale factor.
out_dir() { echo "$OUT_DIR/$MACHINE_ID/sf$SCALE"; }

base_args() {
  ARGS=(
    --master "$SPARK_MASTER"
    --driver-memory "$DRIVER_MEM"
    --conf spark.executor.instances=1
    --conf spark.executor.cores="$CORES"
    --conf spark.cores.max="$CORES"
    --conf spark.executor.memory="$EXEC_MEM"
    --conf spark.memory.offHeap.enabled=true
    --conf spark.memory.offHeap.size="$OFFHEAP"
    --conf spark.sql.shuffle.partitions=200
    --conf spark.sql.adaptive.enabled=true
    --conf spark.eventLog.enabled=true
    --conf "spark.eventLog.dir=file://$EVENTS_DIR"
    --conf spark.eventLog.compress=false
    --conf spark.eventLog.rolling.enabled=false
    --conf spark.eventLog.logStageExecutorMetrics=true
    --conf spark.executor.metrics.pollingInterval=1000
    --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
    --conf spark.sql.catalog.lake=org.apache.iceberg.spark.SparkCatalog
    --conf spark.sql.catalog.lake.type=hadoop
    --conf "spark.sql.catalog.lake.warehouse=file://$WAREHOUSE"
  )
}

comet_args() {
  if [ ! -f "$COMET_JAR" ]; then
    echo "Comet jar not found at $COMET_JAR" >&2
    return 1
  fi
  ARGS+=(
    --jars "$COMET_JAR"
    --driver-class-path "$COMET_JAR"
    --conf "spark.executor.extraClassPath=$COMET_JAR"
    --conf spark.plugins=org.apache.spark.CometPlugin
    --conf spark.shuffle.manager=org.apache.spark.sql.comet.execution.shuffle.CometShuffleManager
    --conf spark.comet.explain.fallback.enabled=true
    --conf spark.sql.extendedExplainProviders=org.apache.comet.ExtendedExplainInfo
  )
}

# Sets ARGS and QUERY for one run id. See README, "Run matrix".
run_args() {
  base_args
  QUERY="$BENCH_ROOT/sql/insert.sql"
  case "$1" in
    A)  ;;                                                    # Spark only
    A1) ARGS+=(--conf spark.sql.shuffle.orderIndependentChecksum.enabled=false) ;;
    AF) QUERY="$BENCH_ROOT/sql/insert_breaker.sql" ;;         # Spark only, with the breaker
    B)  comet_args || return 1 ;;                             # Comet defaults: iceberg-java writes
    C)  comet_args || return 1
        ARGS+=(--conf spark.comet.write.iceberg.enabled=true) ;;
    D)  comet_args || return 1
        ARGS+=(--conf spark.comet.write.iceberg.enabled=true --conf spark.comet.shuffle.mode=jvm) ;;
    E)  comet_args || return 1
        ARGS+=(--conf spark.comet.write.iceberg.enabled=true --conf spark.comet.shuffle.enabled=false) ;;
    F)  comet_args || return 1
        ARGS+=(--conf spark.comet.write.iceberg.enabled=true)
        QUERY="$BENCH_ROOT/sql/insert_breaker.sql" ;;
    *)  echo "Unknown run id: $1 (use A, A1, AF, B, C, D, E, F)" >&2; return 1 ;;
  esac
}
