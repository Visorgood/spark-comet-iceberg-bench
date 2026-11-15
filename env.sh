# Settings for the scripts inside the Docker image; sourced by docker/entrypoint.sh and every script.
# The only setting meant to be changed is SCALE: docker run -e SCALE=0.1 ...
# Versions (SPARK_VERSION, ICEBERG_VERSION, COMET_VERSION) and COMET_JAR are set in the Dockerfile.

export BENCH_ROOT=/bench
export WORK=/work                       # the Docker volume: data, tables, logs, outputs
export SPARK_HOME=/opt/spark
export DATA_DIR="$WORK/data"            # generated TPC-H Parquet
export WAREHOUSE="$WORK/warehouse"      # Iceberg tables (Hadoop catalog "lake")
export EVENTS_DIR="$WORK/spark-events"  # Spark event logs, read by the History Server
export OUT_DIR="$WORK/out"              # per-run outputs: timings, metrics, plans
export REPORT_DIR="$WORK/report"        # the HTML report served on port 8000

export SCALE="${SCALE:-10}"             # TPC-H scale factor
export RUNS="spark comet comet-fallback"
export WARMUP=1
export ITERATIONS=5

# Executor size from the container's limits (README: docker run --cpus=4 --memory=16g):
# all its CPUs, 30% of its memory as heap and 30% as off-heap (Comet's memory; the
# Spark-only run gets the same pool). With 4 CPUs and 16 GB: 4 cores, 4g heap, 4g off-heap.
if [ -r /sys/fs/cgroup/memory.max ] && [ "$(cat /sys/fs/cgroup/memory.max)" != "max" ]; then
  _mem_bytes="$(cat /sys/fs/cgroup/memory.max)"
else
  _mem_bytes="$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) * 1024 ))"
fi
export MEM_GB="$(( _mem_bytes / 1024 / 1024 / 1024 ))"
# nproc ignores --cpus (a CPU-time quota), so read the quota from the cgroup.
_cpus="$(nproc)"
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r _quota _period < /sys/fs/cgroup/cpu.max
  if [ "$_quota" != "max" ]; then
    _limit="$(( _quota / _period ))"
    [ "$_limit" -ge 1 ] || _limit=1
    if [ "$_limit" -lt "$_cpus" ]; then _cpus="$_limit"; fi
  fi
fi
export CPUS="$_cpus"
_pool_gb="$(( MEM_GB * 30 / 100 ))"
[ "$_pool_gb" -ge 1 ] || _pool_gb=1
export CORES="$CPUS"
export EXEC_MEM="${_pool_gb}g"
export OFFHEAP="${_pool_gb}g"
export DRIVER_MEM=2g
export WORKER_MEM="$(( _pool_gb + 1 ))g"   # a standalone worker accounts only for the executor heap
export SPARK_DAEMON_MEMORY=512m             # Spark master, worker and History Server

# One-worker Spark standalone cluster inside the container
export SPARK_MASTER_HOST=127.0.0.1
export SPARK_MASTER="spark://127.0.0.1:7077"
export PATH="$SPARK_HOME/bin:$PATH"
