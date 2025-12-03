#!/bin/bash
set -euo pipefail

# Configuration
CONFIG_FILE="/config/backup.conf"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/logs/backup-${TIMESTAMP}.log"
FINAL_DIR="/backups/full/${TIMESTAMP}"
LOCK_FILE="/tmp/gitlab-backup.lock"

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "❌ 配置文件 /config/backup.conf 未找到" >&2
  echo "请从 config/backup.conf.example 复制并配置" >&2
  exit 1
fi

source "$CONFIG_FILE"

# Create directories
mkdir -p "$FINAL_DIR" "$(dirname "$LOG_FILE")"

# Logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Feishu notification function
send_feishu() {
  local status="$1"
  local msg="$2"
  
  [[ "${ENABLE_FEISHU_NOTIFY:-false}" != "true" ]] && return 0
  
  local color="red"
  [[ "$status" == "成功" ]] && color="green"
  [[ "$status" == "警告" ]] && color="orange"
  
  local payload=$(cat <<EOF
{
  "msg_type": "interactive",
  "card": {
    "header": {
      "title": {"tag": "plain_text", "content": "GitLab备份${status}"},
      "template": "${color}"
    },
    "elements": [
      {
        "tag": "div",
        "text": {
          "tag": "lark_md",
          "content": "**时间:** $(date +'%Y-%m-%d %H:%M:%S')\n**状态:** ${status}\n**详情:** ${msg}\n**主机:** $(hostname)"
        }
      }
    ]
  }
}
EOF
)
  
  curl -sfSL -H 'Content-Type: application/json' -d "$payload" "$FEISHU_WEBHOOK_URL" >/dev/null 2>&1 || true
}

# Cleanup function
cleanup() {
  local exit_code=$?
  rm -f "$LOCK_FILE"
  
  if [[ $exit_code -ne 0 ]]; then
    log "❌ 备份失败，退出码: $exit_code"
    send_feishu "失败" "备份异常终止，请检查日志"
  fi
  
  exit $exit_code
}

trap cleanup EXIT INT TERM

# Acquire lock to prevent concurrent backups
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "❌ 另一个备份进程正在运行"
  send_feishu "警告" "检测到并发备份，已跳过"
  exit 1
fi

# Check disk space
log "检查磁盘空间..."
DISK_USAGE=$(df /backups | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 85 ]]; then
  log "⚠️ 警告：备份磁盘使用率 ${DISK_USAGE}%"
  send_feishu "警告" "备份磁盘使用率 ${DISK_USAGE}%，即将满"
fi

# Start backup
log "========================================="
log "开始 GitLab 容器化备份"
log "主机: $(hostname)"
log "时间: $(date +'%Y-%m-%d %H:%M:%S')"
log "========================================="

# Step 1: Trigger GitLab internal backup
log "步骤 1/7: 触发 GitLab 内部备份..."

SKIP_OPTS=""
[[ "${SKIP_ARTIFACTS:-true}" == "true" ]] && SKIP_OPTS="SKIP=artifacts"

if ! docker exec "$GITLAB_CONTAINER_NAME" gitlab-backup create $SKIP_OPTS 2>&1 | tee -a "$LOG_FILE"; then
  log "❌ gitlab-backup create 失败"
  send_feishu "失败" "GitLab 内部备份命令失败"
  exit 1
fi

# Step 2: Find and copy backup file
log "步骤 2/7: 复制备份文件..."

BACKUP_FILE=$(ls -t /gitlab/backups/*.tar 2>/dev/null | head -1)
if [[ -z "$BACKUP_FILE" ]]; then
  log "❌ 未在 /gitlab/backups 找到 .tar 文件"
  send_feishu "失败" "找不到 GitLab 生成的备份文件"
  exit 1
fi

BACKUP_DEST="$FINAL_DIR/gitlab_data_${TIMESTAMP}.tar"
cp "$BACKUP_FILE" "$BACKUP_DEST"
log "备份文件已保存: $BACKUP_DEST"

# Step 3: Verify backup integrity
log "步骤 3/7: 验证备份完整性..."

if ! tar -tzf "$BACKUP_DEST" >/dev/null 2>&1; then
  log "❌ 备份文件损坏，无法解压"
  send_feishu "失败" "备份文件完整性验证失败"
  exit 1
fi

# Calculate checksum
sha256sum "$BACKUP_DEST" > "$FINAL_DIR/checksums.txt"
log "✓ 备份文件验证通过"

# Step 4: Backup configuration files
log "步骤 4/7: 备份配置文件..."

[[ -f /gitlab/config/gitlab.rb ]] && cp /gitlab/config/gitlab.rb "$FINAL_DIR/" && log "  ✓ gitlab.rb"
[[ -f /gitlab/config/gitlab-secrets.json ]] && cp /gitlab/config/gitlab-secrets.json "$FINAL_DIR/" && log "  ✓ gitlab-secrets.json"

# Step 5: Backup SSL certificates (optional)
if [[ -d /gitlab/ssl ]]; then
  log "步骤 5/7: 备份 SSL 证书..."
  tar -czf "$FINAL_DIR/certs.tar.gz" -C /gitlab/ssl . 2>/dev/null && log "  ✓ certs.tar.gz"
fi

# Step 6: Backup GitLab Runner (optional)
if [[ -d /gitlab-runner ]]; then
  log "步骤 6/7: 备份 GitLab Runner..."
  tar -czf "$FINAL_DIR/runner.tar.gz" -C /gitlab-runner . 2>/dev/null && log "  ✓ runner.tar.gz"
fi

# Step 7: Remote synchronization (optional)
if [[ "${REMOTE_BACKUP_ENABLED:-false}" == "true" ]]; then
  log "步骤 7/7: 远程同步..."
  
  # Setup SSH known_hosts
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  REMOTE_HOST=$(echo "$REMOTE_SERVER" | cut -d@ -f2 | cut -d: -f1)
  
  if [[ ! -f ~/.ssh/known_hosts ]] || ! grep -q "$REMOTE_HOST" ~/.ssh/known_hosts; then
    log "  添加远程主机指纹..."
    ssh-keyscan -H "$REMOTE_HOST" 2>/dev/null | sort -u >> ~/.ssh/known_hosts || {
      log "⚠️ 无法获取远程主机指纹"
      send_feishu "警告" "SSH 指纹获取失败，跳过远程同步"
    }
    # Deduplicate known_hosts
    sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts
  fi
  
  # Sync to remote
  if ! rsync -avz --timeout=3600 -e "ssh -i $REMOTE_SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30" \
      "$FINAL_DIR/" "${REMOTE_SERVER}/${TIMESTAMP}/"; then
    log "⚠️ 远程同步失败"
    send_feishu "警告" "远程同步失败，本地备份正常"
  else
    log "  ✓ 远程同步完成"
  fi
fi

# Step 8: Cleanup old backups
log "清理旧备份..."

# Local cleanup
RETENTION_DAYS=${RETENTION_DAYS:-14}
find /backups/full -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} + 2>/dev/null || true
log "  ✓ 本地保留策略: ${RETENTION_DAYS} 天"

# Remote cleanup (if enabled)
if [[ "${REMOTE_BACKUP_ENABLED:-false}" == "true" ]] && [[ -n "${REMOTE_RETENTION_DAYS:-}" ]]; then
  REMOTE_PATH=$(echo "$REMOTE_SERVER" | cut -d: -f2)
  REMOTE_USER_HOST=$(echo "$REMOTE_SERVER" | cut -d: -f1)
  
  ssh -i "$REMOTE_SSH_KEY" "$REMOTE_USER_HOST" \
    "find $REMOTE_PATH -maxdepth 1 -type d -mtime +${REMOTE_RETENTION_DAYS} -exec rm -rf {} +" 2>/dev/null || true
  log "  ✓ 远程保留策略: ${REMOTE_RETENTION_DAYS} 天"
fi

# Step 9: Export metrics
BACKUP_SIZE=$(stat -c%s "$BACKUP_DEST" 2>/dev/null || echo 0)
cat > /backups/metrics.prom <<EOF
# HELP gitlab_backup_size_bytes Size of latest backup in bytes
# TYPE gitlab_backup_size_bytes gauge
gitlab_backup_size_bytes ${BACKUP_SIZE}

# HELP gitlab_backup_timestamp Unix timestamp of latest backup
# TYPE gitlab_backup_timestamp gauge
gitlab_backup_timestamp $(date +%s)

# HELP gitlab_backup_success Success status of latest backup (1=success, 0=failure)
# TYPE gitlab_backup_success gauge
gitlab_backup_success 1
EOF

# Summary
log "========================================="
log "✅ 备份成功完成"
log "备份目录: $FINAL_DIR"
log "备份大小: $(du -sh "$FINAL_DIR" | cut -f1)"
log "========================================="

BACKUP_SIZE_HR=$(du -sh "$FINAL_DIR" | cut -f1)
send_feishu "成功" "备份完成\n目录: ${TIMESTAMP}\n大小: ${BACKUP_SIZE_HR}"

exit 0
