# Bug T7：分区取数的三个边角错账（Codex review 2026-09-15）

先读 `docs/tasks/_common.md`，再读 `docs/tasks/bug-t6-zone-sections-stale.md`（尤其末节「Codex review」表，本书就是那三条）和
`docs/tasks/phase2-t1-zone-groups.md`。三条都在 Bug T6 新写的 `Player.zoneGroups` / `CardZoneGroups.make` 一带。

## 症状（Codex 原话的要点，已由 Claude 复核成立）

1. **同名副本洗入牌库时少算**：`CardZoneGroups.make` 牌库段用 `max(牌表 − 离开, 已知在库)`。两张原版未揭示（`listed = 2, left = 0`）+ 洗入一张同名（`known = 1`）→ 报 2，实际 3。
2. **控制权变化算错**：`entitiesThatLeftTheDeck` 走 `playerEntities`，按**当前**控制者过滤。我方从牌库抽出的随从被对手夺走后，从「离开牌库」里消失，牌库段当它还在；反过来夺来的对手随从被算进我方「离开牌库」，扣掉我方同名牌。
3. **定制 Zilliax 不归一**：牌表里是基础 id `CardIds.Collectible.Neutral.ZilliaxDeluxe3000`，抽到的实体是装饰模块 id，减法对不上，基础 Zilliax 永留牌库段。

## 线索（不是结论）

- 旧 `getDeckState()` 对 2 和 3 各有处理：`revealedEntities`（`Player.swift:251`，`isControlled || originalController == self.id`）；`Player.swift:790-797` 遇到装饰 id 就把基础 id 从牌表移除。**别把旧函数搬过来**，它对 `info.created` 的依赖就是 Bug T6 的根。
- 第 1 条最难：需要一个不依赖 `info.created` 的「这张是洗进来的副本、不是牌表那份」信号。候选：实体 `originalZone != .deck` 且当前 `isInDeck`；或 `info.created` 只在**当前在库**的实体上用（Bug T6 证明它对**抽出去**的实体不可信，对一直在库里的实体是否可信要你用回放 fixture 验证）。哪条成立用日志说话，都不成立就直说，报告里给理由。
- 回放 fixture `HSTrackerTests/Fixtures/ZoneReplay/2026-09-14-standard.log` 里有降落伞洗入（不在牌表，不触发第 1 条）；第 1 条要么造单元测试，要么从 `~/Desktop/dev/HSTracker-logs/2026-09-14-phase2-t1-Power.log` 别的局里找同名洗入的片段。

## 硬约束

- 只动分区路径：`CardZoneGroups` 与 `Player` 上 Bug T6 新增的那几个私有取数。`playerCardList` / `opponentCardList` / `getDeckState()` 一行不动；不动 `Game.swift`。
- 不变式照旧：每个 cardId 牌库 + 手牌 + |已打出| == 已知张数；牌库段无 `count == 0`。改了定义同步改测试。
- 对手侧的 `hidden` 过滤（不泄露未揭示的对手牌库）保住。
- 三条各至少一条测试，**先失败再修**。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/Logging/Player.swift`（只动 Bug T6 新增段）
- `HSTrackerTests/CardZoneGroupsTests.swift`、`HSTrackerTests/ZoneGroupsReplayTests.swift`；新增 fixture / 文件登记 pbxproj

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；测试原 100 条 + 新增全绿。
2. 报告里：三条各自的修法与依据；第 1 条用的「洗入副本」信号是什么、用什么证明它可信；哪条修不了或只修了一半。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。
