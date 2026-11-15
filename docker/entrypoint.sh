#!/usr/bin/env bash
# Entry point of the image. Default command `all`: the whole benchmark, then the UI.
# Other commands are for step-by-step runs and debugging; see `help`.
set -euo pipefail
cd /bench
source ./env.sh

usage() {
  cat <<EOF
Commands:  docker run ... <image> <command> [args]
  all            generate data, run: $RUNS, metrics, API diff, report, then serve the UI (default)
  data           generate lineitem and load it into Iceberg for SCALE=$SCALE
  run A C ...    run the given configurations, then extract their metrics
  metrics        extract metrics and final plans from the event logs
  api-diff       compare the SQL and DataFrame API plans
  profile A C    CPU flame graphs for the given runs
  report         rebuild the HTML report
  ui             serve the report (port 8000) and the Spark UI (port 18080) for earlier runs
  export         copy curated results to /export/results (mount a folder at /export)
  shell          a bash shell inside the container with the Spark cluster running
Settings (docker run -e NAME=value): SCALE, RUNS, ITERATIONS, WARMUP, CORES, EXEC_MEM, OFFHEAP,
  MACHINE_ID, HOST_INFO, PROFILE=1 (flame graphs in 'all'), API_DIFF=0 (skip it in 'all')
EOF
}

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
  Report    http://localhost:8000    times, ratios to Spark, plans side by side
  Spark UI  http://localhost:18080   every run; open one, then the SQL / DataFrame tab
  Data, tables and outputs stay in the Docker volume mounted at /work.
  Press Ctrl+C to stop.
==============================================================================
EOF
  wait "$HTTP_PID"
}

mkdir -p "$OUT_DIR" "$EVENTS_DIR" "$REPORT_DIR"
if [ "$MEM_GB" -lt 12 ]; then
  echo "WARNING: the container sees only ${MEM_GB} GB of memory. Give Docker more (Docker Desktop:" >&2
  echo "         Settings > Resources) or use a smaller SCALE." >&2
fi

CMD="${1:-all}"
shift || true
case "$CMD" in
  all)
    bash scripts/05_machine_info.sh
    bash scripts/01_cluster.sh start
    bash scripts/02_generate.sh
    bash scripts/03_load_iceberg.sh
    # A failing configuration does not stop the others; the UI still shows what ran.
    FAILED=""
    for RUN in $RUNS; do bash scripts/10_run.sh "$RUN" || FAILED="$FAILED $RUN"; done
    bash scripts/20_metrics.sh || FAILED="$FAILED metrics"
    if [ "${API_DIFF:-1}" = "1" ]; then bash scripts/30_api_diff.sh || FAILED="$FAILED api-diff"; fi
    if [ "${PROFILE:-0}" = "1" ]; then
      bash scripts/40_profile.sh A || FAILED="$FAILED profile-A"
      bash scripts/40_profile.sh C || FAILED="$FAILED profile-C"
    fi
    if [ -n "$FAILED" ]; then
      echo "WARNING: failed:$FAILED (driver logs: $OUT_DIR/$MACHINE_ID/sf$SCALE/<run>/driver.log)" >&2
    fi
    bash scripts/01_cluster.sh stop   # free the memory before serving the UI
    serve_ui
    ;;
  data)
    bash scripts/05_machine_info.sh
    bash scripts/01_cluster.sh start
    bash scripts/02_generate.sh
    bash scripts/03_load_iceberg.sh
    ;;
  run)
    [ "$#" -gt 0 ] || { echo "usage: run A C ..." >&2; exit 1; }
    bash scripts/05_machine_info.sh
    bash scripts/01_cluster.sh start
    for RUN in "$@"; do bash scripts/10_run.sh "$RUN"; done
    bash scripts/20_metrics.sh
    ;;
  metrics)  bash scripts/20_metrics.sh ;;
  api-diff)
    bash scripts/01_cluster.sh start
    bash scripts/30_api_diff.sh
    ;;
  profile)
    bash scripts/01_cluster.sh start
    PROFILE_RUNS="${*:-A C}"
    for RUN in $PROFILE_RUNS; do bash scripts/40_profile.sh "$RUN"; done
    ;;
  report)   python3 bench/report.py ;;
  ui)       serve_ui ;;
  export)   bash scripts/50_publish.sh ;;
  shell)
    bash scripts/01_cluster.sh start
    bash || true
    ;;
  help|-h|--help) usage ;;
  *) echo "Unknown command: $CMD" >&2; usage; exit 1 ;;
esac
