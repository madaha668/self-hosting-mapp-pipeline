# Docker Compose 兼容性说明

## 版本说明

本项目支持两种 Docker Compose 版本：

### Docker Compose V2 (Plugin) - **推荐** ✅

```bash
# 命令格式
docker compose [command]

# 示例
docker compose up -d
docker compose run --rm gitlab-backup
docker compose down
```

**特点**:
- ✅ 现代版本，官方推荐
- ✅ 作为 Docker CLI 插件运行
- ✅ 更快的性能
- ✅ 更好的维护支持
- ✅ 本项目默认使用

**安装**:
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install docker-compose-plugin

# 或通过 Docker Desktop 自动包含
```

### Docker Compose V1 (Standalone) - 向后兼容

```bash
# 命令格式
docker-compose [command]

# 示例  
docker-compose up -d
docker-compose run --rm gitlab-backup
docker-compose down
```

**特点**:
- ⚠️ 旧版本，将被废弃
- ⚠️ 独立的 Python 应用
- ✅ 本项目仍然支持

## 项目中的自动检测

本项目的所有脚本都会自动检测可用的 Docker Compose 版本：

1. **优先使用** `docker compose` (V2 Plugin)
2. **回退使用** `docker-compose` (V1 Standalone)
3. **都不可用** 则报错并提示安装

### 检测脚本

所有交互式脚本（`preflight-check.sh`、`test-backup.sh`、`install.sh`）都包含自动检测：

```bash
# 自动检测示例
if docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "错误: Docker Compose 未安装"
    exit 1
fi

# 使用检测到的命令
$DOCKER_COMPOSE_CMD up -d
```

## 文档约定

- **所有示例代码** 使用 `docker compose` (V2 语法)
- **文件名** 保持 `docker-compose.yml` (标准命名)
- **兼容性** 脚本自动处理两个版本

## 升级到 V2

### 为什么要升级？

1. **官方推荐** - Docker 官方现在推荐使用 V2
2. **更好的性能** - V2 使用 Go 实现，比 V1 更快
3. **持续维护** - V1 已进入维护模式
4. **功能更新** - 新功能只在 V2 中添加

### 如何升级？

#### Ubuntu/Debian

```bash
# 1. 安装 Docker Compose V2 插件
sudo apt-get update
sudo apt-get install docker-compose-plugin

# 2. 验证安装
docker compose version

# 3. (可选) 卸载旧版本
sudo apt-get remove docker-compose
```

#### 使用 Docker Desktop

Docker Desktop 自动包含 Docker Compose V2，无需额外安装。

#### 手动安装

```bash
# 下载最新版本
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o $DOCKER_CONFIG/cli-plugins/docker-compose

# 添加执行权限
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

# 验证
docker compose version
```

### 迁移现有项目

**好消息**: 无需更改 `docker-compose.yml` 文件！

```bash
# V1 语法
docker-compose up -d

# V2 语法（只需去掉连字符）
docker compose up -d
```

所有 `docker-compose.yml` 文件格式完全兼容。

## 验证您的版本

```bash
# 检查 V2 (Plugin)
docker compose version
# 输出示例: Docker Compose version v2.21.0

# 检查 V1 (Standalone)  
docker-compose --version
# 输出示例: docker-compose version 1.29.2

# 使用本项目的预检测脚本
./preflight-check.sh
```

## 常见问题

### Q: 我可以同时安装 V1 和 V2 吗？

**A**: 可以！两者可以共存。脚本会优先使用 V2。

### Q: 我的系统只有 V1，能用吗？

**A**: 可以！本项目完全支持 V1。但建议升级到 V2。

### Q: 升级后旧项目会出问题吗？

**A**: 不会。`docker-compose.yml` 文件格式完全兼容。

### Q: 如何强制使用特定版本？

**A**: 
```bash
# 强制使用 V2
docker compose run --rm gitlab-backup

# 强制使用 V1  
docker-compose run --rm gitlab-backup
```

### Q: systemd 服务文件需要更新吗？

**A**: 推荐更新为 V2 语法：

```ini
# V2 (推荐)
ExecStart=/usr/bin/docker compose run --rm gitlab-backup

# V1 (仍然支持)
ExecStart=/usr/bin/docker-compose run --rm gitlab-backup
```

## 参考链接

- [Docker Compose V2 官方文档](https://docs.docker.com/compose/)
- [Docker Compose V2 安装指南](https://docs.docker.com/compose/install/)
- [Docker Compose V1 到 V2 迁移](https://docs.docker.com/compose/migrate/)

---

**总结**: 本项目使用现代 `docker compose` 语法，但完全兼容旧版 `docker-compose`。建议升级到 V2 以获得更好的性能和支持。
