#!/usr/bin/env bash
# Generates TPC-H lineitem as Parquet at scale factor $SCALE into data/sf$SCALE/lineitem.
# The generator is deterministic: the same version and scale factor give the same rows.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

OUT="$DATA_DIR/sf$SCALE"
PARTS="${PARTS:-$(awk -v s="$SCALE" 'BEGIN { p = int(s); if (p < 4) p = 4; print p }')}"  # ~600 MB per file
mkdir -p "$OUT"
tpchgen-cli --version | tee "$OUT/generator.txt"
grep -q "$TPCHGEN_VERSION" "$OUT/generator.txt" || echo "WARNING: expected tpchgen-cli $TPCHGEN_VERSION" >&2
time tpchgen-cli parquet -s "$SCALE" --tables=lineitem --parts="$PARTS" --output-dir="$OUT"
du -sh "$OUT/lineitem"
echo "Next: bash scripts/03_load_iceberg.sh"
