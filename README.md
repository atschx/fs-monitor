# fs-monitor

macOS 目录增长说明工具（**测试预发布**）。

选定目录 → 建立空间基线 →（可选）监控 FSEvents → 再次扫描对照差异。五个结果页：子项增长、文件差异、操作证据、进程读写、限制与错误。进程读写只是同时段全进程旁证，**不是**目录级归因，也**不能**做程序—文件精确归因或 100% 物理 IO 归因。

退出应用后**不保留**监控会话、证据或扫描结果。

## 下载

- **预发布：** [v0.1.1-beta.1](https://github.com/atschx/fs-monitor/releases/tag/v0.1.1-beta.1)（以该 Release 页实际附件与 SHA-256 为准）
- 介绍与指南：https://blog.atschx.me/fs-monitor/
- 早期测试标识 [v0.1.0-test](https://github.com/atschx/fs-monitor/releases/tag/v0.1.0-test) **仍然保留**，不是本版本，也不被覆盖

### 本版绑定与包事实

| 项 | 值 |
| --- | --- |
| Tag | `v0.1.1-beta.1`（prerelease） |
| 包内营销版本 | `0.1.1` |
| 构建号 | `2` |
| 绑定提交 | `f1b077f96e5c7244fe55bc42bb060d45e9e09769`（与 tag / `BUILD_INFO.git_sha` 一致） |
| zip SHA-256 | `e31843a4cbb1b1f5fc543ccd2cd561061487519efd18db1f97e8e29e5d7031e4` |
| 架构 | **仅 Apple Silicon（arm64）** |
| 最低系统目标 | macOS **13.0**（目标兼容；**不代表已在 macOS 13 完成交互验收**） |
| 签名 / 公证 | **ad-hoc**，无 Developer ID，**未公证**；Gatekeeper/`spctl` 拒绝为预期 |
| 同包实机交互 | **未验收**（不得视为通过） |
| Liquid Glass | **本版本未提供**该系统外观能力 |

```
e31843a4cbb1b1f5fc543ccd2cd561061487519efd18db1f97e8e29e5d7031e4  FSMonitor.app.zip
```

首次打开（说明供参考，**不保证**各系统/策略下表现一致）：

1. 解压得到 `FSMonitor.app`
2. 选中 App → 右键「打开」→ 确认打开
3. **不要**关闭 Gatekeeper，**不要**关闭 SIP，**不要**执行全局绕过命令

图标：Nova 选定 Huluwa **D2**。已知 16/32 眼神偏弱、大尺寸略偏前；**未**做 Dock 实测。设计稿不是运行截图。

## 快速上手

1. 打开应用 →「选择目录」（选择前不扫描）
2. 「建立基线」（已有基线时「重新建立基线」会先确认）
3. （可选）「开始监控」→ 产生变化 →「停止监控」（停止监控 ≠ 取消扫描）
4. 「复扫查看变化」，在五个结果页查看对照；未知/覆盖缺口不作确定增删

详细步骤、权限、缺口与 FAQ：**[docs/guide.md](docs/guide.md)**（Pages：https://blog.atschx.me/fs-monitor/guide.html）

## 关键限制

- FSEvents **无 PID**；全进程计数 ≠ 目标目录 I/O；时间接近 ≠ 因果
- 不能还原监控开始前的历史；不能许诺退出或重启后回看会话
- 不是现状：跨会话持久化、整盘 IO 仪表盘、已公证正式版、Liquid Glass 外观
- **不是全量产品验收通过**
- 仅 macOS；仓库 CI 不再跑 Linux 测试

## 源码构建（开发者）

```bash
swift test
./scripts/package-macos-app.sh   # 须在 Apple Silicon Mac；产出 dist/FSMonitor.app.zip
```

也可用 Xcode 打开 `Package.swift` 运行 `FSMonitor` scheme。
