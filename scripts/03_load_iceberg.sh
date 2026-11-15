#!/usr/bin/env bash
# Loads $DATA_DIR/sf$SCALE/lineitem into the Iceberg table lake.tpch.lineitem with plain Spark
# (no Comet) and checks the row count against the TPC-H reference.
# Skipped when the table already holds this scale factor.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

MARKER="$WAREHOUSE/lineitem.scale"
if [ "$(cat "$MARKER" 2>/dev/null || true)" = "$SCALE" ]; then
  echo "== lake.tpch.lineitem already loaded at SF $SCALE"
  exit 0
fi

OUT="$(out_dir)"
mkdir -p "$OUT" "$WAREHOUSE"
SQL_FILE="$OUT/load_lineitem.sql"
sed -e "s|{parquet_dir}|$DATA_DIR/sf$SCALE/lineitem|" -e "s|{scale}|$SCALE|" sql/load_lineitem.sql > "$SQL_FILE"

echo "== Loading lineitem SF $SCALE into Iceberg (plain Spark)"
base_args
LOG="$OUT/load_lineitem"
if ! spark-sql "${ARGS[@]}" --name comet-blog-load -f "$SQL_FILE" > "$LOG.out" 2> "$LOG.err"; then
  tail -40 "$LOG.err" >&2
  exit 1
fi

# lineitem row counts of the TPC-H reference generator (SF 0.1 measured with tpchgen-cli 4.0.0)
case "$SCALE" in
  0.1) EXPECTED=600572 ;;
  1)   EXPECTED=6001215 ;;
  10)  EXPECTED=59986052 ;;
  100) EXPECTED=600037902 ;;
  *)   EXPECTED="" ;;
esac
ACTUAL="$(grep -E '^[0-9]+$' "$LOG.out" | tail -1 || true)"
if [ -n "$EXPECTED" ] && [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "ERROR: lineitem has $ACTUAL rows, expected $EXPECTED for SF $SCALE" >&2
  exit 1
fi
echo "$SCALE" > "$MARKER"
echo "== lake.tpch.lineitem: $ACTUAL rows${EXPECTED:+ (matches TPC-H SF $SCALE)}"
