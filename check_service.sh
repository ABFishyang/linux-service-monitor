#!/bin/bash
set -uo pipefail

# ===== 配置区 =====
SERVICES=("httpd:80" "tomcat:8080")   # 服务名:HTTP端口
# 実運用ではEC2側で環境変数SNS_TOPIC_ARNを事前にexportしておく想定。
# 未設定時はプレースホルダーのままとなり、publish時にエラーとなる(アカウントIDをコードに含めないための設計)。
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:ap-northeast-1:<YOUR_ACCOUNT_ID>:service-alert}"
LOG_FILE="/var/log/service-monitor.log"
MAX_RETRY=1

# ===== 日志函数 =====
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" | sudo tee -a "$LOG_FILE" > /dev/null
}

# ===== 检查函数 =====
check_process() {
    local service="$1"
    systemctl is-active --quiet "$service"
}

check_http() {
    local port="$1"
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://localhost:${port}")
    # 000 = 完全连不上（进程可能真的挂了/端口不通）
    # 其他任何三位数状态码 = 服务本身在正常响应请求
    [ "$code" != "000" ] && [ -n "$code" ]
}

# ===== 主逻辑 =====
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
        aws sns publish \
            --topic-arn "$SNS_TOPIC_ARN" \
            --subject "[ALERT] ${service} is down on $(hostname)" \
            --message "Service ${service} failed health check and restart at $(date). Manual intervention required." \
            --region ap-northeast-1
    fi
done
