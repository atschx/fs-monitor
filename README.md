# fs-monitor

macOS 目录增长说明工具。它在你选定的目录上建立空间基线，记录监控窗口里的文件系统事件，并在再次扫描后对照差异。进程读写只在系统真实返回时展示，用来提供旁证，而不是把写入归因到这个目录。

## 它说明什么

- 基线与再次扫描之间，常规文件逻辑大小（`stat` 的 `st_size`）发生了多少变化。
- 能读到分配块时，同时给出 `st_blocks × 512` 的差值。这是已分配块，不是独占物理空间。
- 硬链接按 inode 只计入合计一次。同一 inode 仍会在多条路径上分别显示，所以各行相加可能大于合计。
- 监控期间，FSEvents 提供路径、事件标志和时间。这些是操作证据。
- 若 `proc_pid_rusage` 成功，界面显示全进程磁盘计数在两次采样之间的差值。

## 它不能说明什么

- FSEvents 没有 PID，不能指出是哪个进程写入。
- 全进程计数不是目标目录的 I/O，也不能按路径拆开。
- 采样时间、扫描时间和事件时间接近，只说明时间相关，不是因果关系。
- 不能做 100% 物理 IO 归因。压缩、写时复制、稀疏文件、缓存、其他目录上的读写，以及读不到的路径，都会让数字对不上。
- 调用失败时显示「不可获得」。应用不会把缺失值填成 0，也不会猜测。

## 最低版本

- macOS 13 或更新版本
- Xcode 15 或更新版本（Swift 5.9）
- 用 Swift Package 打开即可，不需要单独的 Xcode 工程文件

本包的可执行文件没有沙盒，也没有 entitlements 文件。不要为它添加 Endpoint Security entitlement。

## 权限边界

默认以当前用户运行，不需要 root，也不使用 Endpoint Security。仓库里没有这项授权，界面不会把普通权限说成已经获得。

访问桌面、文稿、下载或其他受保护目录时，系统可能另行弹出隐私提示。那是 macOS 自己的授权。如果系统拒绝，对应路径会出现在「限制与错误」里，合计不包含这些路径。手动在系统设置里授予完全磁盘访问权限可以提高读取成功率；应用不会假装已经拥有它。

应用不会删除文件，不会结束进程，不会关闭 SIP，也不会上传扫描路径或目录内容。选择目录之前不会扫描。符号链接不会被跟到所选目录之外。其他挂载点不会被进入。

## 在 Mac 上构建和运行

```bash
swift test
swift build -c release --product FSMonitor
.build/release/FSMonitor
```

也可以用 Xcode 打开 `Package.swift`，选择 `FSMonitor` scheme 后运行。

`swift test` 在 Mac 上会编译应用，并额外核对 FSEvents 标志值是否与系统 SDK 一致。Linux 上只能编译和测试可移植核心；那里的 `FSMonitor` 可执行文件会说明自己不是 macOS 应用并以状态码 2 退出。

## 用隔离临时目录验证

下面的脚本只创建、修改和删除带有标记的临时目录。它不会扫描主目录，也不会删除没有标记的路径。

```bash
DIR=$(scripts/isolated-demo.sh prepare)
```

记下打印出的路径，然后：

1. 打开应用，选择这个目录。此时还不会扫描。
2. 点击「建立基线」。
3. 点击「开始监控」。
4. 在另一个终端执行 `scripts/isolated-demo.sh grow "$DIR"`。
5. 回到应用，点击「再次扫描」。
6. `data/cache.bin` 和 `logs/new.log` 应出现在按增长排序的结果里。`logs` 的子项增长应包含这两处变化。
7. 「操作证据」里如果出现这些路径，也只说明路径和时间重叠。事件没有 PID。
8. 点击「停止监控」。「进程读写」里的数字如果存在，标签会写明它们是全进程计数，不是这个目录的 I/O。没有返回的计数保持为不可获得。
9. 可以在扫描过程中点击「取消扫描」。取消后，已有基线不会被半次扫描替换。

确认结束后删除夹具：

```bash
scripts/isolated-demo.sh cleanup "$DIR"
```

`cleanup` 要求目录内存在 `.fs-monitor-demo-marker`，并且路径包含 `fs-monitor-demo`。它会拒绝删除过宽的路径。

## 测试数据

脚本和单元测试写入的文件都以这句话开头：

`【测试数据】这是 FSMonitor 的隔离演示或测试夹具，不是用户数据。`

这些文件不是应用扫描用户目录后生成的结果。应用本身不内置演示数据，也不会在未选择目录时读取磁盘。

## 本环境实际执行过的检查

编写时的环境是 Linux `x86_64`（Ubuntu 24.04），Swift 6.0.3，不是 Mac。

已执行：

- `swift test`：20 个 XCTest 通过，0 失败。覆盖扫描、取消、硬链接合计、符号链接不越界、权限错误、差异排序、进程计数差值和归因限制。
- `swift build` 链出的 Linux 可执行文件已运行，退出码为 2，并打印它不能在当前系统启动界面。
- `bash scripts/isolated-demo.sh self-check` 已通过。它只检查临时目录脚本。

这些结果不是 macOS 构建，也没有执行 FSEvents、libproc 或 SwiftUI。

## CI

`.github/workflows/ci.yml` 有两个作业：

- `Linux core tests (not a macOS build)`：在 Ubuntu 上运行 `swift test`。
- `macOS build and tests`：在 `macos-14` 上运行 `swift test` 和 `swift build -c release --product FSMonitor`。

这个工作流已经放进仓库，但本次开发没有 macOS 运行器，所以不能把 macOS 作业说成已经通过。只有 GitHub 上该作业实际结束后，才能采用它的结果。

## 源码结构

- `Sources/FSMonitorCore`：快照、差异、FSEvents 标志解码、全进程计数差值和会话状态。可在 Linux 上测试。
- `Sources/FSMonitorProc`：macOS 上调用 `proc_pid_rusage`、`proc_listallpids` 和 `proc_pidpath`。其他系统的同名函数直接失败，不制造计数。
- `Sources/FSMonitor`：SwiftUI 界面、目录选择、FSEvents 和进程采样。只在 macOS 上编译进应用。
- `Tests/FSMonitorCoreTests`：核心测试。Mac 上还有一组 SDK 标志对照测试。
