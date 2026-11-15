# Settings used inside the Docker image; sourced by docker/entrypoint.sh and every script.
# Override any of them with `docker run -e NAME=value ...`.
# Versions (SPARK_VERSION, ICEBERG_VERSION, COMET_VERSION, ...) are set in the Dockerfile.

export BENCH_ROOT="${BENCH_ROOT:-/bench}"
export WORK="${WORK:-/work}"                     # the Docker volume: data, tables, logs, outputs
export SPARK_HOME="${SPARK_HOME:-/opt/spark}"
export COMET_JAR="${COMET_JAR:-/opt/comet/comet-spark-spark4.1_${SCALA_BINARY}-${COMET_VERSION}.jar}"
export ASPROF_HOME="${ASPROF_HOME:-/opt/async-profiler}"

export DATA_DIR="$WORK/data"            # generated TPC-H Parquet
export WAREHOUSE="$WORK/warehouse"      # Iceberg tables (Hadoop catalog "lake")
export EVENTS_DIR="$WORK/spark-events"  # Spark event logs, read by the History Server
export OUT_DIR="$WORK/out"              # per-run outputs: timings, metrics, plans
export REPORT_DIR="$WORK/report"        # the HTML report served on port 8000
export EXPORT_DIR="${EXPORT_DIR:-/export}"  # bind-mount target for `export`

# --- What to run -------------------------------------------------------------------
export MACHINE_ID="${MACHINE_ID:-docker-$(uname -m)}"   # name for the results folder
export HOST_INFO="${HOST_INFO:-}"                         # free text: host machine, Docker resources
export SCALE="${SCALE:-10}"                               # TPC-H scale factor
export RUNS="${RUNS:-A A1 AF B C D E F}"
export WARMUP="${WARMUP:-1}"
export ITERATIONS="${ITERATIONS:-5}"

# --- Executor size: by default from what the container can use ------------------------
if [ -r /sys/fs/cgroup/memory.max ] && [ "$(cat /sys/fs/cgroup/memory.max)" != "max" ]; then
  _mem_bytes="$(cat /sys/fs/cgroup/memory.max)"
else
  _mem_bytes="$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) * 1024 ))"
fi
export MEM_GB="$(( _mem_bytes / 1024 / 1024 / 1024 ))"
export CORES="${CORES:-$(nproc)}"
export EXEC_MEM="${EXEC_MEM:-$(( MEM_GB * 30 / 100 ))g}"   # heap
export OFFHEAP="${OFFHEAP:-$(( MEM_GB * 30 / 100 ))g}"     # off-heap pool, the same in every run
export DRIVER_MEM="${DRIVER_MEM:-2g}"
export WORKER_MEM="${WORKER_MEM:-$(( MEM_GB * 60 / 100 + 1 ))g}"

# --- Spark standalone cluster inside the container -------------------------------------
export SPARK_MASTER_HOST=127.0.0.1
export SPARK_MASTER="spark://127.0.0.1:7077"
export PATH="$SPARK_HOME/bin:$PATH"
