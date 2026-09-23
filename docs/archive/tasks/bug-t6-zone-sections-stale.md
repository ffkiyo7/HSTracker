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

## 执行结果（2026-09-15）

### 先复现：离线回放

留存日志里 **2026-09-14 23:13:38 那局标准模式**（`Power.log` 78456–86156 行，恶魔猎手，
带飞行员帕奇斯 `VAC_933`）按 `LogReaderManager` 的过滤条件（`GameState.` / `PowerTaskList.DebugPrintPower` /
`PowerProcessor.EndCurrentTaskList`）原样截到「打幸运币」那一拍，落成
`HSTrackerTests/Fixtures/ZoneReplay/2026-09-14-standard.log`（6472 行 / 764 KB），
由 `HSTrackerTests/ZoneGroupsReplayTests.swift` 喂给 `PowerGameStateParser` 重放。
牌表用整局里被揭示过的 13 张（未揭示的 17 张在回放窗口内不出牌库，不影响任何断言）。

**只喂 `GameState.` 一路是不够的**：第一版 fixture 丢掉 `PowerTaskList` 后，起手牌的
`info.hidden` 停在 `true`、部分实体 `info.originalController` 停在 0，和线上不一致。
两路都喂之后 `originalZone` / `hidden` / `originalController` 才和线上对得上，故 fixture 保留两路。

四个检查点（帕奇斯出牌前 / 黑暗贿赂前 / 邪能学说前 / 复制出的怒缚蛮兵出牌前）上，修之前的实际输出：

| 检查点 | 手牌实体 | 手牌段 | 牌库段里不该在的 |
|---|---|---|---|
| 1（第 2 回合） | SW_039 / SW_041 / VAC_933 / SCH_702 / JAIL_206 / TTN_COIN2 | 只有 SW_039 / SW_041 / VAC_933 | SCH_702、JAIL_206 |
| 2 | BT_753 / SCH_702 / MAW_014 / SW_037 / TTN_COIN2 | **空** | BT_753、SCH_702、JAIL_206、MAW_014、SW_037×2、VAC_928 |
| 3 / 4 | 3~6 张 | **空** | 同上 |

### 两条症状的根因

**共同根因：`EntityInfo.created` 对我方绝大多数正常抽牌也是 `true`。**
炉石在把牌从 DECK 挪进 HAND 之前先 `SHOW_ENTITY` 揭示它（fixture 4165 行的降落伞、
1272 行的邪能学说都是这个形状），HSTracker 在这条路径上把 `created` 打上了
（`Player.createInDeck` 的 `created || turn > 1`，以及 `TagChangeActions.zoneChangeFromOther` 的
`entity.info.created = true`）。回放里第 2 回合起抽到的牌 100% 带 `created=true`。

1. **症状 ②「手牌段不认进手的牌」**：`Player.cardsInHandByCardId`（`Player.swift:618`，Phase 2 / T1 新增）
   把 `created || stolen` 的手牌全部交给 `createdCardsInHand`，而那一支受 `Settings.showPlayerGet` 控制
   （本机默认 false）。因为上面那条，这不只漏掉发现 / 生成牌，**第 2 回合之后手牌段直接是空的**。
   review 侧的待验说法方向对，但低估了范围：它只解释「发现出来的牌」，实际连普通抽牌一起漏。
   用户原话里的「或者牌库抽出来的」正是这一半。

2. **症状 ①「牌库段跟不上」**：`getDeckState()` 的 `revealedNotInDeck`（`Player.swift:711`）要求
   `!info.created || originalEntityWasCreated == false`，所以这些被误标 created 的牌**永远不从
   `originalCardsInDeckIds` 里扣掉** —— 抽走、打出之后仍留在 `remainingInDeck`，分区之后就是
   「牌库段里躺着我早就抽走的牌」。`getDeckState()` 是平铺路径，按任务书一行没动；
   分区改成不再读它。

3. **「延迟」是哪一种**：不是刷新没触发，也不是 tag 到得晚 —— 回放是同步喂日志的，
   每条断言都是「这一行喂完立刻取值」，仍然错。**是分组读了错的字段**（`info.created`），
   状态一旦被误标就再也不回来，所以看起来像「一直不更新 / 偶尔才对一次」。
   `Game.swift` 的刷新调度一行没动。

### 修法

分组不再问「这张牌是不是生成的」，只问**实体现在在哪个区**：

- `CardZoneGroups.make` 换签名：`deckList` / `knownInDeck` / `predictedInDeck` / `cardsInHand` /
  `leftDeck` / `inHandFromDeck`。
  - 牌库段 = `max(牌表张数 − 离开牌库的张数, 当前牌库里已知的张数)`。
    取 `max` 是为了让「洗进来的副本」不被牌表那份吞掉（降落伞、以及复制自牌表的牌）。
  - 手牌段 = 手上全部有 cardId 的实体，created / 非 created 分行（礼物图标语义保留）。
  - 已打出段 = 离开牌库的张数 − 其中还在手上的张数，写成负 `count`（暗条形态不变）。
- `Player` 侧新增三个私有取数：`knownCardsInDeckZone`（牌库区里有 cardId 的实体；对手侧额外滤掉
  `info.hidden`，不泄露）、`cardsThatLeftTheDeck` / `cardsInHandFromDeck`
  （`originalZone == .deck && !isInDeck` 的实体）。`playerCardGroups` / `opponentCardGroups`
  改走同一个 `zoneGroups(deckList:)`，**不再调用 `getDeckState()` / `getOpponentDeckState()`**。

修完同样四个检查点：手牌段逐张等于手牌（含幸运币）、牌库段随抽牌递减、
降落伞 6 → 3、已打出段还多出「抽掉的 3 张降落伞」。

### `showPlayerGet` 在分区模式下的最终语义

**分区模式下手牌段完全不读它**（平铺路径照旧读，一行没动）。两条理由：

1. 字面上它是「显示我方获得的牌」，那是给**一张平铺表**用的开关 —— 表里说不出位置，
   才需要一个开关决定要不要把礼物混进去。分区之后「手牌段」缺了任何一张手牌就不是手牌段。
2. 更实际的一条：`info.created` 对我方**不可用作过滤条件**（见上），拿它当门就等于随机丢牌。

礼物图标没丢：手牌段仍按 `created` 分行并置 `card.isCreated`，`CardRowView` 照旧画礼物角标。
`highlightCardsInHand` / `removeCardsFromDeck` 维持 T1 的结论（分区模式下都不参与）。

### 复现不出来 / 按规则没动的

- **「延迟」本身复现不出来。** 回放是同步的，观察到的全部是「一直错」，不是「晚一拍才对」。
  用户看到的延迟感，我判断就是上面那条「一旦误标就不回来」的表现；要真证伪「刷新晚了」
  得挂探针打一局，本次没做。
- **生成牌打出后进不了已打出段**（比如邪能学说复制出来的怒缚蛮兵 id=116）：它的
  `originalZone == .hand`，从来没在牌库里待过，`leftDeck` 抓不到它。这和平铺路径现状一致，
  属于 2.7「已打出段形态」的范围，没做。
- **`getDeckState()` 把抽走的牌留在 `remainingInDeck` 是平铺路径的真 bug**（上游带来的）：
  平铺表里表现为「抽到手上的牌仍是满张数的正常行，只是名字变绿」，正是 2026-08-30 反馈 ① 的原始现象。
  按任务书 `getDeckState()` 一行不动，只在分区路径绕开。**要不要连平铺一起修，请示下。**
- `DynamicEntity.init` 收了 `extraInfo` 参数却没赋值（`Player.swift:18`，上游遗留），
  所以按 `extraInfo` 分组其实不生效。沿用现状写法，没动。
- fixture 764 KB 偏大。想瘦身只能砍掉检查点，或者接受「只喂 `GameState.`」带来的失真，两条都不划算。

### 验收

- `xcodebuild … clean build`（受限环境）：`** BUILD SUCCEEDED **`
- `xcodebuild … test`（受限环境）：`** TEST SUCCEEDED **`，`Executed 90 tests, with 0 failures`
  （原 82 + `CardZoneGroupsTests` 新增 3 + `ZoneGroupsReplayTests` 5）
- `project.pbxproj`：新增 `ZoneGroupsReplayTests.swift`（Sources 4 处）和
  `2026-09-14-standard.log`（Resources 4 处），本次 pbxproj 只有这两类改动。
- 🎮 待用户再打一局：重点看手牌段是否逐张等于手牌、牌库段是否随抽牌递减、
  洗入牌库的牌（降落伞类）在牌库段的计数是否跟着掉。

## review（Claude，2026-09-15）通过

逐行核对了 `Player.swift` 的 diff、两个测试文件和 pbxproj 的 8 处登记，自己跑了受限环境 `test`：90 / 90 全绿。

- 根因成立：`info.created` 在 SHOW_ENTITY 先于 DRAW 的路径上被打到普通抽牌上，任何拿它当门的分组都会漏。改成按实体当前区域计数是对的方向，也顺带把 review 侧「只有发现牌漏」的说法纠正了。
- `getDeckState()` / 平铺路径确认一行没动；`Game.swift` 没动，「延迟」被证实为「一旦误标就不回来」而非刷新晚。
- 一处已知局限记下：牌库段 `max(牌表 − 离开, 已知在库)` 在「牌表卡还有副本未揭示 **且** 同名生成副本被洗入」时会少算，原因还是 created 不可信；实战里罕见，等 2.7 再看。
- 测试文件头注释原写「丢掉 PowerTaskList」，与执行结果和 fixture（2919 行 PowerTaskList）矛盾，已改准。
- 平铺路径的 `getDeckState()` 同源 bug 要不要修，交用户定。

## Codex review（gpt-6-astra / medium，2026-09-15，范围 `f08de7d3...e3797ba8` 整批）—— Claude 复核：3 条全部成立

| # | Codex 的发现 | 复核 | 触发条件 |
|---|---|---|---|
| 1 | `CardZoneGroups.make` 牌库段 `max(牌表 − 离开, 已知在库)`：两张原版未揭示 + 洗入一张同名 → 报 2，实际 3 | ✅ 成立，即上面 review 记的已知局限，Codex 给了具体反例；现有测试只覆盖三张全已知的情况 | 同名副本洗入牌库 |
| 2 | `entitiesThatLeftTheDeck` 走 `playerEntities`（按**当前**控制者过滤）：我方牌被夺走后从「离开牌库」消失 → 牌库段当它还在；夺来的对手随从反向扣我方同名牌 | ✅ 成立。旧 `getDeckState()` 走 `revealedEntities`（`isControlled || originalController == self.id`）就是为此 | 心灵控制类换控制权 |
| 3 | 定制 Zilliax：牌表是基础 id `ZilliaxDeluxe3000`，实体是装饰模块 id，减法对不上，基础 Zilliax 永留牌库段 | ✅ 成立。旧路径 `Player.swift:796` 遇到装饰 id 就把基础 id 从牌表移除，新路径没有等价处理 | 牌组带定制 Zilliax |

三条都在本片新增的分区取数里，修法方向：2 改按 `originalController`；3 在 `zoneGroups` 入口做一次 id 归一；1 需要一个不依赖 `info.created` 的「洗入副本」信号（`originalZone != .deck` 且当前在库？待验）。**未动代码，等用户定排期。**
