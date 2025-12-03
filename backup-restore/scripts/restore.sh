#!/bin/bash
set -euo pipefail

# Configuration
CONFIG_FILE="/config/backup.conf"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/logs/restore-${TIMESTAMP}.log"

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "❌ 配置文件 /config/backup.conf 未找到" >&2
  exit 1
fi

source "$CONFIG_FILE"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Usage check
if [[ $# -ne 1 ]]; then
  cat <<EOF
用法: $0 <backup-directory>

示例:
  $0 /backups/full/20241203_020000

可用备份:
EOF
  ls -lht /backups/full/ | head -6
  exit 1
fi

BACKUP_DIR="$1"

# Validate backup directory
if [[ ! -d "$BACKUP_DIR" ]]; then
  log "❌ 备份目录不存在: $BACKUP_DIR"
  exit 1
fi

# Interactive confirmation
log "========================================="
log "GitLab 恢复操作"
log "========================================="
log "备份目录: $BACKUP_DIR"
log "目标容器: $GITLAB_CONTAINER_NAME"
log "当前时间: $(date +'%Y-%m-%d %H:%M:%S')"
log ""
log "⚠️  警告: 此操作将覆盖当前 GitLab 数据！"
log ""

if [[ -t 0 ]]; then
  read -p "确认继续? (yes/no): " -r
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log "操作已取消"
    exit 0
  fi
else
  log "非交互模式，跳过确认"
fi

# Start restore
log "========================================="
log "开始恢复 GitLab"
log "========================================="

# Step 1: Verify backup files
log "步骤 1/8: 验证备份文件..."

BACKUP_TAR=$(ls "$BACKUP_DIR"/gitlab_data_*.tar 2>/dev/null | head -1)
if [[ -z "$BACKUP_TAR" ]]; then
  log "❌ 未找到数据备份文件"
  exit 1
fi

# Verify checksum if available
if [[ -f "$BACKUP_DIR/checksums.txt" ]]; then
  log "  验证校验和..."
  cd "$BACKUP_DIR"
  if sha256sum -c checksums.txt 2>&1 | tee -a "$LOG_FILE"; then
    log "  ✓ 校验和验证通过"
  else
    log "  ⚠️ 校验和验证失败，继续恢复但数据可能已损坏"
  fi
  cd - >/dev/null
fi

log "  ✓ 备份文件: $(basename $BACKUP_TAR)"

# Step 2: Check GitLab container status
log "步骤 2/8: 检查 GitLab 容器状态..."

if ! docker ps --format '{{.Names}}' | grep -q "^${GITLAB_CONTAINER_NAME}$"; then
  log "❌ GitLab 容器 $GITLAB_CONTAINER_NAME 未运行"
  exit 1
fi
log "  ✓ GitLab 容器运行中"

# Step 3: Stop GitLab services
log "步骤 3/8: 停止 GitLab 服务..."

if ! docker exec "$GITLAB_CONTAINER_NAME" gitlab-ctl stop puma 2>&1 | tee -a "$LOG_FILE"; then
  log "⚠️ 停止 puma 失败，尝试继续"
fi

if ! docker exec "$GITLAB_CONTAINER_NAME" gitlab-ctl stop sidekiq 2>&1 | tee -a "$LOG_FILE"; then
  log "⚠️ 停止 sidekiq 失败，尝试继续"
fi

sleep 5
log "  ✓ GitLab 核心服务已停止"

# Step 4: Copy backup file to container
log "步骤 4/8: 复制备份文件到容器..."

BACKUP_FILENAME=$(basename "$BACKUP_TAR")
if ! docker cp "$BACKUP_TAR" "$GITLAB_CONTAINER_NAME:/var/opt/gitlab/backups/"; then
  log "❌ 复制备份文件失败"
  docker exec "$GITLAB_CONTAINER_NAME" gitlab-ctl start
  exit 1
fi
log "  ✓ 备份文件已复制"

# Step 5: Restore configuration files
log "步骤 5/8: 恢复配置文件..."

if [[ -f "$BACKUP_DIR/gitlab-secrets.json" ]]; then
  if docker cp "$BACKUP_DIR/gitlab-secrets.json" "$GITLAB_CONTAINER_NAME:/etc/gitlab/"; then
    log "  ✓ gitlab-secrets.json 已恢复"
  else
    log "  ⚠️ gitlab-secrets.json 恢复失败"
  fi
else
  log "  ℹ gitlab-secrets.json 不存在，跳过"
fi

if [[ -f "$BACKUP_DIR/gitlab.rb" ]]; then
  log "  ℹ 发现 gitlab.rb，但不自动恢复（需手动检查）"
fi

# Step 6: Restore SSL certificates (if exists)
if [[ -f "$BACKUP_DIR/certs.tar.gz" ]]; then
  log "步骤 6/8: 恢复 SSL 证书..."
  if docker exec "$GITLAB_CONTAINER_NAME" mkdir -p /etc/gitlab/ssl; then
    if docker cp "$BACKUP_DIR/certs.tar.gz" "$GITLAB_CONTAINER_NAME:/tmp/"; then
      docker exec "$GITLAB_CONTAINER_NAME" tar -xzf /tmp/certs.tar.gz -C /etc/gitlab/ssl/
      log "  ✓ SSL 证书已恢复"
    fi
  fi
fi

# Step 7: Execute GitLab restore
log "步骤 7/8: 执行 GitLab 数据恢复..."

# Extract backup name (remove timestamp and extension)
BACKUP_NAME="${BACKUP_FILENAME%.tar}"
BACKUP_NAME="${BACKUP_NAME#gitlab_data_}"
BACKUP_NAME="${BACKUP_NAME%_gitlab_backup}"

# If backup name still has timestamp, extract the original GitLab backup ID
ORIGINAL_BACKUP=$(docker exec "$GITLAB_CONTAINER_NAME" ls /var/opt/gitlab/backups/*.tar | head -1)
if [[ -n "$ORIGINAL_BACKUP" ]]; then
  BACKUP_NAME=$(basename "$ORIGINAL_BACKUP" .tar)
  BACKUP_NAME="${BACKUP_NAME%_gitlab_backup}"
fi

log "  使用备份 ID: $BACKUP_NAME"

if ! docker exec "$GITLAB_CONTAINER_NAME" gitlab-backup restore BACKUP="$BACKUP_NAME" force=yes 2>&1 | tee -a "$LOG_FILE"; then
  log "❌ GitLab 恢复失败"
  log "尝试重启 GitLab..."
  docker exec "$GITLAB_CONTAINER_NAME" gitlab-ctl restart
  exit 1
fi

log "  ✓ 数据恢复完成"

# Step 8: Restart GitLab
log "步骤 8/8: 重启 GitLab..."

if ! docker exec "$GITLAB_CONTAINER_NAME" gitlab-ctl restart 2>&1 | tee -a "$LOG_FILE"; then
  log "❌ GitLab 重启失败"
  exit 1
fi

log "  ✓ GitLab 已重启"

# Step 9: Wait for GitLab to be ready
log "等待 GitLab 服务启动..."
sleep 30

# Step 10: Health check
log "执行健康检查..."

if docker exec "$GITLAB_CONTAINER_NAME" gitlab-rake gitlab:check SANITIZE=true 2>&1 | tee -a "$LOG_FILE"; then
  log "========================================="
  log "✅ 恢复成功完成"
  log "========================================="
  log "备份源: $BACKUP_DIR"
  log "完成时间: $(date +'%Y-%m-%d %H:%M:%S')"
  log ""
  log "建议操作:"
  log "1. 验证 GitLab 网页界面是否正常"
  log "2. 测试登录功能"
  log "3. 检查项目和数据完整性"
  log "========================================="
  exit 0
else
  log "========================================="
  log "⚠️ 恢复完成但健康检查失败"
  log "========================================="
  log "请手动检查以下内容:"
  log "1. 访问 GitLab 网页界面"
  log "2. 查看容器日志: docker logs $GITLAB_CONTAINER_NAME"
  log "3. 检查服务状态: docker exec $GITLAB_CONTAINER_NAME gitlab-ctl status"
  log "========================================="
  exit 1
fi
