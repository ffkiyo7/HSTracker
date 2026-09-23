# REFORK S3：分区数据层

计划见 `docs/REFORK.md` S3；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`（上游 `3.6.12` + 已提交的 S1 构建层、S2 翻译）。改动只落在这里。
- 主仓库（分支 `dev`）只读，是旧实现的来源：`git show dev:<path>`、`git log master..dev`。
- worktree 没有 `AGENTS.md` / `docs/`，规则以主仓库 `dev` 上的为准。

## 目标

把「记牌器按牌库 / 手牌 / 已打出分区」的数据层搬到新线：纯数据与判定，**不含任何界面**（面板是 S4）。分区结果要能被测试直接验证。

## 来源

dev 上相关提交：`1c44b212`（T1 分区）、`e9a67db6` / `7bd3192b` / `68ccc14e` / `04dae47a`（Bug T6–T10）、`f8fa4c86`（T11 护栏测试）、`d309a8ff`（分区逻辑搬出 `Player.swift`）、`143db6f3` 的数据层部分（`Player` 的单次取数、`RealmHelper.needsCardCountFix`）。另外两个独立修复：`9ab2f0cd`（`Card.copy()` 补拷 `enText`）、`999f2eee`（Bug T3：`predictFabled` 只在实体由对手控制时写入）。

判断一处改动属不属于本任务，看它是不是「分区取数 / 判定」或上面两个修复；界面、刷新调度、设置页都不属于，发现了写进报告。

## 约束

- fork 自有逻辑放 `HSTracker/Fork/`；对上游文件的改动越少越好。`Player.swift` 相对 `3.6.12` 的改动 ≤15 行（为此可以放宽 `Player.game` 的访问级别）。
- 3.6.12 的 `Player` / `Game` / `Entity` / `TagChangeActions` 相对 dev 的基座（3.6.9）改动很大：以 3.6.12 现状为准重新落地，不要把 dev 的旧版本整段覆盖过来。
- 新 `.swift` 手工登记 `project.pbxproj`（`AGENTS.md`「构建」：4 处，漏了不报错）；fixture 登记进测试 target 的资源。本任务允许改 `project.pbxproj`，只做文件登记。
- 不改 `.xcstrings`。

## 验收

- 受限环境 `clean build` 过（S1 之后受限环境可用）。
- 受限环境 `test`：`CardZoneGroupsTests`、`ZoneGroupsReplayTests` 全绿；其余与 S2 后基线一致（151 条中只允许 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 失败，`LocalizationFormatTests` 若因系统权限读不到 catalog 失败要写明）。报告总条数。
- `git diff 3.6.12 --stat -- HSTracker/Logging/Player.swift` ≤15 行。
- 报告：每个来源提交的处理结论（搬 / 改写 / 已被上游取代 + 依据）；被改动的上游文件清单与各自行数。

## 执行结果

（执行者追加）
