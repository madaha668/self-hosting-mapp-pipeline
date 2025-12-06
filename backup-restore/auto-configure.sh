#!/bin/bash
# Auto-configure backup system by inspecting running GitLab container
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "  GitLab Backup - 自动配置"
echo "========================================="
echo ""

# Check if docker-compose.yml exists
if [[ ! -f "docker-compose.yml" ]]; then
    echo -e "${RED}错误: 未找到 docker-compose.yml${NC}"
    exit 1
fi

# Find GitLab container
echo "1. 查找 GitLab 容器..."
GITLAB_CONTAINERS=$(docker ps --format '{{.Names}}' --filter "name=gitlab" 2>/dev/null || echo "")

if [[ -z "$GITLAB_CONTAINERS" ]]; then
    echo -e "${RED}错误: 未找到运行中的 GitLab 容器${NC}"
    echo ""
    echo "所有运行中的容器:"
    docker ps --format "table {{.Names}}\t{{.Image}}"
    echo ""
    read -p "请输入 GitLab 容器名称: " GITLAB_CONTAINER
else
    # Multiple containers found
    CONTAINER_COUNT=$(echo "$GITLAB_CONTAINERS" | wc -l)
    if [[ $CONTAINER_COUNT -gt 1 ]]; then
        echo -e "${YELLOW}找到多个 GitLab 容器:${NC}"
        echo "$GITLAB_CONTAINERS"
        echo ""
        read -p "请选择容器名称: " GITLAB_CONTAINER
    else
        GITLAB_CONTAINER="$GITLAB_CONTAINERS"
        echo -e "${GREEN}✓ 找到容器: $GITLAB_CONTAINER${NC}"
    fi
fi

# Verify container exists
if ! docker ps --format '{{.Names}}' | grep -q "^${GITLAB_CONTAINER}$"; then
    echo -e "${RED}错误: 容器 $GITLAB_CONTAINER 未运行${NC}"
    exit 1
fi

echo ""
echo "2. 检查容器挂载..."

# Function to get mount source for a destination path
get_mount_source() {
    local container="$1"
    local dest_path="$2"
    
    # Try to find exact match first
    local source=$(docker inspect "$container" 2>/dev/null | \
        grep -B3 "\"Destination\": \"$dest_path\"" | \
        grep '"Source"' | head -1 | cut -d'"' -f4)
    
    if [[ -n "$source" ]]; then
        echo "$source"
        return 0
    fi
    
    # Try parent path (e.g., /var/opt/gitlab for /var/opt/gitlab/backups)
    local parent_path=$(dirname "$dest_path")
    source=$(docker inspect "$container" 2>/dev/null | \
        grep -B3 "\"Destination\": \"$parent_path\"" | \
        grep '"Source"' | head -1 | cut -d'"' -f4)
    
    if [[ -n "$source" ]]; then
        # Append the subdirectory
        local subdir=$(basename "$dest_path")
        echo "$source/$subdir"
        return 0
    fi
    
    echo ""
    return 1
}

# Detect mounts
echo ""
echo -e "${BLUE}检测挂载点:${NC}"

# Backup directory
BACKUP_SRC=$(get_mount_source "$GITLAB_CONTAINER" "/var/opt/gitlab/backups")
if [[ -n "$BACKUP_SRC" ]]; then
    echo -e "  ${GREEN}✓${NC} 备份目录: $BACKUP_SRC"
else
    echo -e "  ${YELLOW}⚠${NC} 备份目录未挂载"
    BACKUP_SRC=""
fi

# Config directory
CONFIG_SRC=$(get_mount_source "$GITLAB_CONTAINER" "/etc/gitlab")
if [[ -n "$CONFIG_SRC" ]]; then
    echo -e "  ${GREEN}✓${NC} 配置目录: $CONFIG_SRC"
else
    echo -e "  ${YELLOW}⚠${NC} 配置目录未挂载"
    CONFIG_SRC=""
fi

# Data directory (optional, for information)
DATA_SRC=$(get_mount_source "$GITLAB_CONTAINER" "/var/opt/gitlab")
if [[ -n "$DATA_SRC" ]]; then
    echo -e "  ${GREEN}✓${NC} 数据目录: $DATA_SRC"
else
    echo -e "  ${YELLOW}ℹ${NC} 数据目录未单独挂载"
    DATA_SRC=""
fi

# SSL directory (optional)
SSL_SRC=$(get_mount_source "$GITLAB_CONTAINER" "/etc/gitlab/ssl")
if [[ -n "$SSL_SRC" ]]; then
    echo -e "  ${GREEN}✓${NC} SSL 目录: $SSL_SRC"
else
    SSL_SRC=""
fi

echo ""

# Validate critical mounts
if [[ -z "$BACKUP_SRC" ]]; then
    echo -e "${YELLOW}警告: 备份目录未挂载${NC}"
    echo "备份将在容器内执行，但备份文件可能无法从宿主机访问"
    echo ""
    read -p "继续配置? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Generate docker-compose.yml volumes section
echo "3. 生成配置..."
echo ""

# Backup current docker-compose.yml
cp docker-compose.yml docker-compose.yml.backup
echo -e "${GREEN}✓${NC} 已备份原配置: docker-compose.yml.backup"

# Determine volume type and format
format_volume_mount() {
    local source="$1"
    local destination="$2"
    local readonly="${3:-:ro}"
    
    # Check if it's a directory or volume name
    if [[ "$source" =~ ^/ ]] && [[ -d "$source" ]]; then
        # Directory bind mount
        echo "      - $source:$destination$readonly"
    else
        # Named volume
        echo "      - $source:$destination$readonly"
    fi
}

# Build volumes section
VOLUMES_CONFIG=""

if [[ -n "$BACKUP_SRC" ]]; then
    VOLUMES_CONFIG+="$(format_volume_mount "$BACKUP_SRC" "/gitlab/backups" ":ro")"$'\n'
fi

if [[ -n "$CONFIG_SRC" ]]; then
    VOLUMES_CONFIG+="$(format_volume_mount "$CONFIG_SRC" "/gitlab/config" ":ro")"$'\n'
fi

if [[ -n "$SSL_SRC" ]] && [[ "$SSL_SRC" != "$CONFIG_SRC/ssl" ]]; then
    VOLUMES_CONFIG+="$(format_volume_mount "$SSL_SRC" "/gitlab/ssl" ":ro")"$'\n'
fi

# Add standard backup container volumes
VOLUMES_CONFIG+="      - ./backups:/backups"$'\n'
VOLUMES_CONFIG+="      - ./config:/config"$'\n'
VOLUMES_CONFIG+="      - ./logs:/logs"$'\n'
VOLUMES_CONFIG+="      - ~/.ssh:/root/.ssh:ro"

echo -e "${BLUE}生成的卷配置:${NC}"
echo "$VOLUMES_CONFIG"
echo ""

# Update docker-compose.yml
echo "4. 更新 docker-compose.yml..."

# Create temporary file with updated configuration
cat > docker-compose.yml.tmp << 'EOF'
version: '3.8'

services:
  # Backup service - run on-demand or via cron
  gitlab-backup:
    build: .
    container_name: gitlab-backup
    volumes:
      # Docker control (required)
      - /var/run/docker.sock:/var/run/docker.sock
      
      # GitLab directories (auto-detected from container)
EOF

# Add detected volumes
echo "$VOLUMES_CONFIG" >> docker-compose.yml.tmp

# Add rest of configuration
cat >> docker-compose.yml.tmp << 'EOF'
    environment:
      - TZ=Asia/Shanghai
    command: ["/app/scripts/backup.sh"]
    restart: "no"
    networks:
      - gitlab-backup-net

  # Restore service - run on-demand only
  gitlab-restore:
    build: .
    container_name: gitlab-restore
    volumes:
      # Docker control (required)
      - /var/run/docker.sock:/var/run/docker.sock
      
      # Backup system directories
      - ./backups:/backups
      - ./config:/config
      - ./logs:/logs
    environment:
      - TZ=Asia/Shanghai
    entrypoint: ["/app/scripts/restore.sh"]
    restart: "no"
    networks:
      - gitlab-backup-net

networks:
  gitlab-backup-net:
    driver: bridge
EOF

# Check if we need to add external volumes
EXTERNAL_VOLUMES=""
if [[ -n "$BACKUP_SRC" ]] && [[ ! "$BACKUP_SRC" =~ ^/ ]]; then
    EXTERNAL_VOLUMES+="  $BACKUP_SRC:"$'\n'
    EXTERNAL_VOLUMES+="    external: true"$'\n'
fi

if [[ -n "$CONFIG_SRC" ]] && [[ ! "$CONFIG_SRC" =~ ^/ ]]; then
    if [[ -n "$EXTERNAL_VOLUMES" ]]; then
        EXTERNAL_VOLUMES+=$'\n'
    fi
    EXTERNAL_VOLUMES+="  $CONFIG_SRC:"$'\n'
    EXTERNAL_VOLUMES+="    external: true"$'\n'
fi

if [[ -n "$EXTERNAL_VOLUMES" ]]; then
    echo "" >> docker-compose.yml.tmp
    echo "# External volumes from GitLab container" >> docker-compose.yml.tmp
    echo "volumes:" >> docker-compose.yml.tmp
    echo "$EXTERNAL_VOLUMES" >> docker-compose.yml.tmp
fi

# Replace original file
mv docker-compose.yml.tmp docker-compose.yml
echo -e "${GREEN}✓${NC} docker-compose.yml 已更新"
echo ""

# Update config file
echo "5. 更新配置文件..."

if [[ -f "config/backup.conf" ]]; then
    # Update existing config
    sed -i.bak "s/^GITLAB_CONTAINER_NAME=.*/GITLAB_CONTAINER_NAME=$GITLAB_CONTAINER/" config/backup.conf
    echo -e "${GREEN}✓${NC} config/backup.conf 已更新"
    echo "  容器名称: $GITLAB_CONTAINER"
else
    # Create new config
    cp config/backup.conf.example config/backup.conf
    sed -i "s/^GITLAB_CONTAINER_NAME=.*/GITLAB_CONTAINER_NAME=$GITLAB_CONTAINER/" config/backup.conf
    echo -e "${GREEN}✓${NC} config/backup.conf 已创建"
    echo "  容器名称: $GITLAB_CONTAINER"
fi

echo ""
echo "========================================="
echo -e "${GREEN}✓ 自动配置完成！${NC}"
echo "========================================="
echo ""

# Summary
echo "配置摘要:"
echo "  GitLab 容器: $GITLAB_CONTAINER"
[[ -n "$BACKUP_SRC" ]] && echo "  备份目录: $BACKUP_SRC"
[[ -n "$CONFIG_SRC" ]] && echo "  配置目录: $CONFIG_SRC"
[[ -n "$DATA_SRC" ]] && echo "  数据目录: $DATA_SRC"
echo ""

echo "备份文件:"
echo "  docker-compose.yml.backup - 原始配置"
echo "  config/backup.conf.bak - 原始配置 (如果存在)"
echo ""

echo "下一步:"
echo "  1. 查看配置: cat docker-compose.yml"
echo "  2. 编辑配置: vim config/backup.conf"
echo "  3. 验证配置: ./preflight-check.sh"
echo "  4. 测试备份: ./test-backup.sh --dry-run"
echo "  5. 执行备份: docker compose run --rm gitlab-backup"
echo ""
