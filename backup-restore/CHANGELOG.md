# 更新日志 / Changelog

所有重要的项目更改都会记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

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
