# GitLab Backup 快速开始指南

## 🧪 测试优先（推荐）

**⚠️ 建议：在生产环境安装前，先测试功能！**

```bash
# 快速测试（2 分钟）
./preflight-check.sh           # 检查环境
./test-backup.sh --dry-run     # 模拟运行
```

**完整测试指南**: 查看 [TESTING.md](TESTING.md)

---

## 🚀 5 分钟快速安装

### 1. 解压文件

```bash
cd /opt
tar -xzf gitlab-backup-docker.tar.gz
cd gitlab-backup-docker
```

### 2. 一键自动配置（推荐）⭐

**最简单的方式 - 零配置！**

```bash
./auto-configure.sh
```

这个脚本会：
- ✅ 自动找到您的 GitLab 容器
- ✅ 自动检测所有挂载路径
- ✅ 自动生成正确的配置文件
- ✅ 无需手动编辑任何东西

**就这么简单！配置完成后跳到步骤 3。**

---

### 2. 运行安装向导（备选方案）

```bash
./install.sh
```

安装向导会自动：
- ✅ 检查 Docker 环境
- ✅ 检测 GitLab 容器
- ✅ 生成配置文件
- ✅ 构建 Docker 镜像
- ✅ 执行测试备份
- ✅ 设置定时任务

### 3. 手动安装（可选）

如果不使用安装向导，可以手动配置：

```bash
# 复制配置模板
cp config/backup.conf.example config/backup.conf

# 编辑配置（至少修改 GITLAB_CONTAINER_NAME）
vim config/backup.conf

# 构建镜像
docker compose build

# 测试备份
docker compose run --rm gitlab-backup
```

## 📋 基本使用

### 备份

```bash
# 手动备份
docker compose run --rm gitlab-backup

# 查看备份
ls -lht backups/full/
```

### 恢复

```bash
# 列出可用备份
ls -lt backups/full/

# 恢复指定备份
docker compose run --rm gitlab-restore /backups/full/20241203_020000
```

### 状态检查

```bash
docker compose run --rm gitlab-backup /app/scripts/check-status.sh
```

## ⚙️ 最小配置示例

编辑 `config/backup.conf`：

```bash
# 必需配置
GITLAB_CONTAINER_NAME=gitlab          # 改为你的 GitLab 容器名

# 可选配置（使用默认值）
RETENTION_DAYS=14                     # 保留 14 天
ENABLE_FEISHU_NOTIFY=false            # 不启用通知
REMOTE_BACKUP_ENABLED=false           # 不启用远程备份
```

## 📱 配置飞书通知（可选）

1. 在飞书群组中添加自定义机器人
2. 复制 Webhook URL
3. 更新配置：

```bash
ENABLE_FEISHU_NOTIFY=true
FEISHU_WEBHOOK_URL=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
```

## 🔄 设置定时备份

### 方法 1：crontab

```bash
crontab -e

# 添加：每天凌晨 2 点备份
0 2 * * * cd /opt/gitlab-backup-docker && docker compose run --rm gitlab-backup
```

### 方法 2：systemd（推荐）

安装向导会自动设置，或手动执行：

```bash
# 创建 service 文件
sudo cp docs/systemd/gitlab-backup.service /etc/systemd/system/
sudo cp docs/systemd/gitlab-backup.timer /etc/systemd/system/

# 启用定时器
sudo systemctl daemon-reload
sudo systemctl enable gitlab-backup.timer
sudo systemctl start gitlab-backup.timer

# 查看状态
sudo systemctl status gitlab-backup.timer
```

## 🐛 常见问题

### 找不到 GitLab 容器

```bash
# 查看所有容器
docker ps -a

# 更新配置文件中的容器名
vim config/backup.conf
```

### 找不到 GitLab 数据目录

```bash
# 运行诊断工具
./diagnose-gitlab.sh

# 它会显示:
# - 容器的实际挂载路径
# - 推荐的配置
# - 需要更新的地方
```

### 路径不匹配

编辑 `docker-compose.yml`，修改挂载路径：

```yaml
volumes:
  - /srv/gitlab/backups:/gitlab/backups:ro  # 改为实际路径
  - /srv/gitlab/config:/gitlab/config:ro
```

### 权限问题

```bash
# 检查目录权限
ls -ld /srv/gitlab/backups

# 修复权限
sudo chmod 755 /srv/gitlab/backups
```

## 📚 更多信息

- 完整文档：[README.md](README.md)
- 配置说明：[config/backup.conf.example](config/backup.conf.example)
- 故障排查：README.md 中的"故障排查"章节

## ✅ 验证安装

```bash
# 1. 检查配置
cat config/backup.conf

# 2. 执行测试备份
docker compose run --rm gitlab-backup

# 3. 查看备份结果
ls -lh backups/full/

# 4. 查看日志
tail -f logs/backup-*.log

# 5. 检查系统状态
docker compose run --rm gitlab-backup /app/scripts/check-status.sh
```

如果以上步骤都成功，说明安装正确！

## 🎉 完成！

现在你已经拥有一个完整的 GitLab 备份系统：

- ✅ 自动备份
- ✅ 完整性验证
- ✅ 一键恢复
- ✅ 状态监控

享受自动化备份！如有问题，请查看 README.md 或提交 Issue。
