#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

BACKUP_DIR="/backups/full"
LOG_DIR="/logs"

echo "========================================="
echo "   GitLab 备份系统状态检查"
echo "========================================="
echo ""

# System info
echo "📊 系统信息"
echo "  主机: $(hostname)"
echo "  时间: $(date +'%Y-%m-%d %H:%M:%S')"
echo "  用户: $(whoami)"
echo ""

# Disk usage
echo "💾 磁盘使用情况"
DISK_USAGE=$(df -h /backups 2>/dev/null | tail -1)
if [[ -n "$DISK_USAGE" ]]; then
  echo "  备份目录: $DISK_USAGE"
  
  DISK_PERCENT=$(echo "$DISK_USAGE" | awk '{print $5}' | sed 's/%//')
  if [[ $DISK_PERCENT -gt 85 ]]; then
    echo -e "  ${RED}⚠️ 警告: 磁盘使用率超过 85%${NC}"
  elif [[ $DISK_PERCENT -gt 70 ]]; then
    echo -e "  ${YELLOW}⚠️ 注意: 磁盘使用率超过 70%${NC}"
  else
    echo -e "  ${GREEN}✓ 磁盘空间充足${NC}"
  fi
else
  echo "  无法获取磁盘信息"
fi
echo ""

# Backup statistics
echo "📦 备份统计"
if [[ -d "$BACKUP_DIR" ]]; then
  TOTAL_BACKUPS=$(find "$BACKUP_DIR" -maxdepth 1 -type d | tail -n +2 | wc -l)
  TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
  
  echo "  总备份数: $TOTAL_BACKUPS"
  echo "  总大小: $TOTAL_SIZE"
  
  # Latest backup
  LATEST=$(ls -t "$BACKUP_DIR" | head -1)
  if [[ -n "$LATEST" ]]; then
    LATEST_SIZE=$(du -sh "$BACKUP_DIR/$LATEST" 2>/dev/null | cut -f1)
    LATEST_TIME=$(stat -c %y "$BACKUP_DIR/$LATEST" 2>/dev/null | cut -d'.' -f1)
    
    echo ""
    echo "  最新备份:"
    echo "    目录: $LATEST"
    echo "    大小: $LATEST_SIZE"
    echo "    时间: $LATEST_TIME"
    
    # Check backup age
    LATEST_TIMESTAMP=$(stat -c %Y "$BACKUP_DIR/$LATEST" 2>/dev/null)
    NOW=$(date +%s)
    AGE_HOURS=$(( (NOW - LATEST_TIMESTAMP) / 3600 ))
    
    if [[ $AGE_HOURS -gt 48 ]]; then
      echo -e "    ${RED}⚠️ 警告: 备份已超过 48 小时 (${AGE_HOURS}h)${NC}"
    elif [[ $AGE_HOURS -gt 24 ]]; then
      echo -e "    ${YELLOW}⚠️ 注意: 备份已超过 24 小时 (${AGE_HOURS}h)${NC}"
    else
      echo -e "    ${GREEN}✓ 备份较新 (${AGE_HOURS}h)${NC}"
    fi
  fi
else
  echo "  备份目录不存在"
fi
echo ""

# Recent backups list
echo "📋 最近 5 次备份"
if [[ -d "$BACKUP_DIR" ]]; then
  ls -lht "$BACKUP_DIR" | head -6 | tail -5 | while read line; do
    echo "  $line"
  done
else
  echo "  无备份记录"
fi
echo ""

# Latest backup contents
echo "📁 最新备份内容"
if [[ -n "$LATEST" ]] && [[ -d "$BACKUP_DIR/$LATEST" ]]; then
  ls -lh "$BACKUP_DIR/$LATEST" | tail -n +2 | while read line; do
    echo "  $line"
  done
else
  echo "  无内容"
fi
echo ""

# Log files
echo "📄 最近日志文件"
if [[ -d "$LOG_DIR" ]]; then
  ls -lht "$LOG_DIR"/*.log 2>/dev/null | head -5 | while read line; do
    echo "  $line"
  done
  
  echo ""
  echo "📝 最近日志摘要 (最后 10 行)"
  LATEST_LOG=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
  if [[ -n "$LATEST_LOG" ]]; then
    echo "  文件: $(basename $LATEST_LOG)"
    echo "  ----------------------------------------"
    tail -10 "$LATEST_LOG" | sed 's/^/  /'
  else
    echo "  无日志文件"
  fi
else
  echo "  日志目录不存在"
fi
echo ""

# Container status
echo "🐳 Docker 容器状态"
if command -v docker &> /dev/null; then
  # Check if we can access docker
  if docker ps &> /dev/null; then
    # GitLab container
    GITLAB_STATUS=$(docker ps --filter "name=gitlab" --format "{{.Names}}: {{.Status}}" 2>/dev/null)
    if [[ -n "$GITLAB_STATUS" ]]; then
      echo -e "  ${GREEN}✓ $GITLAB_STATUS${NC}"
    else
      echo -e "  ${RED}✗ GitLab 容器未运行${NC}"
    fi
    
    # Backup container (should not be running)
    BACKUP_STATUS=$(docker ps --filter "name=gitlab-backup" --format "{{.Names}}: {{.Status}}" 2>/dev/null)
    if [[ -n "$BACKUP_STATUS" ]]; then
      echo -e "  ${YELLOW}⚠️ $BACKUP_STATUS (备份容器不应长期运行)${NC}"
    else
      echo -e "  ${GREEN}✓ 备份容器未运行 (正常)${NC}"
    fi
  else
    echo "  无法访问 Docker"
  fi
else
  echo "  Docker 未安装"
fi
echo ""

# Metrics
echo "📈 备份指标"
if [[ -f /backups/metrics.prom ]]; then
  cat /backups/metrics.prom | grep -v "^#" | while read line; do
    METRIC=$(echo "$line" | awk '{print $1}')
    VALUE=$(echo "$line" | awk '{print $2}')
    
    case $METRIC in
      gitlab_backup_size_bytes)
        SIZE_MB=$(( VALUE / 1024 / 1024 ))
        echo "  备份大小: ${SIZE_MB} MB"
        ;;
      gitlab_backup_timestamp)
        TIME=$(date -d "@$VALUE" +'%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
        echo "  备份时间: $TIME"
        ;;
      gitlab_backup_success)
        if [[ "$VALUE" == "1" ]]; then
          echo -e "  最后状态: ${GREEN}成功${NC}"
        else
          echo -e "  最后状态: ${RED}失败${NC}"
        fi
        ;;
    esac
  done
else
  echo "  无指标文件"
fi
echo ""

# Configuration check
echo "⚙️  配置检查"
if [[ -f /config/backup.conf ]]; then
  echo -e "  ${GREEN}✓ 配置文件存在${NC}"
  
  # Check key settings
  source /config/backup.conf 2>/dev/null
  
  echo "  GitLab 容器: ${GITLAB_CONTAINER_NAME:-未设置}"
  echo "  保留天数: ${RETENTION_DAYS:-未设置}"
  echo "  飞书通知: ${ENABLE_FEISHU_NOTIFY:-未设置}"
  echo "  远程备份: ${REMOTE_BACKUP_ENABLED:-未设置}"
else
  echo -e "  ${RED}✗ 配置文件不存在${NC}"
fi
echo ""

echo "========================================="
echo "状态检查完成"
echo "========================================="
