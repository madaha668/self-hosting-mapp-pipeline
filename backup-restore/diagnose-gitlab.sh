#!/bin/bash
# GitLab Container Diagnostics
# 帮助用户了解 GitLab 容器的挂载配置

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "  GitLab 容器诊断工具"
echo "========================================="
echo ""

# Find GitLab containers
echo "1. 查找 GitLab 容器"
echo "-------------------"
GITLAB_CONTAINERS=$(docker ps --format '{{.Names}}' --filter "name=gitlab" 2>/dev/null || echo "")

if [[ -z "$GITLAB_CONTAINERS" ]]; then
    echo -e "${YELLOW}未找到运行中的 GitLab 容器${NC}"
    echo ""
    echo "所有运行中的容器:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    exit 0
fi

echo -e "${GREEN}找到以下 GitLab 容器:${NC}"
echo "$GITLAB_CONTAINERS"
echo ""

# Analyze each container
for CONTAINER in $GITLAB_CONTAINERS; do
    echo "========================================="
    echo "容器: $CONTAINER"
    echo "========================================="
    echo ""
    
    # Basic info
    echo "基本信息:"
    echo "  镜像: $(docker inspect --format='{{.Config.Image}}' "$CONTAINER")"
    echo "  状态: $(docker inspect --format='{{.State.Status}}' "$CONTAINER")"
    echo "  运行时间: $(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER" | cut -d'.' -f1)"
    echo ""
    
    # Volume mounts
    echo "卷挂载分析:"
    echo "-------------------"
    
    # Backup directory
    echo -e "${BLUE}1. 备份目录 (/var/opt/gitlab/backups):${NC}"
    BACKUP_MOUNT=$(docker inspect "$CONTAINER" 2>/dev/null | grep -B3 '"/var/opt/gitlab/backups"' | grep '"Source"' | cut -d'"' -f4 | head -1)
    
    if [[ -n "$BACKUP_MOUNT" ]]; then
        echo "  ✓ 挂载点: $BACKUP_MOUNT"
        if [[ -d "$BACKUP_MOUNT" ]]; then
            echo "  ✓ 类型: 目录绑定挂载"
            echo "  ✓ 大小: $(du -sh "$BACKUP_MOUNT" 2>/dev/null | cut -f1)"
            echo "  ✓ 文件数: $(find "$BACKUP_MOUNT" -type f 2>/dev/null | wc -l)"
            echo ""
            echo "  用于 docker-compose.yml:"
            echo "    - $BACKUP_MOUNT:/gitlab/backups:ro"
        else
            echo "  ✓ 类型: Docker 命名卷"
            echo "  ✓ 卷名: $BACKUP_MOUNT"
            echo ""
            echo "  用于 docker-compose.yml:"
            echo "    volumes:"
            echo "      - $BACKUP_MOUNT:/gitlab/backups:ro"
        fi
    else
        echo "  ⚠ 未挂载（备份可能在容器内部）"
        echo "  建议: 添加卷挂载以便访问备份文件"
    fi
    echo ""
    
    # Config directory
    echo -e "${BLUE}2. 配置目录 (/etc/gitlab):${NC}"
    CONFIG_MOUNT=$(docker inspect "$CONTAINER" 2>/dev/null | grep -B3 '"/etc/gitlab"' | grep '"Source"' | cut -d'"' -f4 | head -1)
    
    if [[ -n "$CONFIG_MOUNT" ]]; then
        echo "  ✓ 挂载点: $CONFIG_MOUNT"
        if [[ -d "$CONFIG_MOUNT" ]]; then
            echo "  ✓ 类型: 目录绑定挂载"
            echo "  ✓ 主要文件:"
            [[ -f "$CONFIG_MOUNT/gitlab.rb" ]] && echo "    - gitlab.rb ($(stat -c%s "$CONFIG_MOUNT/gitlab.rb" 2>/dev/null | numfmt --to=iec 2>/dev/null || stat -c%s "$CONFIG_MOUNT/gitlab.rb" 2>/dev/null || echo "?") bytes)"
            [[ -f "$CONFIG_MOUNT/gitlab-secrets.json" ]] && echo "    - gitlab-secrets.json"
            echo ""
            echo "  用于 docker-compose.yml:"
            echo "    - $CONFIG_MOUNT:/gitlab/config:ro"
        else
            echo "  ✓ 类型: Docker 命名卷"
            echo "  ✓ 卷名: $CONFIG_MOUNT"
            echo ""
            echo "  用于 docker-compose.yml:"
            echo "    volumes:"
            echo "      - $CONFIG_MOUNT:/gitlab/config:ro"
        fi
    else
        echo "  ⚠ 未挂载（配置可能在容器内部）"
    fi
    echo ""
    
    # Data directory
    echo -e "${BLUE}3. 数据目录 (/var/opt/gitlab):${NC}"
    DATA_MOUNT=$(docker inspect "$CONTAINER" 2>/dev/null | grep -B3 '"/var/opt/gitlab"' | grep '"Source"' | cut -d'"' -f4 | head -1)
    
    if [[ -n "$DATA_MOUNT" ]]; then
        echo "  ✓ 挂载点: $DATA_MOUNT"
        if [[ -d "$DATA_MOUNT" ]]; then
            echo "  ✓ 类型: 目录绑定挂载"
            echo "  ✓ 大小: $(du -sh "$DATA_MOUNT" 2>/dev/null | cut -f1)"
        else
            echo "  ✓ 类型: Docker 命名卷"
            echo "  ✓ 卷名: $DATA_MOUNT"
        fi
    else
        echo "  ℹ 未单独挂载（可能使用子目录挂载）"
    fi
    echo ""
    
    # All mounts summary
    echo "所有挂载点汇总:"
    echo "-------------------"
    docker inspect "$CONTAINER" 2>/dev/null | grep -A 2 '"Type":' | grep -E '"Type"|"Source"|"Destination"' | sed 'N;N;s/\n/ /g' | sed 's/.*"Type": "\([^"]*\)".*"Source": "\([^"]*\)".*"Destination": "\([^"]*\)".*/  \1: \2 -> \3/' || echo "  无法解析挂载信息"
    echo ""
    
    # Recommended docker-compose.yml
    echo "推荐的 docker-compose.yml 配置:"
    echo "-------------------"
    echo "volumes:"
    if [[ -n "$BACKUP_MOUNT" ]]; then
        echo "  - $BACKUP_MOUNT:/gitlab/backups:ro"
    else
        echo "  # 备份目录未挂载，需要手动配置"
        echo "  # - /path/to/backups:/gitlab/backups:ro"
    fi
    
    if [[ -n "$CONFIG_MOUNT" ]]; then
        echo "  - $CONFIG_MOUNT:/gitlab/config:ro"
    else
        echo "  # 配置目录未挂载，需要手动配置"
        echo "  # - /path/to/config:/gitlab/config:ro"
    fi
    echo ""
    
    # Test backup command
    echo "测试备份命令:"
    echo "-------------------"
    echo "# 测试 GitLab 容器是否可以执行备份"
    echo "docker exec $CONTAINER gitlab-backup --help"
    echo ""
    
    # Check backup files
    if [[ -n "$BACKUP_MOUNT" ]] && [[ -d "$BACKUP_MOUNT" ]]; then
        echo "现有备份文件:"
        echo "-------------------"
        BACKUP_FILES=$(find "$BACKUP_MOUNT" -name "*.tar" 2>/dev/null | wc -l)
        if [[ $BACKUP_FILES -gt 0 ]]; then
            echo "  找到 $BACKUP_FILES 个备份文件:"
            find "$BACKUP_MOUNT" -name "*.tar" -exec ls -lh {} \; 2>/dev/null | tail -5
        else
            echo "  暂无备份文件"
        fi
        echo ""
    fi
done

echo "========================================="
echo "诊断完成"
echo "========================================="
echo ""
echo "下一步:"
echo "  1. 根据上述信息更新 docker-compose.yml 中的挂载路径"
echo "  2. 运行: ./preflight-check.sh"
echo "  3. 测试: ./test-backup.sh --dry-run"
echo ""
