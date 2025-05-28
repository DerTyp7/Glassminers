#!/bin/bash

EXEC=./server.out
TIME=5

while [ true ]; do
    $EXEC
    echo "[WCHDOG][ Info] Server was stopped at [$(date +"%d.%m.%Y %T")] with: $?"
    echo "[WCHDOG][ Info] Restarting in $TIME seconds unless enter is pressed..."
    read -t $TIME input;
    if [ $? == 0 ]; then
        break;
    fi
done
