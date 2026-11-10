# fs-monitor

macOS 目录增长说明工具（早期 demo / 测试版）。

选定目录 → 建立空间基线 →（可选）监控 FSEvents → 再次扫描对照差异。进程读写只在系统真实返回时展示，用作旁证，**不是**目录级归因，也**不能**做 100% 物理 IO 归因。

## 下载

- 介绍与指南：https://blog.atschx.me/fs-monitor/
- 安装包：[Releases](https://github.com/atschx/fs-monitor/releases)（**以页面实际内容为准**；若为空则尚无公开预发布）
- CI 工件：Actions 中的 `FSMonitor-macos-app`（需登录）

当前公开测试包目标：

- 系统目标：macOS 13+
- 架构：**仅 Apple Silicon（arm64）**；本仓库 CI 在 `macos-15` arm64 上打包
- **同一包在真实 Mac（含 macOS 13）上的交互运行尚未由本发布流程验证**
- 签名：**ad-hoc**，无 Apple Developer ID，**未公证**；CI 上 `spctl --assess` 为 **rejected**（预期）

首次打开（说明供参考，**不保证**各系统/策略下表现一致）：

1. 解压得到 `FSMonitor.app`
2. 选中 App → 右键「打开」→ 确认打开
3. **不要**关闭 Gatekeeper，**不要**关闭 SIP，**不要**执行全局绕过命令

图标：本轮采用 Nova 选定的 Huluwa **D2**（已核验 SHA256/RGBA）。已知保留不足：16/32 眼神偏弱、大尺寸略偏前；**未**做 Dock 实测。未混入 board/参考底图。

## 快速上手

1. 打开应用 →「选择目录」（选择前不扫描）
2. 「建立基线」
3. （可选）「开始监控」→ 产生变化 →「停止监控」
4. 「再次扫描」，在汇总 / 文件 / 操作证据 / 进程读写中查看结果

详细步骤、权限、缺口与 FAQ：**[docs/guide.md](docs/guide.md)**（Pages：https://blog.atschx.me/fs-monitor/guide.html）

## 关键限制

- FSEvents **无 PID**；全进程计数 ≠ 目标目录 I/O；时间接近 ≠ 因果
- 不是现状：跨会话持久化回溯、整盘 IO 仪表盘、复制/暂停归因、已公证正式版
- 仅 macOS；仓库 CI 不再跑 Linux 测试

## 源码构建（开发者）

```bash
swift test
./scripts/package-macos-app.sh   # 须在 Apple Silicon Mac；产出 dist/FSMonitor.app.zip
```

也可用 Xcode 打开 `Package.swift` 运行 `FSMonitor` scheme。
