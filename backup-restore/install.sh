#!/bin/bash
set -e

echo "========================================="
echo "  GitLab Backup Solution - 安装向导"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${YELLOW}⚠️  建议使用普通用户运行，而不是 root${NC}"
   read -p "是否继续? (y/n) " -n 1 -r
   echo
   if [[ ! $REPLY =~ ^[Yy]$ ]]; then
       exit 1
   fi
fi

# Check Docker
echo "检查 Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker 未安装${NC}"
    echo "请先安装 Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "${GREEN}✓ Docker 已安装${NC}"

# Check Docker Compose
echo "检查 Docker Compose..."
DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
    echo -e "${GREEN}✓ Docker Compose (plugin) 已安装${NC}"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
    echo -e "${GREEN}✓ docker-compose (standalone) 已安装${NC}"
    echo -e "${YELLOW}ℹ 建议升级到 Docker Compose V2 (plugin)${NC}"
else
    echo -e "${RED}✗ Docker Compose 未安装${NC}"
    echo "请先安装 Docker Compose"
    exit 1
fi
echo ""

# Get GitLab container name
echo "配置向导"
echo "========================================="
echo ""

# Offer auto-configuration
echo -e "${GREEN}推荐: 自动配置${NC}"
echo "自动检测 GitLab 容器并配置所有路径"
echo ""
read -p "是否使用自动配置? (y/n) [y]: " -n 1 -r
echo
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    # Run auto-configure
    if [[ -f "./auto-configure.sh" ]]; then
        ./auto-configure.sh
        
        if [[ $? -eq 0 ]]; then
            echo ""
            echo -e "${GREEN}✓ 自动配置成功完成${NC}"
            echo ""
            
            # Skip to build step
            AUTO_CONFIGURED=true
        else
            echo ""
            echo -e "${YELLOW}自动配置失败，切换到手动配置${NC}"
            echo ""
            AUTO_CONFIGURED=false
        fi
    else
        echo -e "${YELLOW}未找到 auto-configure.sh，使用手动配置${NC}"
        echo ""
        AUTO_CONFIGURED=false
    fi
else
    AUTO_CONFIGURED=false
fi

if [[ "$AUTO_CONFIGURED" != "true" ]]; then
    # Manual configuration
    echo "手动配置模式"
    echo "-------------------"
    echo ""

# List running containers
echo "当前运行的容器："
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
echo ""

read -p "请输入 GitLab 容器名称 [gitlab]: " GITLAB_NAME
GITLAB_NAME=${GITLAB_NAME:-gitlab}

# Verify container exists
if ! docker ps --format '{{.Names}}' | grep -q "^${GITLAB_NAME}$"; then
    echo -e "${YELLOW}⚠️  警告: 容器 '$GITLAB_NAME' 未运行${NC}"
    read -p "是否继续? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get GitLab data directory
echo ""
echo "检测 GitLab 数据目录..."
GITLAB_BACKUP_DIR=$(docker inspect $GITLAB_NAME 2>/dev/null | grep -A 1 '"Destination": "/var/opt/gitlab/backups"' | grep Source | cut -d'"' -f4)

if [[ -n "$GITLAB_BACKUP_DIR" ]]; then
    echo -e "${GREEN}✓ 检测到备份目录: $GITLAB_BACKUP_DIR${NC}"
    read -p "使用此目录? (y/n) [y]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        GITLAB_BACKUP_DIR_CONFIRMED=$GITLAB_BACKUP_DIR
    fi
fi

if [[ -z "$GITLAB_BACKUP_DIR_CONFIRMED" ]]; then
    read -p "请输入 GitLab backups 目录路径 [/srv/gitlab/backups]: " GITLAB_BACKUP_DIR
    GITLAB_BACKUP_DIR=${GITLAB_BACKUP_DIR:-/srv/gitlab/backups}
    GITLAB_BACKUP_DIR_CONFIRMED=$GITLAB_BACKUP_DIR
fi

# Check if directory exists
if [[ ! -d "$GITLAB_BACKUP_DIR_CONFIRMED" ]]; then
    echo -e "${RED}✗ 目录不存在: $GITLAB_BACKUP_DIR_CONFIRMED${NC}"
    exit 1
fi

# Get GitLab config directory
GITLAB_CONFIG_DIR="/srv/gitlab/config"
read -p "GitLab config 目录路径 [$GITLAB_CONFIG_DIR]: " INPUT_CONFIG_DIR
GITLAB_CONFIG_DIR=${INPUT_CONFIG_DIR:-$GITLAB_CONFIG_DIR}

# Retention days
read -p "备份保留天数 [14]: " RETENTION
RETENTION=${RETENTION:-14}

# Feishu notification
echo ""
read -p "是否启用飞书通知? (y/n) [n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ENABLE_FEISHU=true
    read -p "请输入飞书 Webhook URL: " FEISHU_URL
else
    ENABLE_FEISHU=false
    FEISHU_URL=""
fi

# Remote backup
echo ""
read -p "是否启用远程备份? (y/n) [n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ENABLE_REMOTE=true
    read -p "远程服务器地址 (格式: user@host:/path): " REMOTE_SERVER
    read -p "SSH 密钥路径 [~/.ssh/id_rsa]: " SSH_KEY
    SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
    read -p "远程保留天数 [90]: " REMOTE_RETENTION
    REMOTE_RETENTION=${REMOTE_RETENTION:-90}
else
    ENABLE_REMOTE=false
    REMOTE_SERVER=""
    SSH_KEY=""
    REMOTE_RETENTION=""
fi

    # End of manual configuration
fi  # End AUTO_CONFIGURED check

# Create directories
echo ""
echo "创建目录结构..."
mkdir -p backups/full logs config
echo -e "${GREEN}✓ 目录已创建${NC}"

# Generate configuration (skip if auto-configured)
if [[ "$AUTO_CONFIGURED" != "true" ]]; then
echo ""
echo "生成配置文件..."
cat > config/backup.conf <<EOF
# GitLab Backup Configuration
# 由安装脚本自动生成于 $(date)

# GitLab 容器名称
GITLAB_CONTAINER_NAME=$GITLAB_NAME

# 备份保留策略
RETENTION_DAYS=$RETENTION
REMOTE_RETENTION_DAYS=$REMOTE_RETENTION

# 飞书通知
ENABLE_FEISHU_NOTIFY=$ENABLE_FEISHU
FEISHU_WEBHOOK_URL=$FEISHU_URL

# 远程备份
REMOTE_BACKUP_ENABLED=$ENABLE_REMOTE
REMOTE_SERVER=$REMOTE_SERVER
REMOTE_SSH_KEY=$SSH_KEY

# 高级选项
SKIP_ARTIFACTS=true
ENABLE_COMPRESSION=false
MAX_CONCURRENT_BACKUPS=1
EOF

echo -e "${GREEN}✓ 配置文件已生成: config/backup.conf${NC}"
fi  # End of config generation

# Update docker-compose.yml paths if needed (skip if auto-configured)
if [[ "$AUTO_CONFIGURED" != "true" ]]; then
if [[ "$GITLAB_BACKUP_DIR_CONFIRMED" != "/srv/gitlab/backups" ]] || [[ "$GITLAB_CONFIG_DIR" != "/srv/gitlab/config" ]]; then
    echo ""
    echo "更新 docker-compose.yml 路径..."
    sed -i.bak "s|/srv/gitlab/backups|$GITLAB_BACKUP_DIR_CONFIRMED|g" docker-compose.yml
    sed -i.bak "s|/srv/gitlab/config|$GITLAB_CONFIG_DIR|g" docker-compose.yml
    echo -e "${GREEN}✓ docker-compose.yml 已更新${NC}"
fi
fi  # End of docker-compose.yml update

# Build image
echo ""
read -p "是否立即构建 Docker 镜像? (y/n) [y]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "构建镜像..."
    $DOCKER_COMPOSE_CMD build
    echo -e "${GREEN}✓ 镜像构建完成${NC}"
fi

# Test backup
echo ""
read -p "是否执行测试备份? (y/n) [y]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo "执行测试备份..."
    echo "========================================="
    $DOCKER_COMPOSE_CMD run --rm gitlab-backup
    echo "========================================="
    echo ""
    echo -e "${GREEN}✓ 测试备份完成${NC}"
    echo ""
    echo "备份结果："
    ls -lh backups/full/
fi

# Setup cron
echo ""
read -p "是否设置定时任务? (y/n) [y]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo "选择定时方式："
    echo "1) crontab"
    echo "2) systemd timer (推荐)"
    read -p "请选择 [2]: " CRON_TYPE
    CRON_TYPE=${CRON_TYPE:-2}
    
    if [[ "$CRON_TYPE" == "1" ]]; then
        # crontab
        CRON_CMD="0 2 * * * cd $(pwd) && $DOCKER_COMPOSE_CMD run --rm gitlab-backup >> /var/log/gitlab-backup-cron.log 2>&1"
        echo ""
        echo "请手动添加以下行到 crontab:"
        echo ""
        echo "$CRON_CMD"
        echo ""
        read -p "是否自动添加? (y/n) [y]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
            echo -e "${GREEN}✓ crontab 已添加${NC}"
        fi
    else
        # systemd
        echo ""
        echo "创建 systemd 文件..."
        
        sudo tee /etc/systemd/system/gitlab-backup.service > /dev/null <<EOFSVC
[Unit]
Description=GitLab Backup Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=$(pwd)
ExecStart=$(which docker) compose run --rm gitlab-backup
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSVC

        sudo tee /etc/systemd/system/gitlab-backup.timer > /dev/null <<EOFTMR
[Unit]
Description=GitLab Backup Timer
Requires=gitlab-backup.service

[Timer]
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
EOFTMR

        sudo systemctl daemon-reload
        sudo systemctl enable gitlab-backup.timer
        sudo systemctl start gitlab-backup.timer
        
        echo -e "${GREEN}✓ systemd timer 已配置并启动${NC}"
        echo ""
        echo "查看 timer 状态:"
        sudo systemctl status gitlab-backup.timer
    fi
fi

# Summary
echo ""
echo "========================================="
echo -e "${GREEN}✓ 安装完成！${NC}"
echo "========================================="
echo ""
echo "下一步："
echo "1. 查看配置: cat config/backup.conf"
echo "2. 手动备份: docker-compose run --rm gitlab-backup"
echo "3. 查看状态: docker-compose run --rm gitlab-backup /app/scripts/check-status.sh"
echo "4. 查看日志: tail -f logs/backup-*.log"
echo ""
echo "文档: 查看 README.md"
echo ""
