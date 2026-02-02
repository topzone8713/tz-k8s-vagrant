#!/usr/bin/env bash

# Exit on error - 설치 실패 시 중지
set -e

#set -x

echo "##############################################"
echo "Executing base.sh..."
echo "##############################################"

# Log file paths to monitor
LOG_FILE="/var/log/base.sh.log"
if [ ! -f "$LOG_FILE" ] || [ ! -w "$LOG_FILE" ]; then
  LOG_FILE="/tmp/base.sh.log"
fi

# Run base.sh with timeout monitoring
# Use timeout command if available, otherwise run normally
if command -v timeout > /dev/null 2>&1; then
  # Use timeout (30 minutes max for base.sh execution)
  timeout 1800 bash /vagrant/scripts/local/base.sh
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 124 ]; then
    echo "✗ ERROR: base.sh execution timed out after 30 minutes"
    echo "ERROR: base.sh execution timed out. Check $LOG_FILE for details"
    echo "Last 50 lines of log:"
    tail -50 "$LOG_FILE" 2>/dev/null || echo "Log file not accessible"
    exit 1
  fi
else
  # No timeout command available, run normally but monitor log file
  bash /vagrant/scripts/local/base.sh &
  BASE_PID=$!
  
  # Monitor progress by checking log file updates (max 30 minutes)
  MAX_WAIT=1800
  WAIT_COUNT=0
  LAST_LOG_SIZE=0
  STALL_COUNT=0
  
  while kill -0 $BASE_PID 2>/dev/null; do
    sleep 10
    WAIT_COUNT=$((WAIT_COUNT + 10))
    
    # Check if log file is growing (indicates progress)
    if [ -f "$LOG_FILE" ]; then
      CURRENT_LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
      if [ "$CURRENT_LOG_SIZE" -eq "$LAST_LOG_SIZE" ]; then
        STALL_COUNT=$((STALL_COUNT + 1))
        if [ $STALL_COUNT -ge 12 ]; then
          # No progress for 2 minutes (12 * 10s), show last log lines
          echo "WARNING: base.sh appears to be stalled. Last log entries:"
          tail -20 "$LOG_FILE" 2>/dev/null || echo "Log file not accessible"
          STALL_COUNT=0
        fi
      else
        STALL_COUNT=0
        LAST_LOG_SIZE=$CURRENT_LOG_SIZE
      fi
    fi
    
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
      echo "ERROR: base.sh execution exceeded maximum wait time (30 minutes)"
      kill $BASE_PID 2>/dev/null || true
      echo "Last 50 lines of log:"
      tail -50 "$LOG_FILE" 2>/dev/null || echo "Log file not accessible"
      exit 1
    fi
  done
  
  # Wait for process to finish and get exit code
  wait $BASE_PID
  EXIT_CODE=$?
fi

if [ $EXIT_CODE -ne 0 ]; then
  echo "✗ ERROR: base.sh execution failed (exit code: $EXIT_CODE)"
  echo "ERROR: Critical tools (kubectl, helm) installation failed!"
  echo "Please check $LOG_FILE for details"
  echo "Last 50 lines of log:"
  tail -50 "$LOG_FILE" 2>/dev/null || echo "Log file not accessible"
  exit 1
fi
echo "✓ base.sh executed successfully"
echo "##############################################"
