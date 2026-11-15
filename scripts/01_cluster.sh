#!/usr/bin/env bash
# Starts or stops the one-worker Spark standalone cluster inside the container,
# and the History Server (the Spark UI of finished runs) on port 18080.
#   bash scripts/01_cluster.sh start | stop | history
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

case "${1:-}" in
  start)
    mkdir -p "$EVENTS_DIR"
    if ! curl -fs http://127.0.0.1:8080/json/ >/dev/null 2>&1; then
      "$SPARK_HOME/sbin/start-master.sh" >/dev/null
      "$SPARK_HOME/sbin/start-worker.sh" "$MASTER_URL" --cores "$CORES" --memory "$WORKER_MEM" >/dev/null
    fi
    for _ in $(seq 1 60); do   # wait until the worker has registered
      if curl -fs http://127.0.0.1:8080/json/ | grep -q '"aliveworkers" *: *1'; then
        echo "== Spark cluster up: 1 worker, $CORES cores, executor heap $EXEC_MEM, off-heap $OFFHEAP"
        exit 0
      fi
      sleep 1
    done
    echo "Spark worker did not register; see $SPARK_HOME/logs" >&2
    exit 1
    ;;
  history)
    SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=file://$EVENTS_DIR -Dspark.history.fs.update.interval=5s" \
      "$SPARK_HOME/sbin/start-history-server.sh" >/dev/null
    ;;
  stop)
    "$SPARK_HOME/sbin/stop-history-server.sh" >/dev/null 2>&1 || true
    "$SPARK_HOME/sbin/stop-worker.sh" >/dev/null 2>&1 || true
    "$SPARK_HOME/sbin/stop-master.sh" >/dev/null 2>&1 || true
    ;;
  *) echo "usage: $0 start|stop|history" >&2; exit 1 ;;
esac
