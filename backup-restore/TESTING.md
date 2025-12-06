# GitLab Backup - 测试指南

在生产环境安装之前，您可以通过多种方式测试备份系统的功能。

## 🎯 测试方法概览

| 方法 | 时间 | 风险 | 适用场景 |
|------|------|------|----------|
| **预检测脚本** | 1 分钟 | 无 | 快速验证环境是否满足要求 |
| **模拟运行** | 2 分钟 | 无 | 查看备份会执行哪些操作 |
| **独立测试环境** | 15 分钟 | 无 | 完整功能测试（推荐） |
| **生产环境只读测试** | 5 分钟 | 低 | 验证与现有 GitLab 的兼容性 |

## 方法 1: 预检测脚本（最快）

**用途**: 验证环境是否满足运行要求

```bash
# 运行预检测
./preflight-check.sh
```

**检查项目**:
- ✅ Docker 和 Docker Compose 安装
- ✅ GitLab 容器检测
- ✅ 磁盘空间
- ✅ 网络连接
- ✅ 必需工具
- ✅ 文件权限
- ✅ 配置验证

**示例输出**:
```
=========================================
  GitLab Backup - 预检测脚本
=========================================

1. 检查 Docker 环境
-------------------
✓ Docker 已安装 (版本: 24.0.6)
✓ Docker 守护进程运行正常

2. 检查 Docker Compose
-------------------
✓ docker compose 已安装 (版本: 2.21.0)

3. 检查 GitLab 容器
-------------------
✓ 发现 GitLab 容器:
    - gitlab (状态: running, 启动: 2024-12-01)

...

=========================================
✓ 所有检查通过！系统已准备就绪。
=========================================
```

## 方法 2: 模拟运行（Dry Run）

**用途**: 查看备份流程会执行哪些操作，但不实际执行

```bash
# 模拟备份
./test-backup.sh --dry-run

# 详细模式
./test-backup.sh --dry-run --verbose
```

**特点**:
- ✅ 完全安全，不会修改任何数据
- ✅ 显示将要执行的所有命令
- ✅ 验证配置正确性
- ✅ 检查所有依赖

**示例输出**:
```
=========================================
  GitLab Backup - 模拟测试 (Dry Run)
=========================================

[10:30:45] 步骤 1/10: 检查配置文件
  ✓ 配置文件加载成功
  ℹ GitLab 容器: gitlab
  ℹ 保留天数: 14

[10:30:45] 步骤 2/10: 检查 Docker 环境
  ✓ Docker 已安装
  ✓ Docker 守护进程运行正常

[10:30:45] 步骤 3/10: 检查 GitLab 容器
  ✓ 容器 gitlab 正在运行

[10:30:45] 步骤 4/10: 测试备份命令
[模拟] docker exec gitlab gitlab-backup create SKIP=artifacts
  ✓ 命令格式正确

...

=========================================
  测试摘要
=========================================

✓ 模拟测试完成！

所有检查都已通过。系统配置正确。

下一步:
  1. 执行实际测试: ./test-backup.sh (不带 --dry-run)
  2. 运行完整备份: docker compose run --rm gitlab-backup
=========================================
```

## 方法 3: 独立测试环境（推荐）

**用途**: 在独立的测试 GitLab 上完整测试所有功能

### 3.1 启动测试 GitLab

```bash
# 1. 启动测试环境（首次需要 5-10 分钟）
docker compose -f docker-compose.test.yml up -d gitlab-test

# 2. 查看启动日志
docker compose -f docker-compose.test.yml logs -f gitlab-test

# 看到 "gitlab Reconfigured!" 表示完成
```

### 3.2 访问测试 GitLab

```bash
# 获取初始密码
docker exec gitlab-test cat /etc/gitlab/initial_root_password

# 浏览器访问
# http://localhost:8929
# 用户名: root
# 密码: (上面命令输出)
```

### 3.3 创建测试数据（可选）

在测试 GitLab 中：
1. 创建一个项目
2. 添加一些文件
3. 创建几个 commit

### 3.4 执行备份测试

```bash
# 准备配置（如果还没有）
cp config/backup.conf.example config/backup.conf

# 编辑配置，设置容器名为 gitlab-test
vim config/backup.conf
# GITLAB_CONTAINER_NAME=gitlab-test

# 执行备份
docker compose -f docker-compose.test.yml run --rm gitlab-backup-test

# 查看备份结果
ls -lh backups/full/
```

### 3.5 测试恢复

```bash
# 列出可用备份
ls -lt backups/full/

# 选择一个备份进行恢复
BACKUP_DIR=$(ls -t backups/full/ | head -1)
echo "恢复备份: $BACKUP_DIR"

# 执行恢复
docker compose -f docker-compose.test.yml run --rm \
  --entrypoint /app/scripts/restore.sh \
  gitlab-backup-test /backups/full/$BACKUP_DIR
```

### 3.6 验证恢复结果

```bash
# 访问 GitLab，检查数据是否完整
# http://localhost:8929

# 检查项目、文件是否都在
```

### 3.7 测试状态检查

```bash
docker compose -f docker-compose.test.yml run --rm \
  gitlab-backup-test /app/scripts/check-status.sh
```

### 3.8 清理测试环境

```bash
# 停止并删除所有测试容器和数据
docker compose -f docker-compose.test.yml down -v

# 删除测试数据目录
rm -rf test-data/

# 保留备份用于验证（可选）
# ls -lh backups/full/
```

## 方法 4: 生产环境只读测试

**用途**: 验证与现有生产 GitLab 的兼容性，但不执行备份

```bash
# 1. 复制配置模板
cp config/backup.conf.example config/backup.conf

# 2. 编辑配置，设置为生产容器名
vim config/backup.conf
# GITLAB_CONTAINER_NAME=gitlab  # 改为实际容器名

# 3. 运行预检测
./preflight-check.sh

# 4. 运行模拟测试
./test-backup.sh --dry-run

# 5. 检查 GitLab 挂载路径
docker inspect gitlab | grep -A 5 Mounts

# 6. 确认 docker-compose.yml 中的路径匹配
cat docker-compose.yml | grep "/srv/gitlab"

# 如果路径不同，修改 docker-compose.yml
vim docker-compose.yml
```

**注意**: 这个测试不会修改任何数据，只是验证配置正确性。

## 🔍 测试清单

完成以下测试以确保系统就绪：

### 基础功能测试
- [ ] 预检测脚本通过
- [ ] 模拟运行成功
- [ ] Docker 镜像构建成功
- [ ] 配置文件验证通过

### 备份功能测试
- [ ] 备份命令执行成功
- [ ] 备份文件生成
- [ ] 备份文件完整性验证（checksum）
- [ ] 配置文件备份
- [ ] SSL 证书备份（如有）

### 恢复功能测试
- [ ] 恢复命令执行成功
- [ ] GitLab 启动正常
- [ ] 数据完整性验证
- [ ] 项目可访问
- [ ] 用户登录正常

### 高级功能测试（可选）
- [ ] 飞书通知发送（如启用）
- [ ] 远程备份同步（如启用）
- [ ] 自动清理旧备份
- [ ] 状态监控脚本

## 📊 测试报告模板

完成测试后，可以使用以下模板记录结果：

```markdown
# GitLab Backup 测试报告

**测试日期**: 2024-12-03
**测试人员**: [您的名字]
**环境**: [测试/生产]

## 环境信息
- Docker 版本: [版本号]
- Docker Compose 版本: [版本号]
- GitLab 版本: [版本号]
- 操作系统: [系统信息]

## 测试结果

### 预检测
- 状态: ✅ 通过 / ❌ 失败
- 问题: [如有]

### 备份测试
- 备份时间: [耗时]
- 备份大小: [大小]
- 状态: ✅ 成功 / ❌ 失败
- 问题: [如有]

### 恢复测试
- 恢复时间: [耗时]
- 状态: ✅ 成功 / ❌ 失败
- 数据完整性: ✅ 完整 / ❌ 有问题
- 问题: [如有]

### 通知测试
- 飞书通知: ✅ 正常 / ❌ 失败 / ⊘ 未启用
- 问题: [如有]

### 远程备份测试
- 远程同步: ✅ 正常 / ❌ 失败 / ⊘ 未启用
- 问题: [如有]

## 总结
- 是否建议部署到生产: ✅ 是 / ❌ 否
- 需要改进的地方: [说明]
```

## 🚀 测试完成后

所有测试通过后：

```bash
# 1. 清理测试环境（如果使用了测试 GitLab）
docker compose -f docker-compose.test.yml down -v
rm -rf test-data/

# 2. 配置生产环境
cp config/backup.conf.example config/backup.conf
vim config/backup.conf

# 3. 运行安装向导
./install.sh

# 或手动部署
docker compose build
docker compose run --rm gitlab-backup

# 4. 设置定时任务
crontab -e
# 添加: 0 2 * * * cd /opt/gitlab-backup-docker && docker compose run --rm gitlab-backup
```

## ❓ 常见测试问题

### Q1: 测试 GitLab 启动很慢？
**A**: GitLab 首次启动需要 5-10 分钟。可以查看日志：
```bash
docker compose -f docker-compose.test.yml logs -f gitlab-test
```

### Q2: 测试占用太多资源？
**A**: 测试 GitLab 默认配置已经是最小化的。如果还是太重，可以：
1. 仅使用预检测和模拟运行
2. 在虚拟机中测试
3. 在非工作时间测试

### Q3: 如何测试大数据量备份？
**A**: 
```bash
# 在测试 GitLab 中导入数据
docker cp large-project.tar gitlab-test:/tmp/
docker exec gitlab-test gitlab-rake gitlab:import:repos
```

### Q4: 模拟运行能测试所有功能吗？
**A**: 模拟运行只验证配置和命令，不实际执行。要测试完整功能，需要方法 3（独立测试环境）。

## 📚 相关文档

- [README.md](README.md) - 完整文档
- [QUICKSTART.md](QUICKSTART.md) - 快速开始
- [config/backup.conf.example](config/backup.conf.example) - 配置说明

---

**建议**: 在生产部署前，至少完成**方法 1 和方法 2**，推荐完成**方法 3**的完整功能测试。
