#!/usr/bin/env bash
# Run G: CPU flame graph of the executor JVM with async-profiler, for one configuration.
#   bash scripts/40_profile.sh A    and    bash scripts/40_profile.sh C
# Needs async-profiler unpacked in $ASPROF_HOME (macOS: lib/libasyncProfiler.dylib,
# Linux: lib/libasyncProfiler.so). Download: https://github.com/async-profiler/async-profiler/releases
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

RUN="${1:?usage: $0 A|C}"
OUT="$(out_dir)/profiles/$RUN"
mkdir -p "$OUT"
LIB="$ASPROF_HOME/lib/libasyncProfiler.dylib"
[ -f "$LIB" ] || LIB="$ASPROF_HOME/lib/libasyncProfiler.so"
[ -f "$LIB" ] || { echo "async-profiler not found in $ASPROF_HOME" >&2; exit 1; }

run_args "$RUN"
# The profile covers the executor's whole life: one warm-up and two measured iterations.
ARGS+=(--conf "spark.executor.extraJavaOptions=-XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints -agentpath:$LIB=start,event=cpu,interval=1ms,file=$OUT/flame-cpu-%p.html")

export PYSPARK_PYTHON="${PYSPARK_PYTHON:-python3}"
spark-submit "${ARGS[@]}" --name "comet-blog-profile-$RUN" \
  bench/bench.py --run "$RUN-profile" --query "$QUERY" --create sql/create_target.sql \
  --warmup 1 --iterations 2 --out "$OUT" > "$OUT/driver.log" 2>&1 \
  || { tail -40 "$OUT/driver.log" >&2; exit 1; }
ls -1 "$OUT"/flame-*.html
