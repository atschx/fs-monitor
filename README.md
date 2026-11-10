# fs-monitor

macOS 目录增长说明工具（早期 demo，仍在迭代）。

选定一个目录 → 建立空间基线 →（可选）开始监控文件系统事件 → 再次扫描对照差异。进程读写只在系统真实返回时展示，用作旁证，**不是**目录级归因，也**不能**做 100% 物理 IO 归因。

## 当前实有能力

- 扫描所选目录，记录常规文件逻辑大小（`st_size`）；可读到时一并给出分配块（`st_blocks × 512`）。
- 基线与再次扫描之间的路径级差分与顶层子项汇总；硬链接按 inode 合计一次。
- 监控窗口内记录 FSEvents（路径、标志、时间）作为操作证据；**事件没有 PID**。
- 若 `proc_pid_rusage` 成功，显示全进程磁盘计数差值；失败则显示「不可获得」，不会填 0。
- 可取消扫描；取消后不会用半次结果替换已有基线。
- 默认不以 root 运行；无 Endpoint Security entitlement。

## 明确做不到 / 不是现状

- 不能指出是哪个进程写入了所选目录（FSEvents 无 PID）。
- 全进程计数 ≠ 目标目录 I/O，也不能按路径拆开。
- 时间接近 ≠ 因果关系。
- **不是**现状：跨会话持久化回溯、整盘 IO 仪表盘、复制/暂停类归因、`fs_usage` 集成、已公证的正式签名发行版。

## 系统要求

- macOS 13 或更新版本
- 预编译测试包：按 Releases 中 `BUILD_INFO.txt` / `lipo` 标注的架构（当前 CI 在 `macos-15` 上打包，通常为 Apple Silicon `arm64`）
- 从源码构建：Xcode 15+（Swift 5.9+）

本项目只面向 macOS。仓库 CI 不再运行 Linux 测试。

## 下载与首次运行

介绍页：https://blog.atschx.me/fs-monitor/（`https://atschx.github.io/fs-monitor/` 可能按账号自定义域转到此处）

| 入口 | 状态 |
| --- | --- |
| [GitHub Releases](https://github.com/atschx/fs-monitor/releases) | **以页面实际内容为准**。若尚无预发布，请用下方源码构建，或等待 Actions 产物 / 合并后触发的预发布 |
| Actions 中的 `FSMonitor-macos-app` 工件 | CI 在 macOS runner 上打包的 `.app.zip`（需登录 GitHub 下载） |

预编译包为 **ad-hoc 签名测试版**，**未** Apple Developer ID 签名，**未**公证。首次打开：

1. 解压得到 `FSMonitor.app`
2. 选中 App → 右键「打开」→ 确认打开
3. **不要**关闭 Gatekeeper，**不要**关闭 SIP，**不要**执行全局绕过命令

更完整步骤见 [使用指南](docs/guide.md)。

## 使用指南

请阅读 **[docs/guide.md](docs/guide.md)**：选目录、建基线、监控、复扫、读证据、权限、未知项、卸载与常见问题。只描述已实现流程。

## 从源码构建（开发者）

```bash
swift test
swift build -c release --product FSMonitor
.build/release/FSMonitor
```

打包可双击的 `.app`（须在 Mac 上）：

```bash
./scripts/package-macos-app.sh
# 产物：dist/FSMonitor.app 与 dist/FSMonitor.app.zip
```

也可用 Xcode 打开 `Package.swift`，选择 `FSMonitor` scheme 运行。

## 仓库结构（简）

- `Sources/FSMonitor`：SwiftUI 界面与 macOS 监控
- `Sources/FSMonitorCore`：扫描、差分、会话与归因限制文案
- `Sources/FSMonitorProc`：`proc_pid_rusage` 等进程采样
- `Tests/FSMonitorCoreTests`：核心与（Mac 上）SDK 标志对照测试
- `docs/`：介绍页与使用指南；由 GitHub Pages 发布
- `scripts/package-macos-app.sh`：在 macOS 上测试、构建并打出 ad-hoc `.app`

## CI

`.github/workflows/ci.yml` 仅在 `macos-15` 上执行测试、构建并打包 `.app` 工件。文档-only 变更默认不触发该工作流。介绍页部署见 `.github/workflows/pages.yml`。预发布流程见 `.github/workflows/release.yml`（`workflow_dispatch`）。
