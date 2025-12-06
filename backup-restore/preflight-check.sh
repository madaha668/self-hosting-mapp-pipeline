#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "  GitLab Backup - 预检测脚本"
echo "  Pre-flight Validation"
echo "========================================="
echo ""

ERRORS=0
WARNINGS=0

# Helper functions
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

check_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# 1. Check Docker
echo "1. 检查 Docker 环境"
echo "-------------------"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    check_pass "Docker 已安装 (版本: $DOCKER_VERSION)"
    
    # Check Docker daemon
    if docker info &> /dev/null; then
        check_pass "Docker 守护进程运行正常"
    else
        check_fail "Docker 守护进程未运行或无权限访问"
        check_info "尝试: sudo usermod -aG docker $USER"
    fi
else
    check_fail "Docker 未安装"
    check_info "安装: https://docs.docker.com/get-docker/"
fi
echo ""

# 2. Check Docker Compose
echo "2. 检查 Docker Compose"
echo "-------------------"
DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null 2>&1; then
    DC_VERSION=$(docker compose version --short 2>/dev/null || docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)
    check_pass "docker compose (plugin) 已安装 (版本: $DC_VERSION)"
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DC_VERSION=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    check_pass "docker-compose (standalone) 已安装 (版本: $DC_VERSION)"
    check_info "建议升级到 Docker Compose V2 (plugin)"
    DOCKER_COMPOSE_CMD="docker-compose"
else
    check_fail "Docker Compose 未安装"
    check_info "安装: https://docs.docker.com/compose/install/"
fi
echo ""

# 3. Check for GitLab container
echo "3. 检查 GitLab 容器"
echo "-------------------"
if docker ps --format '{{.Names}}' | grep -q gitlab; then
    GITLAB_CONTAINERS=$(docker ps --format '{{.Names}}' | grep gitlab)
    check_pass "发现 GitLab 容器:"
    echo "$GITLAB_CONTAINERS" | while read container; do
        STATUS=$(docker inspect --format='{{.State.Status}}' "$container")
        UPTIME=$(docker inspect --format='{{.State.StartedAt}}' "$container" | cut -d'T' -f1)
        echo "    - $container (状态: $STATUS, 启动: $UPTIME)"
    done
else
    check_warn "未发现运行中的 GitLab 容器"
    check_info "如果还未安装 GitLab，可以使用测试模式"
fi
echo ""

# 4. Check GitLab data directories
echo "4. 检查 GitLab 数据目录"
echo "-------------------"

# Try to detect from running container first
if docker ps --format '{{.Names}}' | grep -q gitlab; then
    GITLAB_CONTAINER=$(docker ps --format '{{.Names}}' | grep gitlab | head -1)
    check_info "从容器 $GITLAB_CONTAINER 检测挂载点..."
    
    # Get volume mounts from container
    BACKUP_MOUNT=$(docker inspect "$GITLAB_CONTAINER" 2>/dev/null | grep -B3 '"/var/opt/gitlab/backups"' | grep '"Source"' | cut -d'"' -f4 | head -1)
    CONFIG_MOUNT=$(docker inspect "$GITLAB_CONTAINER" 2>/dev/null | grep -B3 '"/etc/gitlab"' | grep '"Source"' | cut -d'"' -f4 | head -1)
    
    FOUND_PATHS=()
    
    if [[ -n "$BACKUP_MOUNT" ]]; then
        if [[ -d "$BACKUP_MOUNT" ]]; then
            SIZE=$(du -sh "$BACKUP_MOUNT" 2>/dev/null | cut -f1 || echo "N/A")
            check_pass "备份目录: $BACKUP_MOUNT (大小: $SIZE)"
            FOUND_PATHS+=("$BACKUP_MOUNT")
        else
            check_info "备份挂载点: $BACKUP_MOUNT (可能是命名卷)"
            FOUND_PATHS+=("$BACKUP_MOUNT")
        fi
    fi
    
    if [[ -n "$CONFIG_MOUNT" ]]; then
        if [[ -d "$CONFIG_MOUNT" ]]; then
            check_pass "配置目录: $CONFIG_MOUNT"
            FOUND_PATHS+=("$CONFIG_MOUNT")
        else
            check_info "配置挂载点: $CONFIG_MOUNT (可能是命名卷)"
            FOUND_PATHS+=("$CONFIG_MOUNT")
        fi
    fi
    
    if [[ ${#FOUND_PATHS[@]} -eq 0 ]]; then
        check_warn "未检测到挂载点，可能使用 Docker 命名卷"
        check_info "查看卷: docker inspect $GITLAB_CONTAINER | grep -A5 Mounts"
        check_info "这不影响备份功能，因为备份通过容器 exec 执行"
    fi
else
    # Fallback to checking common paths
    check_info "未检测到 GitLab 容器，检查常见路径..."
    
    COMMON_PATHS=(
        "/srv/gitlab/backups"
        "/srv/gitlab/config"
        "/srv/gitlab/data"
        "/var/opt/gitlab/backups"
        "/etc/gitlab"
    )
    
    FOUND_PATHS=()
    for path in "${COMMON_PATHS[@]}"; do
        if [[ -d "$path" ]]; then
            SIZE=$(du -sh "$path" 2>/dev/null | cut -f1)
            check_pass "找到目录: $path (大小: $SIZE)"
            FOUND_PATHS+=("$path")
        fi
    done
    
    if [[ ${#FOUND_PATHS[@]} -eq 0 ]]; then
        check_info "未找到标准路径的 GitLab 目录"
        check_info "如果使用容器化 GitLab，这是正常的"
        check_info "备份将通过容器内部执行，无需宿主机访问"
    fi
fi
echo ""

# 5. Check disk space
echo "5. 检查磁盘空间"
echo "-------------------"
BACKUP_DIR="./backups"
if [[ -d "$BACKUP_DIR" ]]; then
    DISK_INFO=$(df -h "$BACKUP_DIR" | tail -1)
else
    DISK_INFO=$(df -h . | tail -1)
fi

DISK_AVAIL=$(echo "$DISK_INFO" | awk '{print $4}')
DISK_USAGE=$(echo "$DISK_INFO" | awk '{print $5}' | sed 's/%//')

echo "  当前磁盘: $DISK_INFO"
if [[ $DISK_USAGE -lt 70 ]]; then
    check_pass "磁盘空间充足 (可用: $DISK_AVAIL)"
elif [[ $DISK_USAGE -lt 85 ]]; then
    check_warn "磁盘空间偏紧 (可用: $DISK_AVAIL, 使用率: ${DISK_USAGE}%)"
else
    check_fail "磁盘空间不足 (可用: $DISK_AVAIL, 使用率: ${DISK_USAGE}%)"
    check_info "建议至少保留 2x GitLab 数据大小的空间"
fi
echo ""

# 6. Check network connectivity
echo "6. 检查网络连接"
echo "-------------------"
if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    check_pass "网络连接正常"
else
    check_warn "网络连接可能有问题"
    check_info "远程备份功能可能无法使用"
fi
echo ""

# 7. Check required tools
echo "7. 检查必需工具"
echo "-------------------"
REQUIRED_TOOLS=("bash" "tar" "gzip" "rsync" "ssh")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        check_pass "$tool 已安装"
    else
        check_warn "$tool 未安装"
        check_info "某些功能可能无法使用"
    fi
done
echo ""

# 8. Check file permissions
echo "8. 检查文件权限"
echo "-------------------"
if [[ -w "." ]]; then
    check_pass "当前目录可写"
else
    check_fail "当前目录不可写"
fi

if [[ -r "/var/run/docker.sock" ]]; then
    check_pass "可以访问 Docker socket"
else
    check_warn "无法访问 Docker socket"
    check_info "可能需要 sudo 权限或加入 docker 组"
fi
echo ""

# 9. Detect GitLab installation type
echo "9. GitLab 安装类型检测"
echo "-------------------"
if docker ps --format '{{.Names}}' | grep -q gitlab; then
    check_pass "检测到容器化 GitLab"
    
    # Try to detect GitLab edition
    GITLAB_CONTAINER=$(docker ps --format '{{.Names}}' | grep gitlab | head -1)
    GITLAB_VERSION=$(docker exec "$GITLAB_CONTAINER" gitlab-rake gitlab:env:info 2>/dev/null | grep "GitLab information" -A 5 | grep "Version:" | cut -d':' -f2 | xargs || echo "未知")
    
    if [[ "$GITLAB_VERSION" != "未知" ]]; then
        check_info "GitLab 版本: $GITLAB_VERSION"
    fi
    
    # Check backup directory mount
    BACKUP_MOUNT=$(docker inspect "$GITLAB_CONTAINER" | grep -A 1 '"/var/opt/gitlab/backups"' | grep "Source" | cut -d'"' -f4 || echo "")
    if [[ -n "$BACKUP_MOUNT" ]]; then
        check_info "备份目录挂载: $BACKUP_MOUNT"
    fi
    
elif [[ -f "/usr/bin/gitlab-ctl" ]] || [[ -f "/opt/gitlab/bin/gitlab-ctl" ]]; then
    check_warn "检测到 Omnibus GitLab 安装"
    check_info "本工具主要为容器化 GitLab 设计，可能需要调整"
else
    check_warn "未检测到 GitLab 安装"
    check_info "可以使用测试模式进行功能测试"
fi
echo ""

# 10. Configuration validation
echo "10. 配置文件检查"
echo "-------------------"
if [[ -f "config/backup.conf" ]]; then
    check_pass "配置文件存在: config/backup.conf"
    
    # Validate configuration
    source config/backup.conf 2>/dev/null || true
    
    if [[ -n "${GITLAB_CONTAINER_NAME:-}" ]]; then
        check_info "配置的容器名: $GITLAB_CONTAINER_NAME"
        
        if docker ps --format '{{.Names}}' | grep -q "^${GITLAB_CONTAINER_NAME}$"; then
            check_pass "容器 $GITLAB_CONTAINER_NAME 正在运行"
        else
            check_warn "容器 $GITLAB_CONTAINER_NAME 未运行"
        fi
    else
        check_warn "GITLAB_CONTAINER_NAME 未配置"
    fi
    
    if [[ "${REMOTE_BACKUP_ENABLED:-false}" == "true" ]]; then
        check_info "已启用远程备份"
        if [[ -n "${REMOTE_SERVER:-}" ]]; then
            check_info "远程服务器: $REMOTE_SERVER"
        fi
        if [[ -f "${REMOTE_SSH_KEY:-}" ]]; then
            check_pass "SSH 密钥存在: $REMOTE_SSH_KEY"
        else
            check_warn "SSH 密钥不存在: ${REMOTE_SSH_KEY:-未设置}"
        fi
    fi
    
elif [[ -f "config/backup.conf.example" ]]; then
    check_info "仅有示例配置文件"
    check_info "运行 ./install.sh 或手动复制配置"
else
    check_fail "配置文件缺失"
fi
echo ""

# Summary
echo "========================================="
echo "  检查摘要"
echo "========================================="
echo ""

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ 所有检查通过！系统已准备就绪。${NC}"
    echo ""
    echo "下一步:"
    echo "  1. 运行测试: ./test-backup.sh --dry-run"
    echo "  2. 或直接安装: ./install.sh"
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ 发现 $WARNINGS 个警告，但系统可以使用。${NC}"
    echo ""
    echo "建议:"
    echo "  - 查看上述警告信息"
    echo "  - 在测试模式下验证功能: ./test-backup.sh --dry-run"
else
    echo -e "${RED}✗ 发现 $ERRORS 个错误，$WARNINGS 个警告。${NC}"
    echo ""
    echo "请先解决以下问题:"
    echo "  - 确保 Docker 已安装并运行"
    echo "  - 确保 Docker Compose 已安装"
    echo "  - 确保有足够的磁盘空间"
fi

echo ""
echo "========================================="

exit $ERRORS
