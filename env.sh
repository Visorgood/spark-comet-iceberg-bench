# Source this file before running any script:   source ./env.sh
#
# Defaults keep every download, build and output inside this repository.
# Personal settings (MACHINE_ID, cores, memory, paths to existing installs) go to
# env.local.sh, which git ignores; start from env.local.sh.example.

# --- Pinned versions: these define what the published results mean ------------
export SPARK_VERSION=4.1.3
export SCALA_BINARY=2.13
export ICEBERG_VERSION=1.11.0
export TPCHGEN_VERSION=4.0.0
# Comet: either a release (COMET_RELEASE) or a commit of apache/datafusion-comet (COMET_REF).
# With COMET_RELEASE set, Linux downloads the published jar and macOS builds the release source.
export COMET_RELEASE="${COMET_RELEASE:-}"
export COMET_REF="${COMET_REF:-460129cbb96f0f2d5c64dbfd2c973ba91f52cf9e}"   # main, 14 Nov 2026

# --- Repository root and personal overrides -----------------------------------
export BENCH_ROOT="${BENCH_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
if [ -f "$BENCH_ROOT/env.local.sh" ]; then
  . "$BENCH_ROOT/env.local.sh"
fi

# --- Paths (all inside the repository unless env.local.sh says otherwise) -------
export DEPS_DIR="${DEPS_DIR:-$BENCH_ROOT/deps}"              # Spark, Comet, async-profiler
export SPARK_HOME="${SPARK_HOME:-$DEPS_DIR/spark-${SPARK_VERSION}-bin-hadoop3}"
export COMET_HOME="${COMET_HOME:-$DEPS_DIR/datafusion-comet}"  # Comet source tree to build
export ASPROF_HOME="${ASPROF_HOME:-$DEPS_DIR/async-profiler}"  # only for the flame graphs
export DATA_DIR="${DATA_DIR:-$BENCH_ROOT/data}"                # generated TPC-H Parquet
export WAREHOUSE="${WAREHOUSE:-$BENCH_ROOT/warehouse}"         # Iceberg Hadoop-catalog warehouse
export EVENTS_DIR="${EVENTS_DIR:-$BENCH_ROOT/spark-events}"    # Spark event logs
export OUT_DIR="${OUT_DIR:-$BENCH_ROOT/out}"                   # raw outputs (not committed)
export RESULTS_DIR="${RESULTS_DIR:-$BENCH_ROOT/results}"       # curated results (committed)

# --- Machine and data size -----------------------------------------------------
export MACHINE_ID="${MACHINE_ID:-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)}"
export SCALE="${SCALE:-10}"          # TPC-H scale factor: 0.1 smoke test, 10 check, 100 final
export CORES="${CORES:-8}"           # executor cores
export EXEC_MEM="${EXEC_MEM:-16g}"   # executor heap
export OFFHEAP="${OFFHEAP:-16g}"     # off-heap pool; the same in every run, Spark-only runs included
export DRIVER_MEM="${DRIVER_MEM:-4g}"
export WORKER_MEM="${WORKER_MEM:-40g}"  # >= EXEC_MEM + OFFHEAP + headroom
export WARMUP="${WARMUP:-1}"
export ITERATIONS="${ITERATIONS:-5}"

# --- Spark standalone cluster on this machine -----------------------------------
export SPARK_MASTER_HOST=127.0.0.1
export SPARK_MASTER="spark://127.0.0.1:7077"

export ICEBERG_PACKAGES="org.apache.iceberg:iceberg-spark-runtime-4.1_${SCALA_BINARY}:${ICEBERG_VERSION},org.apache.iceberg:iceberg-core:${ICEBERG_VERSION}"
export PATH="$SPARK_HOME/bin:$PATH"
