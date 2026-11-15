#!/usr/bin/env bash
# Entry point of the image.
#   (no command)  the whole benchmark, then the report and the Spark UI
#   ui            the report and the Spark UI of earlier runs
#   shell         a bash shell in the container with the Spark cluster running
set -euo pipefail
cd /bench
source ./env.sh

HTTP_PID=""
cleanup() {
  [ -n "$HTTP_PID" ] && kill "$HTTP_PID" 2>/dev/null || true
  bash scripts/01_cluster.sh stop || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

serve_ui() {
  bash scripts/01_cluster.sh history
  python3 bench/report.py
  python3 -m http.server 8000 --bind 0.0.0.0 --directory "$REPORT_DIR" >/dev/null 2>&1 &
  HTTP_PID=$!
  cat <<EOF

==============================================================================
  Report    http://localhost:8000    times, plans side by side, raw files
  Spark UI  http://localhost:18080   every run; open one, then SQL / DataFrame
  Press Ctrl+C to stop.
==============================================================================
EOF
  wait "$HTTP_PID"
}

mkdir -p "$OUT_DIR" "$EVENTS_DIR" "$REPORT_DIR"

case "${1:-all}" in
  all)
    if [ "$CPUS" -ne 4 ] || [ "$MEM_GB" -ne 16 ]; then
      echo "NOTE: this container has $CPUS CPUs and $MEM_GB GB; the README runs with" >&2
      echo "      --cpus=4 --memory=16g, so these numbers are not directly comparable." >&2
    fi
    bash scripts/05_machine_info.sh
    bash scripts/01_cluster.sh start
    bash scripts/02_generate.sh
    bash scripts/03_load_iceberg.sh
    # A failing run does not stop the others; the report still shows what ran.
    FAILED=""
    for RUN in $RUNS; do bash scripts/10_run.sh "$RUN" || FAILED="$FAILED $RUN"; done
    bash scripts/30_api_diff.sh || FAILED="$FAILED api-diff"
    bash scripts/20_metrics.sh || FAILED="$FAILED metrics"
    if [ -n "$FAILED" ]; then
      echo "WARNING: failed:$FAILED (see driver.log under Raw files in the report)" >&2
    fi
    bash scripts/01_cluster.sh stop   # free the memory before serving the UI
    serve_ui
    ;;
  ui)
    serve_ui
    ;;
  shell)
    bash scripts/01_cluster.sh start
    echo "Scripts: /bench/scripts   data and outputs: /work   e.g. bash scripts/10_run.sh comet"
    bash || true
    ;;
  *)
    echo "Unknown command: $1 (use no command, ui or shell)" >&2
    exit 1
    ;;
esac
