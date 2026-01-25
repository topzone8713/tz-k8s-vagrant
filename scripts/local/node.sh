#!/usr/bin/env bash

# Exit on error - 설치 실패 시 중지
set -e

#set -x

echo "##############################################"
echo "Executing base.sh..."
echo "##############################################"
bash /vagrant/scripts/local/base.sh
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "✗ ERROR: base.sh execution failed (exit code: $EXIT_CODE)"
  echo "ERROR: Critical tools (kubectl, helm) installation failed!"
  echo "Please check /tmp/base.sh.log or /var/log/base.sh.log for details"
  exit 1
fi
echo "✓ base.sh executed successfully"
echo "##############################################"
