#!/bin/bash

EXEC=./server.out
TIME=5

mkdir -p logs

while [ true ]; do
    TIMESTAMP=$(date +"%d.%m.%Y %T")
    echo "[WCHDOG][Info] Server is starting at [$TIMESTAMP] with: $?"
    $EXEC > "logs/$TIMESTAMP.log"
    echo "[WCHDOG][Info] Server stopped at [$(date +"%d.%m.%Y %T")] with: $?"
    echo "[WCHDOG][Info] Restarting in $TIME seconds unless enter is pressed..."
    read -t $TIME input;
    if [ $? == 0 ]; then
        break;
    fi
done
