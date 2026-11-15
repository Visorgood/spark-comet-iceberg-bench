#!/usr/bin/env bash
# Generates TPC-H lineitem as Parquet at scale factor $SCALE into $DATA_DIR/sf$SCALE/lineitem.
# The generator is deterministic. Skipped when the data is already in the volume.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

OUT="$DATA_DIR/sf$SCALE"
if [ -f "$OUT/.done" ]; then
  echo "== lineitem SF $SCALE already generated"
  exit 0
fi
PARTS="$(awk -v s="$SCALE" 'BEGIN { p = int(s); if (p < 4) p = 4; print p }')"  # ~600 MB per file
mkdir -p "$OUT"
echo "== Generating lineitem, SF $SCALE, $PARTS files"
tpchgen-cli parquet -s "$SCALE" --tables=lineitem --parts="$PARTS" --output-dir="$OUT"
du -sh "$OUT/lineitem"
touch "$OUT/.done"
