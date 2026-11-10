# UI 交接（v0.1.1-beta.1 · Huluwa v2.2）

本目录保存首批可实施稿与本分支承接说明。**设计示意 ≠ 已发布；示例数字（如 1240 / 1334 / +174）不可硬编码。**

内部规格快照与完整 30 页评审 PDF **不写入公开仓库**；本 README 只记工程承接要点。

## 资产（首批已入库）

| 文件 | 说明 |
| --- | --- |
| `main-monitoring-light.png` | 监控中主窗 · 浅色 |
| `main-monitoring-dark.png` | 监控中主窗 · 深色代表 |
| `components.png` | 组件样式与尺寸板 |
| `fs-monitor-ui-handoff-v2_1f59.pdf` | 首批 PDF（已被 Huluwa **v2.2 / 30 页** 评审稿替代为输入；新稿不入库） |

## 设计原则（Albert）

**原生 macOS 视觉/UI 优先**，再适度叠加 D2 主题色。原生控件、层级、状态语义、浅深色与可访问性优先；**不为暖色/青蓝全面自绘**。D2 暖色 `#9C4F39` 仅作当前态主操作 tint。

## 本批已落地（代码，PR4）

- 系统 `windowBackground` / `controlBackground`；原生 `.bordered` / `.borderedProminent` + 状态表主操作
- 五摘要 / 五 Tab / 「复扫查看变化」；取消扫描 ≠ 停止监控
- 双任务文案：静态「监控：未运行」；停止即时反馈可「已停止监控，扫描仍在继续」
- **确认框（Nova 11:34 逐字）**：更换监控目录？ / 重建基线？；默认取消；有有效基线即确认重建；首次建立不弹
- **部分覆盖三卡标签**：基线扫描合计 / 当前可读合计 / 可比较逻辑变化；脚注禁止两总量直接相减；未知不作确定增删
- 「限制与错误」如实写退出无持久化；扫描失败/取消保旧结果，监控不自动停止
- 停止即时反馈仅「已停止监控」；扫描是否继续由实时扫描条/双任务派生（避免完成后残留）
- 有效基线后 F7 空闲稳定显示「监控：未运行」
- 扫描活动：系统 `ProgressView`，仅 `isScanning`；减少动态效果用静态符号（无自绘转盘/假比例）
- 窗口：`defaultSize(1120×760)`；无硬 `minWidth`/`minHeight`
- 包内默认 `marketing_version=0.1.1`；目标 tag **`v0.1.1-beta.1`**（本批不自动发布）

## Huluwa v2.2 · 30 页源码映射（摘要）

| 页 | 态 | 源码承接 |
| --- | --- | --- |
| 01–03 | 目录/缩略/组件板 | 参考；非运行窗 |
| 04–05 | F1 未选目录（05 深色代表） | `ContentView` 空态「选择要查看的目录」 |
| 06 | F2 已选无基线 | 空态「目录已选中，尚未读取」；主操作建立基线 |
| 07 | F2 首次建基线扫描 | `scanningState`「正在建立基线…」+ 取消 |
| 08 | F2 基线就绪未监控 | 主操作开始监控；摘要卡完整覆盖标签 |
| 09 | F3 采样过渡 | `isProcessSamplePending` 禁主动作 |
| 10–11 | F3/F5 监控中（11 深色代表） | 主窗基准态 |
| 12 | F4 监控中且扫描中 | 双任务 + 进度叠旧结果 |
| 13–15 | F4 监控未运行/停止即时 | 未运行 vs statusMessage 已停止 |
| 16 | F7 停止后有结果 | 结果只读 + 开始监控强调 |
| 17–19 | F6 失败/取消保旧 | `showingStaleAcceptedResults`；监控不自动停 |
| 20 | F6 部分覆盖 | 三卡改名 + 覆盖缺口行 |
| 21–26 | F5 空比较/进程不可得/四 Tab | 空态文案 + 既有 Table |
| 27–30 | 两确认框（深色代表） | `SessionPresentation` 逐字 + `confirmationDialog` |

深色页为代表性外观，跟系统 Dark，不另写一套。

## Liquid Glass（Albert 未闭合项）

- Apple：标准 SwiftUI/AppKit 控件在 **Xcode 26 / macOS 26 SDK** 下构建并在对应系统运行时，可自动获得 Liquid Glass；自定义可用 `glassEffect` / `NSGlassEffectView`（需 Swift 6.2+ 编译期可见）。
- 当前 CI：`macos-15` + **Xcode 16.4**；部署目标 **macOS 13 arm64**。现 SDK **无法**编译或虚报 `glassEffect` 支持。
- **状态：未闭合。** 路线是继续优先原生系统控件，待工具链升到可用 SDK 后再评估自动材料 / `#available`；本批不自绘仿玻璃，也不自行标「不采用/取消」。

## 验收边界

- Nova 目视关键页 ≠ 运行验收；Cook 技术 / Nova 产品 / Huluwa UI 正式验收前 **不合并、不发布**
- CI 绿 ≠ 同包实机；预览 merge SHA ≠ branch SHA ≠ 最终 main 包
