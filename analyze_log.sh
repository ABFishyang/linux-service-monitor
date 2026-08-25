#!/bin/bash
set -uo pipefail

LOG_FILE="/var/log/httpd/access_log"
REPORT_FILE="/var/log/access-log-report.log"

echo "===== $(date '+%Y-%m-%d %H:%M:%S') Access Log Report =====" | sudo tee "$REPORT_FILE"

echo "" | sudo tee -a "$REPORT_FILE"
echo "--- HTTP Status Code Distribution ---" | sudo tee -a "$REPORT_FILE"
sudo awk '{print $9}' "$LOG_FILE" | sort | uniq -c | sort -rn | sudo tee -a "$REPORT_FILE"

echo "" | sudo tee -a "$REPORT_FILE"
echo "--- Top 5 Client IPs ---" | sudo tee -a "$REPORT_FILE"
sudo awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -rn | head -5 | sudo tee -a "$REPORT_FILE"

echo "" | sudo tee -a "$REPORT_FILE"
echo "--- Error Requests (4xx/5xx) ---" | sudo tee -a "$REPORT_FILE"
sudo grep -E '" [45][0-9]{2} ' "$LOG_FILE" | sudo tee -a "$REPORT_FILE"

echo "" | sudo tee -a "$REPORT_FILE"
echo "===== Report generated. Saved to ${REPORT_FILE} =====" | sudo tee -a "$REPORT_FILE"
