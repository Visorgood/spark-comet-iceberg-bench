#!/usr/bin/env bash
# Extracts per-iteration metrics, final plans and the summary table from the event logs.
# Python standard library only; Spark does not need to be running.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

OUT="$(out_dir)"
python3 bench/metrics.py --events "$EVENTS_DIR" --results "$OUT"
if command -v column >/dev/null; then
  column -s, -t < "$OUT/summary.csv"
else
  cat "$OUT/summary.csv"
fi
