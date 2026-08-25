#!/usr/bin/env bash
set -uo pipefail

# ===== 設定 =====
CONFIG_FILE="${SERVICE_MONITOR_CONFIG:-/etc/service-monitor.env}"
if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

SERVICES=("httpd:80" "tomcat:8080") # サービス名:HTTPポート
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
LOG_FILE="${LOG_FILE:-/var/log/service-monitor.log}"

# ===== ログ関数 =====
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" | sudo tee -a "$LOG_FILE" > /dev/null
}

# ===== 監視関数 =====
check_process() {
    local service="$1"
    systemctl is-active --quiet "$service"
}

check_http() {
    local port="$1"
    local code
    code=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 "http://localhost:${port}") || code="000"
    # 000は接続不能。それ以外の3桁ステータスはHTTP応答ありと判定する。
    [[ "$code" =~ ^[1-5][0-9]{2}$ ]]
}

# ===== メイン処理 =====
for entry in "${SERVICES[@]}"; do
    service="${entry%%:*}"
    port="${entry##*:}"

    if check_process "$service" && check_http "$port"; then
        log "OK: ${service} is running and responding on port ${port}"
        continue
    fi

    log "ALERT: ${service} appears down. Attempting restart..."
    sudo systemctl restart "$service"
    sleep 5

    if check_process "$service" && check_http "$port"; then
        log "RECOVERED: ${service} restarted successfully"
    else
        log "FAILED: ${service} restart did not resolve the issue"
        if [[ -z "$SNS_TOPIC_ARN" ]]; then
            log "ERROR: SNS_TOPIC_ARN is not configured; notification skipped"
            continue
        fi
        aws sns publish \
            --topic-arn "$SNS_TOPIC_ARN" \
            --subject "[ALERT] ${service} is down on $(hostname)" \
            --message "Service ${service} failed health check and restart at $(date). Manual intervention required." \
            --region "$AWS_REGION"
    fi
done
