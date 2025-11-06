#!/bin/bash

echo "Stopping worker process..."

WORKER_PATTERN="python -u app/worker.py"

# pgrep은 찾은 PID를 줄 단위로 출력하므로 공백 분리 가능
PIDS=$(pgrep -f "$WORKER_PATTERN" || true)

if [ -z "$PIDS" ]; then
    echo "No worker process found (already stopped?)."
else
    echo "Worker PID(s) detected: $PIDS"
    for PID in $PIDS; do
        if kill "$PID" 2>/dev/null; then
            echo "Sent SIGTERM to PID $PID"
        fi
    done

    # 잠시 대기 후 잔존 PID 확인
    sleep 2
    REMAINING=$(pgrep -f "$WORKER_PATTERN" || true)
    if [ -n "$REMAINING" ]; then
        echo "Worker still running (PID: $REMAINING). Sending SIGKILL."
        kill -9 $REMAINING 2>/dev/null || true
    fi
fi

echo "Life Cycle - ApplicationStop: complete."
