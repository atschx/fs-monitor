# UI 第一批交接（v0.1.1-beta.1）

本目录保存 Huluwa 首批可实施稿与本分支承接说明。**设计示意 ≠ 已发布；示例数字不可硬编码。**

## 资产

| 文件 | 说明 |
| --- | --- |
| `main-monitoring-light.png` | 监控中主窗 · 浅色 |
| `main-monitoring-dark.png` | 监控中主窗 · 深色 |
| `components.png` | 组件样式与尺寸板 |
| `fs-monitor-ui-handoff-v2_1f59.pdf` | PDF 交接 |

## 设计原则（Albert 11:18）

**原生 macOS 视觉/UI 优先**，再适度叠加 D2 主题色。原生控件、层级、状态语义、浅深色与可访问性优先；**不为暖色/青蓝全面自绘**，不用图标风格压过原生体验。D2 延续保留为辅（主操作 tint），具体色板微调等 Huluwa/Nova 同一交接。

## 本批已落地（代码）

- 系统 `windowBackground` / `controlBackground`；语义 `.primary` / `.secondary` / 系统绿红橙
- 原生 `.bordered` / `.borderedProminent`；主操作文案 **「复扫查看变化」** + D2 暖色 **tint**（非自绘按钮）
- 原生 segmented `Picker` 承载五 Tab 与排序；五摘要卡用系统卡片底，非全盘自定义色板
- 次级「停止监控」；既有状态条（失败/陈旧结果/采样中/覆盖缺口）保留
- 独立「取消扫描」与停止监控并存（既有能力，未改机制）
- 窗口：`WindowGroup.defaultSize(1120×760)` 仅为打开时建议尺寸；**无** `minWidth`/`minHeight` 硬下限（已移除本轮曾误加的 720×480；组件板 1368×872 亦非硬限制）
- 字体：系统动态字体样式（headline/caption/…）；卡片数值 `monospacedDigit`
- 包内默认 `marketing_version=0.1.1`；目标 Release/tag 约定 **`v0.1.1-beta.1`**（本批不自动发布）

## Nova 目视

Nova 已目视三图通过本批「监控中」逻辑方向；**不等于全量验收**。

## 待补（不擅定）

| 来源 | 缺口 |
| --- | --- |
| Nova | 完整 **v1.2 组合主操作 / 状态表** 尚未交接；未画状态不得猜新机制 |
| Nova | 目录选择子流程、基线建立引导、暂停/恢复等未交规则 |
| Huluwa | 菜单栏 / Dock / 更多空态与过渡动效（本批范围外） |
| Huluwa | 卡片内 D2 金属小图标资源是否单独交付（本批用系统符号 + 色板） |
| 产品 | 验收通过前 **不合并、不发布**；由 Cook 技术 + Nova 产品 + Huluwa UI 验收 |

## 对比度 / 可访问性

- 主操作：系统 prominent + D2 tint `#9C4F39`（交接板约 5.85:1）；其余按钮走系统 bordered
- Tab/排序：系统 segmented（系统浅深色与对比度）
- 身份珊瑚 `#BE7054` **不作**失败/监控状态色；监控用系统绿，错误用系统红

## Liquid Glass（研究结论，不阻断本批）

- Apple 文档：`glassEffect` / Liquid Glass 随 **macOS 26（Tahoe）SDK**、**Xcode 26** 提供；系统原生控件在用新 SDK 构建并在新系统运行时可自动获得材料。
- 当前 CI：`macos-15` + **Xcode 16.4** / Swift 6.1.2；部署目标仍为 **macOS 13 arm64**。
- **本批不调用** `glassEffect`、不自绘仿玻璃、不宣称 macOS 26/27 支持。若未来升 SDK，仅在 `#available(macOS 26, *)` 下评估，且不得压过原生优先原则。
