# shellcheck shell=bash
# Shared helpers and spark-submit arguments. Works with the bash 3.2 that ships with macOS.
# Every run uses the same cluster shape, memory (off-heap included) and event-log settings;
# runs differ only by the lines in run_args().

require_env() {
  if [ -z "${BENCH_ROOT:-}" ] || [ -z "${SPARK_HOME:-}" ]; then
    echo "Run 'source ./env.sh' first." >&2
    exit 1
  fi
}

# Directory for raw outputs of the current machine and scale factor.
out_dir() { echo "$OUT_DIR/$MACHINE_ID/sf$SCALE"; }

# Sets COMET_JAR: an explicit COMET_JAR, a downloaded release jar in deps/, or a build in COMET_HOME.
find_comet_jar() {
  if [ -n "${COMET_JAR:-}" ] && [ -f "$COMET_JAR" ]; then return 0; fi
  local version="${COMET_RELEASE:-*}"
  COMET_JAR="$(find "$DEPS_DIR" "$COMET_HOME/spark/target" -maxdepth 4 \
      -name "comet-spark-spark4.1_${SCALA_BINARY}-${version}.jar" \
      ! -name '*-sources.jar' ! -name '*-tests.jar' ! -name 'original-*' 2>/dev/null | head -1)"
  export COMET_JAR
  [ -n "$COMET_JAR" ]
}

base_args() {
  ARGS=(
    --master "$SPARK_MASTER"
    --driver-memory "$DRIVER_MEM"
    --packages "$ICEBERG_PACKAGES"
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
  if ! find_comet_jar; then
    echo "No Comet jar found. Run scripts/00_setup.sh, or set COMET_JAR in env.local.sh." >&2
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

# Verifies a downloaded file against a published checksum file (sha512 or sha1).
# Works with both "HEX  file" and "file: HE X ..." layouts.
verify_checksum() {  # $1 = file, $2 = checksum file, $3 = sha512|sha1
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib, os, re, sys
path, sumfile, algo = sys.argv[1:4]
h = hashlib.new(algo)
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
text = open(sumfile).read().replace(os.path.basename(path), "")
text = re.sub(r"(?i)sha-?(512|1)", "", text)   # drop "SHA512 (...) =" style labels
expected = re.sub(r"[^0-9a-fA-F]", "", text).lower()
if expected != h.hexdigest():
    sys.exit(f"checksum mismatch for {path}: expected {expected}, got {h.hexdigest()}")
print(f"{algo} ok: {os.path.basename(path)}")
PY
}
