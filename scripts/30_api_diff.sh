#!/usr/bin/env bash
# SQL and the PySpark DataFrame API give the same physical plan.
# Uses the comet configuration, so the plans show Comet operators.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

OUT="$(out_dir)/api_diff"
mkdir -p "$OUT"
run_args comet
export PYSPARK_PYTHON="${PYSPARK_PYTHON:-python3}"
spark-submit "${ARGS[@]}" --name comet-blog-api-diff bench/api_diff.py --out "$OUT" > "$OUT.log" 2>&1 \
  || { tail -40 "$OUT.log" >&2; exit 1; }
cat "$OUT/plan_diff.txt"
echo "Plans and diff: $OUT"
