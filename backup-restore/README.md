# GitLab Backup & Restore Solution (Docker)

一个完整的容器化 GitLab 备份与恢复解决方案，支持自动备份、远程同步、完整性验证和飞书通知。

## 📋 特性

- ✅ **容器化部署**：独立的备份容器，不影响 GitLab 运行
- ✅ **自动备份**：支持 cron 定时任务
- ✅ **完整性验证**：自动校验备份文件完整性
- ✅ **远程同步**：支持 rsync 远程备份
- ✅ **通知系统**：飞书 Webhook 通知
- ✅ **自动清理**：可配置的备份保留策略
- ✅ **一键恢复**：简单的恢复流程
- ✅ **状态监控**：实时查看备份状态
- ✅ **指标导出**：Prometheus 格式指标

## 🏗️ 架构

```
┌─────────────────────────────────────────────────────────────┐
│                       宿主机 (Host)                         │
│                                                             │
│  ┌──────────────┐         ┌──────────────────────────┐    │
│  │   GitLab     │         │   Backup Container        │    │
│  │  Container   │◄────────│  (按需运行)               │    │
│  │              │  exec   │  - backup.sh              │    │
│  │  /var/opt/   │         │  - restore.sh             │    │
│  │   gitlab/    │         │  - check-status.sh        │    │
│  │   backups/   │         └───────────┬───────────────┘    │
│  └──────┬───────┘                     │                    │
│         │                             │                    │
│  /srv/gitlab/backups (ro) ◄──────────┘                    │
│  /srv/gitlab/config (ro)                                   │
│  ./backups ◄─────────── 备份输出                          │
│  ./config  ◄─────────── 配置文件                          │
│  ./logs    ◄─────────── 日志                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ rsync (可选)
                           ▼
                  ┌─────────────────┐
                  │  远程备份服务器  │
                  └─────────────────┘
```

## 📦 项目结构

```
gitlab-backup-docker/
├── Dockerfile                      # 备份容器镜像
├── docker-compose.yml              # 服务编排
├── README.md                       # 本文件
│
├── scripts/                        # 脚本目录
│   ├── backup.sh                   # 备份脚本
│   ├── restore.sh                  # 恢复脚本
│   └── check-status.sh             # 状态检查脚本
│
├── config/                         # 配置目录
│   └── backup.conf.example         # 配置模板
│
├── backups/                        # 备份输出目录（自动创建）
│   └── full/
│       └── 20241203_020000/        # 按时间戳组织
│           ├── gitlab_data_*.tar   # 数据备份
│           ├── gitlab.rb           # 配置文件
│           ├── gitlab-secrets.json # 密钥
│           ├── certs.tar.gz        # SSL 证书
│           ├── runner.tar.gz       # Runner 配置
│           └── checksums.txt       # 校验和
│
└── logs/                           # 日志目录（自动创建）
    ├── backup-20241203_020000.log
    └── restore-20241203_080000.log
```

## 🚀 快速开始

### 1. 前置条件

- Docker 和 Docker Compose
- 运行中的 GitLab 容器
- GitLab 数据目录挂载在 `/srv/gitlab`（可自定义）

### 2. 安装

```bash
# 克隆或下载项目
cd /opt
mkdir gitlab-backup-docker
cd gitlab-backup-docker

# 解压文件（假设已下载）
tar -xzf gitlab-backup-docker.tar.gz

# 或者从 Git 克隆（如果有仓库）
# git clone https://github.com/yourusername/gitlab-backup-docker.git
# cd gitlab-backup-docker
```

### 3. 配置

```bash
# 复制配置模板
cp config/backup.conf.example config/backup.conf

# 编辑配置
vim config/backup.conf
```

**最小配置**：

```bash
# 仅需修改 GitLab 容器名
GITLAB_CONTAINER_NAME=gitlab  # 改为你的 GitLab 容器名

# 其他使用默认值即可
RETENTION_DAYS=14
ENABLE_FEISHU_NOTIFY=false
REMOTE_BACKUP_ENABLED=false
```

### 4. 验证 GitLab 路径

确保 `docker-compose.yml` 中的路径与你的 GitLab 安装一致：

```bash
# 检查 GitLab 数据目录
docker inspect gitlab | grep -A 10 Mounts

# 根据实际情况修改 docker-compose.yml 中的路径
# 默认：
#   - /srv/gitlab/backups:/gitlab/backups:ro
#   - /srv/gitlab/config:/gitlab/config:ro
```

### 5. 构建镜像

```bash
docker-compose build
```

### 6. 测试备份

```bash
# 手动执行一次备份
docker-compose run --rm gitlab-backup

# 查看日志
tail -f logs/backup-*.log

# 查看备份结果
ls -lh backups/full/
```

### 7. 设置定时任务

**方法 1：宿主机 crontab**

```bash
# 编辑 crontab
crontab -e

# 添加定时任务（每天凌晨 2 点）
0 2 * * * cd /opt/gitlab-backup-docker && docker-compose run --rm gitlab-backup >> /var/log/gitlab-backup-cron.log 2>&1
```

**方法 2：systemd timer（推荐）**

创建 `/etc/systemd/system/gitlab-backup.service`：

```ini
[Unit]
Description=GitLab Backup Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/gitlab-backup-docker
ExecStart=/usr/bin/docker-compose run --rm gitlab-backup
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

创建 `/etc/systemd/system/gitlab-backup.timer`：

```ini
[Unit]
Description=GitLab Backup Timer
Requires=gitlab-backup.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

启用定时器：

```bash
systemctl daemon-reload
systemctl enable gitlab-backup.timer
systemctl start gitlab-backup.timer
systemctl status gitlab-backup.timer
```

## 🔧 使用指南

### 备份操作

```bash
# 手动备份
docker-compose run --rm gitlab-backup

# 查看备份列表
ls -lht backups/full/

# 查看最新备份内容
ls -lh backups/full/$(ls -t backups/full/ | head -1)

# 查看备份状态
docker-compose run --rm gitlab-backup /app/scripts/check-status.sh
```

### 恢复操作

```bash
# 列出可用备份
docker-compose run --rm gitlab-restore /backups/full/

# 恢复指定备份（会有交互确认）
docker-compose run --rm gitlab-restore /backups/full/20241203_020000

# 非交互恢复（自动确认）
echo "yes" | docker-compose run --rm gitlab-restore /backups/full/20241203_020000
```

**⚠️ 恢复注意事项**：

1. 恢复会覆盖当前 GitLab 数据，请谨慎操作
2. 建议在测试环境先验证备份完整性
3. 恢复后需要等待 GitLab 完全启动（约 1-2 分钟）
4. 恢复完成后建议手动验证数据完整性

### 状态检查

```bash
# 查看系统状态
docker-compose run --rm gitlab-backup /app/scripts/check-status.sh

# 或者直接在宿主机执行
./scripts/check-status.sh
```

状态检查包括：
- 系统信息
- 磁盘使用情况
- 备份统计
- 最近备份列表
- 日志摘要
- 容器状态
- 配置检查

## ⚙️ 配置详解

### 基本配置

```bash
# GitLab 容器名称（必需）
GITLAB_CONTAINER_NAME=gitlab
```

### 保留策略

```bash
# 本地保留天数
RETENTION_DAYS=14

# 远程保留天数（启用远程备份时）
REMOTE_RETENTION_DAYS=90
```

### 飞书通知

```bash
# 启用通知
ENABLE_FEISHU_NOTIFY=true

# Webhook URL
FEISHU_WEBHOOK_URL=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
```

**获取 Webhook URL**：
1. 打开飞书群组
2. 设置 → 群机器人
3. 添加机器人 → 自定义机器人
4. 复制 Webhook 地址

### 远程备份

```bash
# 启用远程备份
REMOTE_BACKUP_ENABLED=true

# 远程服务器（SSH 格式）
REMOTE_SERVER=backup@backup.example.com:/data/backups/gitlab

# SSH 密钥路径
REMOTE_SSH_KEY=/root/.ssh/id_rsa
```

**配置 SSH 密钥**：

```bash
# 生成密钥
ssh-keygen -t rsa -b 4096 -f ~/.ssh/gitlab_backup_rsa

# 复制公钥到远程服务器
ssh-copy-id -i ~/.ssh/gitlab_backup_rsa.pub backup@backup.example.com

# 测试连接
ssh -i ~/.ssh/gitlab_backup_rsa backup@backup.example.com
```

### 高级选项

```bash
# 跳过 artifacts（节省空间）
SKIP_ARTIFACTS=true

# 额外压缩
ENABLE_COMPRESSION=false

# 并发限制
MAX_CONCURRENT_BACKUPS=1
```

## 🛡️ 安全建议

1. **只读挂载**：GitLab 目录使用 `:ro` 只读挂载
2. **SSH 密钥权限**：确保私钥权限为 600
3. **配置文件权限**：`chmod 600 config/backup.conf`
4. **远程服务器**：使用专用备份用户，限制权限
5. **Webhook 安全**：不要在公开场合暴露 Webhook URL

## 📊 监控和告警

### Prometheus 指标

备份脚本会生成 `backups/metrics.prom` 文件：

```prometheus
gitlab_backup_size_bytes 1234567890
gitlab_backup_timestamp 1701619200
gitlab_backup_success 1
```

可以使用 node_exporter 的 textfile collector 导出：

```bash
# 在 node_exporter 配置中
--collector.textfile.directory=/opt/gitlab-backup-docker/backups
```

### 日志监控

使用 `journalctl` 或 ELK/Loki 收集日志：

```bash
# 查看 systemd 日志
journalctl -u gitlab-backup.service -f

# 查看备份日志
tail -f logs/backup-*.log
```

## 🐛 故障排查

### 备份失败

**问题：找不到 GitLab 容器**

```bash
# 检查容器名称
docker ps | grep gitlab

# 更新配置文件中的容器名
vim config/backup.conf
```

**问题：权限被拒绝**

```bash
# 检查目录权限
ls -ld /srv/gitlab/backups

# 确保 Docker 可以访问
sudo chmod 755 /srv/gitlab/backups
```

**问题：磁盘空间不足**

```bash
# 检查磁盘使用
df -h /opt/gitlab-backup-docker/backups

# 手动清理旧备份
find backups/full -type d -mtime +30 -exec rm -rf {} +
```

### 恢复失败

**问题：备份文件损坏**

```bash
# 验证备份完整性
cd backups/full/20241203_020000
sha256sum -c checksums.txt

# 尝试手动解压
tar -tzf gitlab_data_*.tar | head
```

**问题：GitLab 无法启动**

```bash
# 查看 GitLab 日志
docker logs gitlab

# 检查配置文件
docker exec gitlab cat /etc/gitlab/gitlab.rb

# 重新配置
docker exec gitlab gitlab-ctl reconfigure
```

### 远程同步失败

**问题：SSH 连接失败**

```bash
# 测试 SSH 连接
ssh -i ~/.ssh/gitlab_backup_rsa backup@backup.example.com

# 检查 known_hosts
ssh-keyscan backup.example.com >> ~/.ssh/known_hosts
```

**问题：网络超时**

```bash
# 增加超时时间
# 在 backup.sh 中的 rsync 命令添加：
--timeout=3600
```

## 📚 最佳实践

### 1. 备份策略

- **频率**：每天一次备份
- **保留**：本地 14 天，远程 90 天
- **验证**：每周测试一次恢复

### 2. 监控清单

- ✅ 备份成功率（通过飞书通知）
- ✅ 备份大小趋势
- ✅ 磁盘空间使用
- ✅ 备份年龄（最新备份时间）

### 3. 定期任务

```bash
# 每月第一天测试恢复（测试环境）
0 3 1 * * /opt/gitlab-backup-docker/scripts/test-restore.sh

# 每周一查看状态报告
0 9 * * 1 /opt/gitlab-backup-docker/scripts/check-status.sh | mail -s "GitLab Backup Status" admin@example.com
```

### 4. 灾难恢复计划

1. **文档化**：记录恢复步骤
2. **定期演练**：每季度一次完整恢复测试
3. **异地备份**：使用远程备份功能
4. **多副本**：考虑多个备份目标

## 🔄 升级指南

### 从旧版本升级

```bash
# 备份当前配置
cp config/backup.conf config/backup.conf.bak

# 拉取新版本
git pull  # 或下载新版本

# 对比配置变化
diff config/backup.conf.bak config/backup.conf.example

# 重新构建镜像
docker-compose build --no-cache

# 测试
docker-compose run --rm gitlab-backup
```

## 📝 变更日志

### v1.0.0 (2024-12-03)

- ✨ 初始版本
- ✅ 完整的备份和恢复功能
- ✅ 飞书通知集成
- ✅ 远程同步支持
- ✅ 完整性验证
- ✅ 状态监控
- ✅ Prometheus 指标

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## 📮 联系方式

- 问题反馈：[GitHub Issues]
- 邮件：admin@example.com

## 🙏 致谢

感谢 GitLab 社区和所有贡献者。

---

**享受自动化备份！ 🎉**
