# Bug T6：分区模式下手牌段 / 牌库段跟不上实际区域变化

先读 `docs/tasks/_common.md`，再读 `docs/tasks/phase2-t1-zone-groups.md`（含执行结果与 review）。
这是 Phase 2 / T1 的 🎮 实战（2026-09-14）产出的两条反馈，合并成一本 bug 书。

## 症状（用户原话，2026-09-14 一局标准模式）

1. 「手牌段、牌库段会有很明显延迟，比如某个牌已经洗入牌库，或者从牌库抽出来，如帕奇斯的降落伞，这种行为无法稳定跟踪到。」
2. 「手牌段不能正确识别进入手牌的牌，或者延迟。比如某些发现出来的牌，或者牌库抽出来的。」

两条的共同点：**牌在区域间移动（牌库 ↔ 手牌，含生成 / 发现 / 洗入）时，分区不反映、或晚反映**。
「延迟」和「不显示」用户没法区分，所以两种都要查。

## 证据

- **那一局的 `Power.log` 已留存**：`~/Desktop/dev/HSTracker-logs/2026-09-14-phase2-t1-Power.log`（30 MB，含多局，`CREATE_GAME` 24 处；目标是 2026-09-14 22:38 之后的标准模式局）。**离线回放它是本任务的主要手段**，不靠再打一局。`HSTrackerTests/LogReaderTests.swift` / `PowerParserTests.swift` 有现成的日志驱动测试可参考。
- 本机 defaults：`show_player_get` **未设置（默认 false）**，`card_size = 1`，`highlight_cards_in_hand = 1`。
- review 侧的一条待验说法：`Player.cardsInHandByCardId` 把 `created || stolen` 的手牌交给 `createdCardsInHand`，而那一支受 `Settings.showPlayerGet` 控制（`Player.swift:450` 平铺路径同样如此）。降落伞、发现出来的牌都是 created。**这只解释「不显示」，解释不了「延迟」**，也可能不是全部原因 —— review 可能读错，独立复核后直说哪条不成立。
- 反馈 ①（2026-08-30）当时「延迟说」被探针反证（E2E p50 171ms），真因是 `highlightCardsInHand`。这次的「延迟」要同样拿证据说话：是刷新没触发、entity 的 tag 到得晚、还是分组读了错的字段。

## 硬约束

- 分组仍然是纯函数 + `Player` 上的属性，不变式（每个 cardId：牌库 + 手牌 + |已打出| == 已知张数；牌库段无 `count == 0`）继续由测试保证，改了定义就同步改测试和任务书里的表。
- 平铺路径（`playerCardList` / `opponentCardList` / `getDeckState()`）**仍然一行不动**。分区模式下 `showPlayerGet` 该不该继续起作用由你定，报告里给结论：它的字面是「显示我方获得的牌」，分区之后「手牌段」缺了生成牌就不是手牌段。
- 不动 `Game.swift` 的刷新调度（`updateTrackers` / 去抖）—— 除非你能用日志回放证明刷新确实没触发，那要单独写清楚，改法先报不动手。
- 不碰 UI（段头视觉是另一条反馈，另开）、不碰尺寸。
- `_common.md` 的规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/Logging/Player.swift`（只动 Phase 2 / T1 新增的那几段）
- `HSTracker/UIs/Trackers/SwiftUI/TrackerViewModel.swift`（如需）
- `HSTrackerTests/CardZoneGroupsTests.swift`；如需新增日志回放测试，新文件登记 pbxproj 4 处
- 其它文件要动先在报告里说明理由，不动手

## 验收

1. **先复现再修**：用留存的 `Power.log` 写一条会失败的测试，覆盖至少：生成牌进手（发现 / 降落伞类）、从牌库抽到手、洗入牌库；跑过后再修。修完这条测试和原 82 条全绿。
2. 受限环境 Debug build `BUILD SUCCEEDED`。
3. 报告里给出：两条症状各自的根因（带日志行号 / 代码位置）；「延迟」到底是哪一种；`showPlayerGet` 在分区模式下的最终语义；哪些症状你复现不出来（直说，别硬凑）。
4. 🎮 由用户再打一局看。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。
