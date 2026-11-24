#!/usr/bin/env bash
# CPU flame graph of the executor for one configuration, in a separate Spark application, so
# the timed runs are never profiled.
#   bash scripts/40_profile.sh spark|comet-default|comet|comet-fallback
# async-profiler runs as an agent in the executor JVM. The itimer engine samples the whole
# process without extra container privileges, so Comet's native threads are in the graph too.
# The graph is written when the executor exits: $OUT_DIR/sf$SCALE/profiles/<run>/flame-<pid>.html
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

RUN="${1:?usage: $0 spark|comet-default|comet|comet-fallback}"
OUT="$(out_dir)/profiles/$RUN"
LIB="$ASPROF_HOME/lib/libasyncProfiler.so"
[ -f "$LIB" ] || { echo "async-profiler not found in $ASPROF_HOME" >&2; exit 1; }
rm -f "$OUT"/flame-*.html
mkdir -p "$OUT"

run_args "$RUN"
ARGS+=(--conf "spark.executor.extraJavaOptions=-XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints -agentpath:$LIB=start,event=itimer,interval=1ms,file=$OUT/flame-%p.html")

echo "== Profiling $RUN (one warm-up, two iterations)"
if ! spark-submit "${ARGS[@]}" --name "comet-blog-profile-$RUN" \
    bench/bench.py --run "$RUN-profile" --query "$QUERY" --create sql/create_target.sql \
    --warmup 1 --iterations 2 --out "$OUT" > "$OUT/driver.log" 2>&1; then
  tail -40 "$OUT/driver.log" >&2
  exit 1
fi
for _ in $(seq 1 30); do   # the executor writes the graph as it shuts down
  if ls "$OUT"/flame-*.html >/dev/null 2>&1; then
    echo "== Flame graph: $(ls "$OUT"/flame-*.html)"
    exit 0
  fi
  sleep 1
done
echo "No flame graph in $OUT; see the executor log under $SPARK_HOME/work" >&2
exit 1
