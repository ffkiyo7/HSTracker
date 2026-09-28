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

## 执行结果

✅ 09-28 Opus 子代理完成，`dev0923` `b12ead8c`；Claude 加了一条断言。只改 `RedDragonTests.swift`。
- `searchStateCap = 400_000`：空载 Debug 实测 49 行最多 255,446 态（t1-48p-07，7.3 CPU 秒），约 1.6 倍余量，≈ 旧 12s CPU 预算空载时的展开量。`cpuBudget` 放到 600 只作兜底。
- 每行加 `XCTAssertNotEqual(result.termination, .budgetExceeded)`（核对员建议）：撞顶单独报，不与伤害不达表混。
- 另三条带 `cpuBudget` 的测试没改：`testDeterminism` 本来就按状态数；两条缺件测试只展开 2–3 态即 `exhausted`，结论不靠截断。
- 三次跑（改前 / 改后两次 + 加断言后一次）24 条全绿，约 161–163s，与改前持平；49 行全 `reachedUpperBound`。
- 本体发现未动：`findMissingPieces` 子搜索的 `per` 预算仍按 CPU 秒，测试走不到；T2 时一起看。
