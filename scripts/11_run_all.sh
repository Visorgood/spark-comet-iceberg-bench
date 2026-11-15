#!/usr/bin/env bash
# Runs the whole matrix, then extracts the metrics.
#   bash scripts/11_run_all.sh                 all runs
#   RUNS="A C" bash scripts/11_run_all.sh      a subset
set -euo pipefail
cd "$(dirname "$0")/.."
for RUN in ${RUNS:-A A1 AF B C D E F}; do
  bash scripts/10_run.sh "$RUN"
done
bash scripts/20_metrics.sh
