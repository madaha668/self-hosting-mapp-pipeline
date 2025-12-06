# 更新日志 / Changelog

所有重要的项目更改都会记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.3.0] - 2024-12-05

### 新增 (Added)
- ✨ **零配置自动检测** (`auto-configure.sh`) ⭐ **重大功能**
  - 自动检测 GitLab 容器的挂载配置
  - 自动生成 docker-compose.yml 配置
  - 自动创建 backup.conf 配置文件
  - 支持 Docker 命名卷和目录绑定挂载
  - 完全无需手动编辑配置

### 改进 (Improved)
- 🔄 更新 `install.sh` 默认使用自动配置
- 📖 强调零配置安装方式
- 🎯 解决硬编码路径问题

### 修复 (Fixed)
- 🐛 彻底修复路径检测问题 - 不再依赖硬编码路径
- 🐛 支持任意 GitLab 容器配置方式

## [1.2.1] - 2024-12-05

### 新增 (Added)
- ✨ **GitLab 容器诊断工具** (`diagnose-gitlab.sh`)
  - 自动检测容器挂载配置
  - 显示实际路径和卷类型
  - 生成推荐的 docker-compose.yml 配置
  - 列出现有备份文件

### 改进 (Improved)
- 🔍 改进 `preflight-check.sh` 的 GitLab 目录检测
  - 从运行中的容器自动检测挂载点
  - 支持 Docker 命名卷
  - 不再因找不到标准路径而报错
  - 提供更友好的提示信息

### 修复 (Fixed)
- 🐛 修复预检测脚本对 Docker 命名卷的误报
- 🐛 修复容器化 GitLab 的目录检测逻辑

### 文档 (Documentation)
- 📖 添加故障排查章节说明"未找到数据目录"问题
- 📖 更新诊断工具使用说明

## [1.2.0] - 2024-12-05

### 新增 (Added)
- ✨ **Docker Compose V2 支持** - 现代化 `docker compose` 命令
  - 自动检测 Docker Compose V2 (plugin) 和 V1 (standalone)
  - 优先使用 V2，回退支持 V1
  - 所有脚本都包含版本检测逻辑
  - 新增 `DOCKER-COMPOSE.md` 兼容性文档

### 改进 (Improved)
- 🔄 更新所有文档使用 `docker compose` (V2) 语法
- 🔄 更新 systemd 服务文件使用 Docker Compose V2
- 🔄 改进安装脚本的版本检测和提示
- ✅ 保持完全向后兼容 `docker-compose` (V1)

### 修复 (Fixed)
- 🐛 修复文件名 `docker-compose.yml` 不受替换影响

### 文档 (Documentation)
- 📖 新增 DOCKER-COMPOSE.md 详细说明
- 📖 更新所有示例代码使用现代语法
- 📖 添加 Docker Compose 升级指南

## [1.1.0] - 2024-12-05

### 新增 (Added)
- ✨ **测试框架** - 完整的测试工具套件
  - `preflight-check.sh` - 环境预检测脚本
  - `test-backup.sh` - 支持 dry-run 模式的测试脚本
  - `docker-compose.test.yml` - 独立测试环境配置
  - `TESTING.md` - 详细测试指南文档
- 🧪 模拟运行模式（--dry-run）- 安全测试所有功能
- 🧪 独立测试 GitLab 环境 - 不影响生产系统
- 📋 10 项自动化环境检查
- 📊 详细的测试报告模板

### 改进 (Improved)
- 📚 更新文档，强调测试优先的最佳实践
- 🎯 更清晰的项目结构说明
- ✅ 更完善的安装前验证

### 文档 (Documentation)
- 📖 新增 TESTING.md 完整测试指南
- 📖 更新 README.md 增加测试章节
- 📖 更新 QUICKSTART.md 推荐测试流程

## [1.0.0] - 2024-12-03

### 新增 (Added)
- ✨ 完整的容器化 GitLab 备份解决方案
- ✨ 自动备份功能（backup.sh）
- ✨ 一键恢复功能（restore.sh）
- ✨ 系统状态检查（check-status.sh）
- ✨ 交互式安装向导（install.sh）
- ✨ 飞书 Webhook 通知集成
- ✨ 远程服务器 rsync 同步
- ✨ 备份完整性自动验证（checksum）
- ✨ 可配置的本地和远程保留策略
- ✨ 防并发运行的锁机制
- ✨ 磁盘空间监控和预警
- ✨ Prometheus 格式指标导出
- ✨ 详细的操作日志记录
- ✨ systemd timer 和 crontab 支持
- ✨ 全面的中英文档
- ✨ Docker Compose 服务编排

### 安全 (Security)
- 🔒 GitLab 目录只读挂载
- 🔒 SSH 密钥安全处理
- 🔒 配置文件权限检查

### 文档 (Documentation)
- 📚 完整的 README.md
- 📚 快速开始指南（QUICKSTART.md）
- 📚 详细的配置说明
- 📚 故障排查指南
- 📚 最佳实践建议
- 📚 systemd 配置示例

## [计划] - 未来版本

### 计划新增
- [ ] 邮件通知支持
- [ ] S3/OSS 对象存储支持
- [ ] 增量备份功能
- [ ] Web UI 管理界面
- [ ] 多 GitLab 实例支持
- [ ] 备份加密功能
- [ ] Webhook 通知（通用）
- [ ] 备份压缩率优化
- [ ] 并行备份支持
- [ ] 备份验证自动化测试

### 改进计划
- [ ] 性能优化
- [ ] 更详细的错误信息
- [ ] 更多的监控指标
- [ ] 英文文档完善

---

## 版本说明

- **[主版本号]**：不兼容的 API 修改
- **[次版本号]**：向下兼容的功能性新增
- **[修订号]**：向下兼容的问题修正

## 贡献

欢迎提交 Issue 和 Pull Request！
