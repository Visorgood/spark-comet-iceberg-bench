# shellcheck shell=bash
# Shared helpers and spark-submit arguments.
# Every run uses the same cluster shape, memory (off-heap included) and event-log settings;
# runs differ only by the lines in run_args(). The Iceberg runtime jar is already on
# Spark's classpath in the image; the Comet jar is added only to Comet runs.

# Directory for the outputs of the current scale factor.
out_dir() { echo "$OUT_DIR/sf$SCALE"; }

base_args() {
  ARGS=(
    --master "$MASTER_URL"
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
    --conf spark.comet.write.iceberg.enabled=true
    --conf spark.comet.explain.fallback.enabled=true
    --conf spark.sql.extendedExplainProviders=org.apache.comet.ExtendedExplainInfo
  )
}

# Sets ARGS and QUERY for one run. See README, "What runs".
run_args() {
  base_args
  QUERY="$BENCH_ROOT/sql/insert.sql"
  case "$1" in
    spark)          ;;
    comet)          comet_args || return 1 ;;
    comet-fallback) comet_args || return 1
                    QUERY="$BENCH_ROOT/sql/insert_breaker.sql" ;;
    *) echo "Unknown run: $1 (use spark, comet or comet-fallback)" >&2; return 1 ;;
  esac
}
