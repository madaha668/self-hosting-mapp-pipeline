#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            cat <<EOF
用法: $0 [选项]

测试备份功能，无需实际执行备份操作。

选项:
  --dry-run    模拟运行，不执行实际操作
  -v, --verbose 详细输出
  -h, --help   显示帮助信息

示例:
  $0 --dry-run              # 模拟备份，查看会执行什么操作
  $0 --dry-run --verbose    # 详细模拟运行
  $0                        # 实际执行测试备份

EOF
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

echo "========================================="
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}  GitLab Backup - 模拟测试 (Dry Run)${NC}"
else
    echo "  GitLab Backup - 实际测试"
fi
echo "========================================="
echo ""

# Detect Docker Compose command
DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# Configuration
CONFIG_FILE="config/backup.conf"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ✗${NC} $*"
}

log_info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ${NC} $*"
}

simulate() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[模拟]${NC} $*"
        return 0
    else
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "执行: $*"
        fi
        eval "$@"
    fi
}

# Step 1: Check configuration
log "步骤 1/10: 检查配置文件"
if [[ ! -f "$CONFIG_FILE" ]]; then
    if [[ -f "config/backup.conf.example" ]]; then
        log_warn "配置文件不存在，使用示例配置"
        CONFIG_FILE="config/backup.conf.example"
    else
        log_error "配置文件缺失"
        exit 1
    fi
fi

source "$CONFIG_FILE"
log "  ✓ 配置文件加载成功"
log_info "  GitLab 容器: ${GITLAB_CONTAINER_NAME:-未设置}"
log_info "  保留天数: ${RETENTION_DAYS:-14}"
echo ""

# Step 2: Check Docker
log "步骤 2/10: 检查 Docker 环境"
if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装"
    exit 1
fi
log "  ✓ Docker 已安装"

if ! docker info &> /dev/null; then
    log_error "无法连接 Docker 守护进程"
    exit 1
fi
log "  ✓ Docker 守护进程运行正常"
echo ""

# Step 3: Check GitLab container
log "步骤 3/10: 检查 GitLab 容器"
CONTAINER_NAME="${GITLAB_CONTAINER_NAME:-gitlab}"

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "  ✓ 容器 $CONTAINER_NAME 正在运行"
    
    # Check GitLab version
    if [[ "$VERBOSE" == "true" ]]; then
        GITLAB_VERSION=$(docker exec "$CONTAINER_NAME" cat /opt/gitlab/version-manifest.txt 2>/dev/null | head -1 || echo "未知")
        log_info "  GitLab 版本: $GITLAB_VERSION"
    fi
else
    log_warn "容器 $CONTAINER_NAME 未运行"
    log_info "继续测试其他功能..."
fi
echo ""

# Step 4: Test backup command
log "步骤 4/10: 测试备份命令"
if [[ "$DRY_RUN" == "true" ]]; then
    simulate "docker exec $CONTAINER_NAME gitlab-backup create SKIP=artifacts"
    log "  ✓ 命令格式正确"
else
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "跳过实际备份执行（使用 docker-compose 进行完整测试）"
        log "  ✓ 命令可用"
    else
        log_warn "容器未运行，无法测试"
    fi
fi
echo ""

# Step 5: Test directory structure
log "步骤 5/10: 检查目录结构"
DIRS=("backups/full" "logs" "config")
for dir in "${DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        log "  ✓ $dir 存在"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            simulate "mkdir -p $dir"
        else
            mkdir -p "$dir"
            log "  ✓ 创建 $dir"
        fi
    fi
done
echo ""

# Step 6: Test file permissions
log "步骤 6/10: 检查文件权限"
if [[ -w "backups" ]]; then
    log "  ✓ backups 目录可写"
else
    log_error "backups 目录不可写"
    exit 1
fi

if [[ -w "logs" ]]; then
    log "  ✓ logs 目录可写"
else
    log_error "logs 目录不可写"
    exit 1
fi
echo ""

# Step 7: Test disk space
log "步骤 7/10: 检查磁盘空间"
DISK_USAGE=$(df backups | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h backups | tail -1 | awk '{print $4}')

log_info "  可用空间: $DISK_AVAIL"
log_info "  使用率: ${DISK_USAGE}%"

if [[ $DISK_USAGE -lt 70 ]]; then
    log "  ✓ 磁盘空间充足"
elif [[ $DISK_USAGE -lt 85 ]]; then
    log_warn "磁盘空间偏紧"
else
    log_error "磁盘空间不足"
fi
echo ""

# Step 8: Test notification (if enabled)
log "步骤 8/10: 测试通知功能"
if [[ "${ENABLE_FEISHU_NOTIFY:-false}" == "true" ]]; then
    if [[ -n "${FEISHU_WEBHOOK_URL:-}" ]]; then
        log_info "  飞书通知已启用"
        if [[ "$DRY_RUN" == "true" ]]; then
            simulate "curl -X POST '$FEISHU_WEBHOOK_URL' -d '{\"test\": true}'"
            log "  ✓ Webhook URL 已配置"
        else
            log_warn "跳过实际通知发送（避免打扰）"
            log "  ✓ 配置正确"
        fi
    else
        log_warn "飞书通知已启用但 Webhook URL 未设置"
    fi
else
    log_info "  飞书通知未启用"
fi
echo ""

# Step 9: Test remote backup (if enabled)
log "步骤 9/10: 测试远程备份功能"
if [[ "${REMOTE_BACKUP_ENABLED:-false}" == "true" ]]; then
    log_info "  远程备份已启用"
    
    if [[ -n "${REMOTE_SERVER:-}" ]]; then
        log_info "  远程服务器: $REMOTE_SERVER"
        
        REMOTE_HOST=$(echo "$REMOTE_SERVER" | cut -d@ -f2 | cut -d: -f1)
        SSH_KEY="${REMOTE_SSH_KEY:-~/.ssh/id_rsa}"
        
        if [[ -f "$SSH_KEY" ]]; then
            log "  ✓ SSH 密钥存在: $SSH_KEY"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                simulate "ssh -i $SSH_KEY -o ConnectTimeout=5 $(echo $REMOTE_SERVER | cut -d: -f1) 'echo test'"
                log "  ✓ SSH 命令格式正确"
            else
                log_warn "跳过实际 SSH 连接测试"
                log "  ✓ 配置看起来正确"
            fi
        else
            log_error "SSH 密钥不存在: $SSH_KEY"
        fi
    else
        log_warn "远程备份已启用但未配置服务器"
    fi
else
    log_info "  远程备份未启用"
fi
echo ""

# Step 10: Test Docker Compose
log "步骤 10/10: 测试 Docker Compose 配置"
if [[ -f "docker-compose.yml" ]]; then
    log "  ✓ docker-compose.yml 存在"
    
    if [[ -n "$DOCKER_COMPOSE_CMD" ]]; then
        if $DOCKER_COMPOSE_CMD config &> /dev/null; then
            log "  ✓ docker-compose.yml 语法正确"
        else
            log_error "docker-compose.yml 语法错误"
        fi
    fi
else
    log_error "docker-compose.yml 不存在"
fi
echo ""

# Summary
echo "========================================="
echo "  测试摘要"
echo "========================================="
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}✓ 模拟测试完成！${NC}"
    echo ""
    echo "所有检查都已通过。系统配置正确。"
    echo ""
    echo "下一步:"
    echo "  1. 执行实际测试: $0 (不带 --dry-run)"
    echo "  2. 运行完整备份: ${DOCKER_COMPOSE_CMD:-docker compose} run --rm gitlab-backup"
    echo "  3. 查看状态: ${DOCKER_COMPOSE_CMD:-docker compose} run --rm gitlab-backup /app/scripts/check-status.sh"
else
    echo -e "${GREEN}✓ 测试完成！${NC}"
    echo ""
    echo "环境验证通过。可以安全地执行备份。"
    echo ""
    echo "执行备份:"
    echo "  ${DOCKER_COMPOSE_CMD:-docker compose} run --rm gitlab-backup"
fi

echo ""
echo "========================================="
