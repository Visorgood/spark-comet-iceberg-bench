#!/usr/bin/env bash
# Copies the curated part of out/$MACHINE_ID/sf$SCALE into results/$MACHINE_ID/sf$SCALE,
# the folder that is committed: summary, per-run metrics and plans, API diff, flame graphs,
# screenshots, machine.txt and versions.txt. Event logs, data and driver logs stay out.
# Text files get your home directory and host name replaced, so nothing personal is published.
# It only adds or overwrites files under results/; review with `git status` before committing.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

SRC="$(out_dir)"
DST="$RESULTS_DIR/$MACHINE_ID/sf$SCALE"
[ -f "$SRC/summary.csv" ] || { echo "No $SRC/summary.csv: run bash scripts/20_metrics.sh first." >&2; exit 1; }
mkdir -p "$DST"
HOST="$(hostname)"

copy_text() {  # $1 = source file, $2 = destination file
  sed -e "s|$HOME|~|g" -e "s|$HOST|<host>|g" "$1" > "$2"
}

for f in machine.txt versions.txt; do
  if [ -f "$OUT_DIR/$MACHINE_ID/$f" ]; then
    copy_text "$OUT_DIR/$MACHINE_ID/$f" "$RESULTS_DIR/$MACHINE_ID/$f"
  fi
done
copy_text "$SRC/summary.csv" "$DST/summary.csv"

for run_dir in "$SRC"/*/; do
  run="$(basename "$run_dir")"
  if [ ! -f "$run_dir/app_id.txt" ]; then continue; fi
  mkdir -p "$DST/$run"
  for f in wall.csv iterations.csv stages_iter1.csv accumulables_iter1.csv \
           explain_formatted.txt explain_extended.txt final_plan_iter1.txt spark_conf.txt; do
    if [ -f "$run_dir/$f" ]; then copy_text "$run_dir/$f" "$DST/$run/$f"; fi
  done
done

if [ -d "$SRC/api_diff" ]; then
  mkdir -p "$DST/api_diff"
  for f in "$SRC"/api_diff/*.txt; do copy_text "$f" "$DST/api_diff/$(basename "$f")"; done
fi
if [ -d "$SRC/profiles" ]; then
  for f in "$SRC"/profiles/*/flame-*.html; do
    if [ ! -f "$f" ]; then continue; fi
    run="$(basename "$(dirname "$f")")"
    mkdir -p "$DST/profiles"
    cp "$f" "$DST/profiles/flame-cpu-$run.html"
  done
fi
if [ -d "$SRC/screenshots" ]; then
  mkdir -p "$DST/screenshots"
  cp "$SRC"/screenshots/*.png "$DST/screenshots/" 2>/dev/null || true
fi

echo "== Copied to $DST"
du -sh "$DST"
echo "Review: git status && git diff --stat"
