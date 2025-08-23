#!/bin/bash

MAX_LOGS=${MAX_LOGS:-20}
LOG_DIR=${LOG_DIR:-"/var/log/glassminers"}
LOG_DATE_FORMAT=${LOG_DATE_FORMAT:-"%Y-%m-%d-%H-%M-%S"}

EXEC=./server.out
TIMESTAMP=$(date +"$LOG_DATE_FORMAT")

delete_old_logs() {
  if [ -d "$LOG_DIR" ]; then
    NUM_LOGS=$(ls -1q "$LOG_DIR"/*.log 2>/dev/null | wc -l)

    if ((NUM_LOGS > MAX_LOGS)); then
      OLDEST_LOGS=$(ls -1t "$LOG_DIR"/*.log | tail -n $((NUM_LOGS - MAX_LOGS)))
      for log_file in $OLDEST_LOGS; do
        rm "$log_file"
        echo "[Info] Removed old log: $log_file"
      done
    fi
  fi
}

rename_log() {
  if [ -f "$LOG_DIR/latest.log" ]; then
    STOP_TIMESTAMP=$(date +"$LOG_DATE_FORMAT")
    mv "$LOG_DIR/latest.log" "$LOG_DIR/$STOP_TIMESTAMP.log"
    echo "[Info] Renamed latest.log to $STOP_TIMESTAMP.log"
  else
    echo "[Warning] No latest.log file to rename"
  fi
}

clean_up() {
  rename_log
  delete_old_logs
}

trap 'clean_up; exit 0' SIGTERM

echo "[Info] Max number of logs set to $MAX_LOGS"
echo "[Info] Server is starting at [$TIMESTAMP]"

$EXEC | tee "$LOG_DIR/latest.log" &
SERVER_PID=$!

wait $SERVER_PID
EXIT_STATUS=$?

clean_up

echo "[Info] Server stopped at [$(date +"$LOG_DATE_FORMAT")] with exit code: $EXIT_STATUS"
sleep 5