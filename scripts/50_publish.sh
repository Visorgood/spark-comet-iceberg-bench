#!/usr/bin/env bash
# Copies the curated outputs of $MACHINE_ID / SF $SCALE to $EXPORT_DIR/results/<machine>/sf<scale>/,
# i.e. into the results/ folder of your checkout when it is mounted at /export:
#   docker run --rm -v spark-comet-bench:/work -v "$PWD":/export <image> export
# Copies summary, per-run metrics and plans, API diff, flame graphs, screenshots,
# machine.txt and versions.txt. Event logs, data and driver logs stay in the volume.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

SRC="$(out_dir)"
[ -d "$EXPORT_DIR" ] || { echo "Mount a folder at $EXPORT_DIR: -v \"\$PWD\":$EXPORT_DIR" >&2; exit 1; }
[ -f "$SRC/summary.csv" ] || { echo "No $SRC/summary.csv yet: run the benchmark first." >&2; exit 1; }
DST="$EXPORT_DIR/results/$MACHINE_ID/sf$SCALE"
mkdir -p "$DST"
HOST="$(hostname)"   # the container id; masked so it does not end up in the repository

copy_text() { sed -e "s|$HOST|<host>|g" "$1" > "$2"; }

for f in machine.txt versions.txt; do
  if [ -f "$OUT_DIR/$MACHINE_ID/$f" ]; then
    copy_text "$OUT_DIR/$MACHINE_ID/$f" "$EXPORT_DIR/results/$MACHINE_ID/$f"
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
for f in "$SRC"/profiles/*/flame-*.html; do
  if [ ! -f "$f" ]; then continue; fi
  mkdir -p "$DST/profiles"
  cp "$f" "$DST/profiles/flame-cpu-$(basename "$(dirname "$f")").html"
done
if [ -d "$SRC/screenshots" ]; then
  mkdir -p "$DST/screenshots"
  cp "$SRC"/screenshots/*.png "$DST/screenshots/" 2>/dev/null || true
fi
# Give the files the owner of the mounted folder, not root (matters on Linux hosts).
chown -R "$(stat -c %u:%g "$EXPORT_DIR")" "$EXPORT_DIR/results"
echo "== Exported to results/$MACHINE_ID/sf$SCALE in the mounted folder"
