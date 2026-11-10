# 远端分支清理记录

时间：2026-11-10（Cloud Agent 会话）  
对照基线：`main` = `9f1dab66bd46ea3c9586ebf80d89d03775d92988`

## 已删除（可恢复 SHA）

| 分支 | tip SHA | 判定 | 操作 |
| --- | --- | --- | --- |
| `cursor/macos-fs-monitor-app-0ddf` | `f0ba8708861d8b7a4139138f9334d5e566ece9a8` | 已是 `main` 祖先，ahead=0 | `git push origin --delete` |
| `cursor/pages-landing-e1bd` | `6d30d3af39900df0d57bc9ac50dabe7ad566d5d1` | 已是 `main` 祖先，ahead=0 | `git push origin --delete` |

恢复示例：

```bash
git fetch origin <sha>
git branch cursor/macos-fs-monitor-app-0ddf f0ba8708861d8b7a4139138f9334d5e566ece9a8
git push -u origin cursor/macos-fs-monitor-app-0ddf
```

## 保留

| 分支 | tip SHA | 原因 |
| --- | --- | --- |
| `main` | `9f1dab66bd46ea3c9586ebf80d89d03775d92988` | 默认分支 |
| `cursor/fs-monitor-cloud-env-0b93` | `2921df7121b480391b3e51033663683a34d9e699` | 独有提交 + 开放 [PR #2](https://github.com/atschx/fs-monitor/pull/2)（Linux Cloud Agent 环境；与「仅 macOS CI」新方向冲突，需人工决定关闭或改写，**未删**） |
| `cursor/docs-ci-app-release-e1bd` | （本轮工作分支） | 当前会话分支，未删 |

## 说明

- 未强推、未改仓库可见性。
- 删除前确认无未合并独有提交、非保护/默认分支、非本会话工作分支。
