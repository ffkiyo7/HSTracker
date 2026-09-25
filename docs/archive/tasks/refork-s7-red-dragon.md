# REFORK S7：红龙搬到新线

计划见 `docs/REFORK.md` S7；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`（上游 `3.6.12` + 已提交的 S1–S5 与第二批修复）。改动只落在这里。
- 主仓库（分支 `dev`）只读，是旧实现的来源：`git show dev:<path>`、`git diff master dev -- <path>`。

## 目标

dev 上的红龙搜索核心（`HSTracker/RedDragon/`）与其测试、fixture 在新线上编得过、测得过。只搬核心，不做任何界面（红龙 overlay 是回主线后的事）。

## 来源

`0a921d6b`（spike T1 搜索核心）；dev 相对 master 在 `HSTracker/RedDragon/`、`HSTracker/Hearthstone/CardIds/`、`HSTrackerTests/RedDragonTests.swift`、`HSTrackerTests/Fixtures/RedDragon/` 下的全部改动。`docs/research/` 的调研文档留在 dev，不进新线。

## 约束

- 3.6.12 的 `CardIds` 与 dev 基座不同：以 3.6.12 现状为准只补红龙用到而缺的常量，不整文件覆盖。
- 本任务允许改 `project.pbxproj`（文件登记、fixture 进测试 target 资源）。不改 `.xcstrings`。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 外全绿，`RedDragonTests` 在内，报告总条数。
- 报告：搬了哪些文件；对上游文件（`CardIds` 等）的改动清单与行数；与 dev 版本有差异的地方及原因。

## 执行结果

09-24 `dev0923` `aae3f397`：9 个文件与 dev 逐字节相同，未用 `CardIds`（REFORK 原写需补常量有误）。全套 289 条，`RedDragonTests` 24 条全绿。
- 执行者那一轮全套跑了 7 小时未结束（采样在 `testSearchReachesTableDamage` 的搜索里），由 Claude 停掉接手；次晨单条 162s、全套 4 分钟正常，未复现。
- 09-26 另一轮全套里该条 480s 失败（23 行全 `budgetExceeded`），当时炉石开着、负载 5–6.5：预算按线程 CPU 秒计，忙时落能效核 → 不稳定测试，改法归 S6b。
