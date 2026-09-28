# REFORK S6b-4：红龙搜索测试改确定性预算

计划见 `docs/REFORK.md` S7 行；通用约束见 `docs/tasks/_common.md`。

## 在哪干

分支 `dev0923`，worktree `.claude/worktrees/refork`。

## 现象

`RedDragonTests.testSearchReachesTableDamage` 的预算按线程 CPU 秒计（`RedDragonSearch.threadCPUTime`）。机器忙时测试线程多落在能效核，每 CPU 秒干的活少，
09-26 一次 480s 失败（23 行全 `budgetExceeded`，伤害不达表），空载时 162s 通过 —— 是不稳定测试，不是搜索回归。

## 目标

测试结果不随负载变：`RedDragonSearchConfig` 已有 `maxStatesExpanded`，让这条测试（以及同文件其它靠 `cpuBudget` 截断出结论的测试）改用展开状态数作预算，
CPU 预算放到不会先触发。cap 取多少要有依据（空载跑一次记 `statesExpanded`，留余量），写进测试注释一行。

## 约束

- 只改 `HSTrackerTests/RedDragonTests.swift`；`HSTracker/RedDragon/` 本体不动，不为变绿改被测代码。若发现本体必须改才做得到，停下写报告。
- 测试跑时长报告里给（`xcodebuild test -only-testing:HSTrackerTests/RedDragonTests`），目标不比现在慢。

## 验收

- 受限环境 `test` 里 `RedDragonTests` 24 条全绿，连跑两次结果一致；报告 cap 值、每条改动的理由、两次时长。
