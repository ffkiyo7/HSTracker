# REFORK S6a：非界面小件

计划见 `docs/REFORK.md` S6；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。S6 拆两半：本书是不碰设置页 / 弹窗界面的小件；局末小结、Trackers 设置页、翻译余项在 S6b，等 S3–S5 实测后再做。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`（上游 `3.6.12` + 已提交的 S1–S5、第二批修复、S7）。改动只落在这里。
- 主仓库（分支 `dev`）只读，是旧实现的来源：`git show dev:<path>`、`git show <commit>`。

## 目标

dev 上下面这些修复 / 小功能，逐项先看 3.6.12 有没有已经解决；没解决的在新线上落地，已解决的给出依据不搬。

| 项 | dev 来源 |
|---|---|
| 排队时显示牌组记牌器 + 进队列清上一局残留 | `c5e125c2` |
| 场景门：不在对局里就不显示记牌器 / 水晶上限 / 计数器 | `381a9c80` |
| watcher 回调不在后台线程写 SwiftUI view model（Bug T1） | `ac116be0` |
| 炉石退出后不再把 `Power.log` 截成 0 字节 | `f08de7d3` |
| Dock 选牌有反馈（打勾 + Toast）、菜单栏按 tag 定位（中文界面下按标题找会失效）、`HSReplayPreferences` 标题本地化 | `35fea72a` 中除 Trackers 设置页以外的部分 |
| 与上游的默认值差异（dev `docs/PLAN.md`「与上游的默认值差异」表里仍适用的键） | 同表 |

## 约束

- 3.6.12 相关代码与 dev 基座差异大（如 `LogReader` 截断逻辑已重写、`Watchers` 已部分修过）：以 3.6.12 现状为准重新落地，不 apply 旧 diff。
- 对上游文件的改动越少越好；fork 自有逻辑放 `HSTracker/Fork/`。
- 线程与时序遵守 `AGENTS.md`「线程与时序」；`QueueEvents.isInQueue` 的读者不得在对局路径上。
- 本任务允许改 `project.pbxproj`（文件登记）；允许在 `.xcstrings` **新增本任务代码实际用到的 fork key**，英文与 zh-Hans 取自 dev 同名 key，不改已有 key，过 `check_xcstrings.py`。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 外全绿，报告总条数。
- 报告：每项一句话结论（搬 / 改写 / 上游已解决 / 放弃 + 依据）；上游文件改动清单与行数；需要 🎮 实机看的点（排队、退出炉石、回菜单各一次）。

## 执行结果

（执行者追加）
