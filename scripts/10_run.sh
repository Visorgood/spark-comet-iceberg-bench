#!/usr/bin/env bash
# Runs one configuration: warm-up + measured iterations in one Spark application.
#   bash scripts/10_run.sh spark|comet|comet-fallback
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

RUN="${1:?usage: $0 spark|comet|comet-fallback}"
OUT="$(out_dir)/$RUN"
mkdir -p "$OUT"
run_args "$RUN"

export PYSPARK_PYTHON="${PYSPARK_PYTHON:-python3}"
set +e
spark-submit "${ARGS[@]}" --name "comet-blog-$RUN" \
  bench/bench.py --run "$RUN" --query "$QUERY" --create sql/create_target.sql \
  --warmup "$WARMUP" --iterations "$ITERATIONS" --out "$OUT" 2>&1 | tee "$OUT/driver.log" | grep --line-buffered -E "^\[bench\]"
STATUS=${PIPESTATUS[0]}
set -e
if [ "$STATUS" -ne 0 ]; then
  echo "spark-submit failed with $STATUS; last lines of $OUT/driver.log:" >&2
  tail -40 "$OUT/driver.log" >&2
  exit "$STATUS"
fi
echo "== $RUN done: $OUT"
