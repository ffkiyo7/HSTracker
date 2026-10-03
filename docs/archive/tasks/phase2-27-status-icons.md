# Phase 2 / 2.7：卡条右端状态图标 + 套牌外的牌进已打出段

先读 `docs/tasks/_common.md`，再读 `docs/archive/tasks/` 里 `bug-t6` / `bug-t7` / `bug-t8` / `bug-t9` 四本（三段定义、不变式、已证伪的信号），
`perf-p2-vector-rows-compositing-cost.md` 的「缓存键与失效」一节，`docs/research/firestone-overlay.md` 第四节（卡条结构）。

## 要什么（用户，2026-09-30）

1. **套牌外的牌进已打出段**。发现 / 生成进手牌、再从手牌打出的牌，现在打出后就从记牌器消失（已打出段只收 `originalZone == .deck` 的实体）。
   用户定：**从手牌打出的算正常打出**，进已打出段。上游 `Player.cardsPlayedThisMatch`（`Player.play`）记了每张从手牌打出的牌，可用可不用。
2. **卡条右端状态图标，按 Firestone**：卡条最右侧，从左往右 **先数量、再图标**。
   - **礼物**：套牌外的牌（发现 / 生成 / 偷来的），三段都标。**替掉现在左上角的小折角**（`createdMark`）。
   - **骷髅**：已打出段里进了坟场的牌。
   - **烧毁**：已打出段里没被打出就离开的牌 —— 被弃、被撕、爆牌、牌库里被炸（Bug T11 那类）、被对手偷走。
   - **传说星**：同理占图标位；张数 > 1 时显示数字，不显示星（现有 `countBox` 的规则）。
   - 同一 cardId 若分属不同状态（如一张进坟场、一张被弃），拆成不同行，每行张数只数自己那种。
3. 这是原 2.7（09-23 用户反馈「分不清被消灭和进坟场的随从」）的实现，礼物图标是这次补的。

## 默认值（用户没拍板的，按这个做，报告里单列出来让用户改）

- 一行最多 数量或★ → 礼物 → 状态 三格；礼物和骷髅 / 烧毁可同时出现（来源和去向是两件事）。
- 骷髅 = 此刻在坟场；已打出但还在场上（随从在场、武器装备中、奥秘挂着）不带状态图标。
- 对手侧与我方同一套规则，但不得泄露隐藏信息（对手没公开的牌不进任何段、不带任何图标）。

## 硬约束

- **套牌外的判定不能靠 `info.created`**：游戏在牌还在牌库时就揭示它，普通抽牌大多被标 created（Bug T6）。现在手牌段的礼物行就是按 `info.created || info.stolen` 分的，这次一并改对；判定依据写进报告。
- 不变式扩展后仍成立：每个 cardId，牌库 + 手牌 + |已打出| == 牌表 + 洗入 + 套牌外进过我方手牌 / 场上的份数；每个实体恰好落一段；段头合计 == 该段画出来的行张数之和。
- 衍生物（直接召唤上场、没进过手牌的）不进已打出段；英雄、英雄技能、附魔不进任何段。
- 图标自绘（SwiftUI 形状）或用 SF Symbols；**不得拷 Firestone 的代码或 SVG**（仓库无许可证）。尺寸在现有 21 px 行网格内，名字区为图标让位时照旧省略号截断。
- 行的任何可见状态变了，位图缓存必须重画（Perf P2 的键）。
- 平铺模式（`group_cards_by_zone` 关）和 `getDeckState()` 一行不动。
- 现有测试不改期望；不变式和新状态各自有测试（`CardZoneGroupsTests` / `ZoneGroupsReplayTests` 那套）。

## 可改的文件

`HSTracker/Fork/PlayerCardZones.swift`、`HSTracker/UIs/Trackers/SwiftUI/` 下的文件、`HSTrackerTests/` 下的分区 / 卡条测试（可新增测试文件，新 `.swift` 按 `AGENTS.md` 登记 `project.pbxproj`）。
行状态若非在上游 `Card` 上加字段不可，允许最小改 `HSTracker/Database/Models/Card.swift`（含 `copy()`），报告写行数和理由。其他上游文件不动，需要就写进报告。

## 验收

- 受限环境 `build` 过；`test -skip-testing:HSTrackerTests/LocalizationFormatTests` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 外全绿，报告总条数。
- 报告：套牌外 / 各状态的判定依据（哪个 tag / 哪个闩）；不变式怎么扩的；动了哪些上游文件多少行；默认值三条的落法；按规则没动的问题。
- 🎮（由人做）：一局带发现的牌组 —— 发现的牌在手牌段带礼物、打出后进已打出段；弃牌 / 爆牌 / 被偷带烧毁；死掉的随从 / 用掉的法术带骷髅；多张时数字在图标左边；单张传说有星、两张以上只有数字。

## 执行结果

09-30 第一轮（Opus 子代理）：`build` 过，`test` 337 条只挂签名 1 条（新增 13）；改 `PlayerCardZones.swift`、`CardRowView.swift`、`TrackerBarStyle.swift`（自绘礼物 / 骷髅 / 火焰）、`TrackerRowRaster.swift`、`TrackerCardListViewModel.swift`、上游 `Card.swift` +2（`zoneStatus`）。
判定：礼物 = T8 / T9 闩 ∨ `originalZone != .deck` ∨ 原控制者是对方；从手牌打出 = id ∈ `cardsPlayedThisMatch` ∪ `spellsPlayedCards`；烧毁 = 未打出且（`info.discarded` ∨ 不归自己控制）；骷髅 = 其余且在坟场。
默认值落法：图标不随行变暗；小折角在平铺模式也换成右端礼物。

review（我读 diff + Fable 核对员 + Codex gpt-6-astra）打回，第二轮要修：
- **必修**
  1. 进过我方手牌、没被「打出」就上场的礼物（被肮脏的鼠辈拉出、手里被触发施放）三段都不在，死后也不在（Codex + Fable A）。
  2. 对手发现的奥秘：打出时 cardId 未公开，`spellsPlayedCards` 不收，公开后也进不了已打出段（Codex）。
  3. 打出 → 弹回手 → 被弃，显示骷髅不显示烧毁（Codex + Fable D）。实现者给的「打出优先」理由不成立：从牌库发现残留的 `discarded` 在 `zoneChangeFromOther` / `createInDeck` 已清掉（Fable 核过）。
- **顺手**
  4. 礼物洗回牌库后在牌库里被炸 / 爆牌，三段都不在（Fable B）。
  5. 没被 T8 闩到的洗回礼物（如幸运币），在牌库段不带礼物图标，与另两段判法不一致（Fable C）。
  6. 一次刷新约 9 次全表扫描，`leftDeck` 已算出却没往下传（Fable E）。
- **不修，记着**：直接生成进奥秘区的印记 / 目标会被当成从手牌打出（`Game.playerSecretPlayed` 不看来源区，极少见）。

09-30 第二轮（同一实现者）：6 条全修，只动 `PlayerCardZones.swift` + `CardZoneGroupsTests.swift`（新增 5 条，修前全红）；`test` 342 条只挂签名 1 条。
- 「进过手牌」判据改为 `originalZone == .hand` ∧ 原控制者是自己（首次落区写一次，与怎么离开无关），打出 / 弃牌列表只兜底后来才进手的礼物。修掉 1 / 2 / 4。
- `info.discarded` 优先于打出过（两处清标记路径实现者复核属实）。修掉 3。
- 牌库段礼物数改为 `isFromOutsideTheDeck` 计数：牌表份 = max(牌表还欠的, 已知在库 − 礼物) + 礼物。修掉 5。
- 一次刷新只扫一遍 `revealedEntities`。修掉 6。
- 连带改动：`isSideboardCopy` 加按 setup 备牌 cardId 认，守住 T9 测试；别的效果生成同 id 牌也会被排除，极少见。
- 残留：套牌外的牌走「手牌 → 备用区 → 手牌」，上游不清 `discarded`，之后打出会显示烧毁。

第二轮 Codex 复核打回 4 条必修，第三轮要修：
- ① 按 cardId 认备牌会把同名的独立发现牌藏起来。撤掉；新口径是 E.T.C. 选中的牌进过手、再被打出，按礼物进已打出段（改 T9 实体 186 期望）。
- ② `discarded` 残留：`TagChangeActions.swift:1371` 离手置位，`:1159` 只清 `originalZone == .deck`。
- ③ 手牌变形替换（恶魔计划，`2026-09-20-bug-t11.log:7564`）的旧礼物实体进了已打出段；这条路径也走 `handDiscard`，与 TNT 销毁要分开。
- ④ 弹回手的衍生物被鼠辈拉上场会消失。
- 用户 09-30 同意两条口径：
  - E.T.C. 选中的牌进过手再打出 → 礼物进已打出；setup 时就在备牌区、没进过手的不进任何段。
  - 被变形换掉的旧实体：礼物不进任何段；牌表牌留在已打出、无图标。

09-30 第三轮：4 条全修，只动 `PlayerCardZones.swift` + 两个测试文件，新增 6 条；`test` 348 条只挂签名 1 条。我读 diff 过，待 🎮。
- ① `isSideboardCopy` 整个删，只排除 `wasSetAsideAtSetup` 原件。改了 3 条现有测试：
  - T9 实体 186 改为礼物进已打出；
  - 第一轮的备牌测试改名并反转期望；
  - 第二轮「弹回再弃」测试补了真实对局会有的 `boardToHand` 一步（期望不变）。
- ② 打出过的牌，只在之后 `info.returned`（`Player.swift:874/887/1186`）时 `discarded` 才算烧毁。
- ③ 此刻在备用区且没打出过 = 被替换：礼物不进任何段，牌表牌无图标。
  - 夹具依据：恶魔计划 74 号 7564 行进备用区后一直留着；TNT 72 / 79 号路过备用区，停在坟场（16610 / 38553 行）。
  - 回放测试 `testACardReplacedInHandHasNoStatus` 修前的红没拿到（宿主崩溃），靠同路径单测证明。
- ④ `hasBeenInHand` 加 `info.returned`。
- **残留，不修**：
  - 从对方手里拿来的牌没打出就被拉上场，三段都不在（要改上游解析层）；
  - `returned` 是永久标记，洗回过牌库的礼物之后「备用区 → 回手 → 打出 → 死」判烧毁；
  - 场上衍生物被洗进牌库后在库里被炸，显示礼物 + 烧毁；
  - 牌库牌被永久移进备用区显示无状态。

09-30 用户看展示页（artifact「记牌器状态图标」）后定：右端每格同宽、图标同大。
- 格宽统一用 `boxWidth` 20（删 `iconSlotWidth` 15）；星与三个图标统一用 `rowIconSize` 11（删 `starSize` 10）。
- 卡名右留白 = 格数 × 20 + 4，三格时卡名区约剩 79 参考像素。
- `test` 348 条只挂签名 1 条。

10-04 用户确认可提交，`7dbc86b1`。

- **另记**：测试宿主启动时 `AnomalyGuideMulliganTriggerView.swift:78` 解包 nil 的 `coreManager` 崩一次，xcodebuild 自动重启后全过，退出码 65（上游 3.6.13 带来，与本任务无关）。
