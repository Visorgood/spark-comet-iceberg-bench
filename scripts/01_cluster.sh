#!/usr/bin/env bash
# Start or stop a one-worker Spark standalone cluster and the History Server on this machine.
#   scripts/01_cluster.sh start | stop
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

case "${1:-}" in
  start)
    mkdir -p "$EVENTS_DIR"
    "$SPARK_HOME/sbin/start-master.sh"
    "$SPARK_HOME/sbin/start-worker.sh" "$SPARK_MASTER" --cores "$CORES" --memory "$WORKER_MEM"
    SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=file://$EVENTS_DIR" \
      "$SPARK_HOME/sbin/start-history-server.sh"
    echo "Master UI:      http://localhost:8080"
    echo "History Server: http://localhost:18080   (the Spark UI of finished runs, for screenshots)"
    ;;
  stop)
    "$SPARK_HOME/sbin/stop-history-server.sh" || true
    "$SPARK_HOME/sbin/stop-worker.sh" || true
    "$SPARK_HOME/sbin/stop-master.sh" || true
    ;;
  *) echo "usage: $0 start|stop" >&2; exit 1 ;;
esac
