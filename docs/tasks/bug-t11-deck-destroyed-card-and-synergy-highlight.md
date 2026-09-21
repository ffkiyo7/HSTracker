# Bug T11：牌库里被炸掉的牌仍显示在牌库段；关联卡牌高亮失效

先读 `docs/tasks/_common.md`，再读 `bug-t8-shuffled-copy-drawn-stays-in-deck.md`、`bug-t10-deck-section-count-disagrees.md`
（两本的「执行结果」都要看）。两条症状互相独立，分开查、分开报告，**不要假定同一根因**。

## 症状（用户原话，2026-09-21，实测的是 09-20 22:19 从 Xcode build 的 Debug 包，含 `04dae47a`）

1. 「计数错账没有修好，比如被对面的爆破工头洗进去的炸弹炸掉的牌，还显示在牌库中。」
2. 「关联卡牌高亮失效了，不知道是什么原因。」

## 已有的事实（只到这一步，根因你查）

### 第 1 条

- 日志：`~/Desktop/dev/HSTracker-logs/2026-09-20-bug-t11-Power.log`，第 **217808 ~ 234611** 行那一局
  （狂野天梯，本地玩家 `F1zz` = PlayerID 2，对手的爆破工头索格伦 `WW_372` 洗入 TNT 炸药 `WW_372t`，实体 214~219）。
- 23:41:27 我方抽到 TNT（id=215），`TRIGGER` 块里：手牌的混乱吞噬（id=72）`HAND → SETASIDE → GRAVEYARD`；
  **牌库里的嫉妒乐章（id=202，`ETC_085t`）`SHOW_ENTITY` 后直接 `DECK → GRAVEYARD`**。
- id=202 的来历：罪孽交响曲（id=61，`ETC_085`）打出时 `FULL_ENTITY` 建在 `SETASIDE`（带 `CREATOR=61`），
  随后 `HIDE_ENTITY … ZONE=DECK` 入库。不在牌表里。
- 这一局里「从牌库直接进墓地」只有这一次，23:41:47 对局就结束了；用户说的「比如」意味着别的局也可能有，
  同一份日志共 36 局、`WW_372t` 出现多次，自己翻。
- 我**没有**回放验证过分区取数在这一刻吐出什么 —— 是数据错还是画面旧（T10 那一类），你先判定，报告里给回放读数。

### 第 2 条

- 开关都开着：`player_highlight_synergies = 1`、`use_swiftui_tracker = 1`。
- 静态读过一遍没找到断点：`Tracker.highlightPlayerDeckCards` → `setSwiftUIHighlight` → 四个列表的
  `TrackerCardListViewModel.setHighlight` → `TrackerCardRow.highlight` → `CardRowView.highlightColor`；
  `CardRowRasterKey.highlight` 在键里，`CardRowView.==`（T10 加的）也走这个键。入口有三个：记牌器行悬停
  （`Tracker.hover`）、游戏内大卡悬停（`Game.onBigCardChange`）、发现界面（`Watchers.onDiscoverStateChange`）。
- 用户没说是哪个入口失效、是全部牌还是个别牌。**上一次确认高亮正常是什么时候不清楚**，
  嫌疑区间至少覆盖 V1（`e3797ba8`）→ V2a/V2b（`1745adfa`）→ Perf P1/P2（`143db6f3`）→ T10（`04dae47a`）。
- 要求：找到真正的断点并拿出证据（测试先红），不要凭上面这条链「看起来通」就下结论；
  查不到就直说查到哪、排除了什么。

## 硬约束

- T6 ~ T10 的不变式和护栏测试全部继续绿；`playerCardList` / `opponentCardList` / `getDeckState()` 不动，平铺模式行为不变。
- 上游解析路径**只加不改**（同 T8）：已有的 `info.created` / `originalZone` / `wasShuffledIntoDeck` / `wasSetAsideAtSetup` 语义不许改。
- 对手侧同样要对（对手牌库里的牌被炸掉），`hidden` 过滤保住。
- Perf P2 的收益不能丢：没变的行不重画（`testAnUnchangedRowIsStillNotRedrawn` 继续绿），图层数护栏继续绿。
- **先失败再修**：两条各至少一条测试先红。第 1 条用上面那一局切 fixture 进 `HSTrackerTests/Fixtures/ZoneReplay/`（控制体积，切到够用为止）。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/Logging/Player.swift`、`HSTracker/Logging/Game.swift`、`HSTracker/Logging/Entity.swift`、`HSTracker/Logging/Parsers/TagChangeActions.swift`
- `HSTracker/UIs/Trackers/Tracker.swift`、`HSTracker/UIs/Trackers/SwiftUI/` 下的文件
- `HSTrackerTests/` 下的测试与 fixture；新增文件登记 pbxproj
- 断点如果落在这之外（比如 `RelatedCardsSystem/`、`Watchers.swift`），**先别改**，报告里写清楚位置和建议改法。

## 验收

1. Debug build `BUILD SUCCEEDED`；测试原 153 条 + 新增全绿。
2. 报告：两条各自的判定（数据错 / 画面旧 / 别的）、根因、证据、改了什么、哪条修不了直说。

## 汇报

结果写进本文件末尾「执行结果」一节。

## 执行结果（2026-09-21）

**两条都没能复现，两条都没改产品代码。** 新增的 12 条测试最终全绿 —— 它们是护栏和
排除证据。唯一红过的一次是**回放 harness 自己的问题**（见末节「补一轮」），不是产品 bug。
下面写清楚每条查到哪、用什么排除的、还剩哪些没测到的环节。

> 注：下面「第 1 条」一节写于第一轮（fixture 从重连处起步、两半日志都喂）。
> 结论没变，但读数和 fixture 范围以末节「补一轮」为准。

### 第 1 条：判定「不是分区取数错账」，证据是回放

任务书点名的那一局 **23:41:57 有一次断线重连**（`GameState.ReconnectIfStuck` → 第 234612 行
第二个 `CREATE_GAME`），所以这一局不是到 23:41:47 就结束，而是一直打到 23:51:43（下一个
`CREATE_GAME` 在 261399 行）。重连后的实体号和重连前逐一相同（67=`ULD_717`、68=`REV_018`、
79=`ICC_041`），这就是任务书把 217808~234611 当成完整一局的由来。

重连之后有一次**比任务书点的那次更贴症状**的爆炸，fixture 切的是这一段：

```
23:49:00  情势反转（DAL_602，id=89）把手牌洗回牌库，火焰之灾祸（ULD_717，id=67）在其中
23:49:00  同一次抽牌抽到 TNT（WW_372t，id=217）
23:49:03  TNT 的 CASTS_WHEN_DRAWN：
            SHOW_ENTITY id=67 ULD_717 zone=DECK   ← 牌库里、已揭示
            TAG_CHANGE id=79 亵渎 HAND→SETASIDE→GRAVEYARD
            TAG_CHANGE id=67 火焰之灾祸 DECK→GRAVEYARD
```

比任务书那次好在：**火焰之灾祸是牌表里的真牌、在牌库里是可见的一行**；任务书点的
嫉妒乐章（`ETC_085t`，id=202）是罪孽交响曲造出来洗进去的 token，`SHOW_ENTITY` 和
`ZONE=GRAVEYARD` 在同一个 block 里，它在牌库段**从来没有以可见行出现过**，用户不可能看到它。

回放（`ZoneGroupsT11ReplayTests`）在这一刻读出的三段：

| | 爆炸前 | 爆炸后 |
|---|---|---|
| 牌库段 `ULD_717` | 1 | **不在牌库段** |
| 已打出段 `ULD_717` | 不在 | **1** |
| 手牌段 `ICC_041` | 1 | 不在 |
| 已打出段 `ICC_041` | 不在 | **1** |
| `game.player.deck` 里的 `ULD_717` 实体 | 1 | 0 |

**数据是对的，两段在同一次刷新里一起动。** 另外把整份 fixture（21755 行）按每 250 行
一个检查点扫了一遍（约 87 个点），两条不变式全程成立：牌库段没有一张牌表卡超过牌表张数、
没有 `count == 0` 的行、手牌段逐张等于 `game.player.hand`。

顺带排掉的：

- `playerDeckDiscard` → `updateTrackers()` 这条刷新链在这一刻确实会触发
  （`zoneChangeFromDeck` 的 `.graveyard` 分支要求 `controller == player.id && cardId != ""`，
  `SHOW_ENTITY` 刚好在同一 block 里先把 cardId 补上了）。
- 全份日志（39 MB、多局）里「从牌库直接进墓地 / 除外」的实体只有 14 个，逐条看过：
  嫉妒乐章 id=202（爆炸，GameState 侧）、火焰之灾祸 id=67（爆炸，PowerTaskList 侧）、
  其余 12 个是罪孽交响曲的七宗罪乐章回合结束被除外（`REMOVEDFROMGAME`，双方各 6 张）。
  **没有一次是「游戏没揭示就炸掉」**，所以不是「我们不知道炸的是哪张」这条。

再看画面这一侧（T10 那一类）：新增 `TrackerMetricsTests.testARemovedRowStopsBeingPainted`，
挂真的 `NSHostingView`，两行画一遍、删掉第二行再画一遍，逐像素比 —— 剩下的那一行和之前
逐字节相同、列表高度正好减半、第二行没有残留。**行的删除会重画，T10 的 `.equatable()`
没有漏掉这一路。**

**所以第 1 条：在这份日志能提供的两次爆炸上，取数和画面都是对的，复现不了。**
可能性剩下（都拿不出证据）：① 用户看到的是另一局 / 另一份日志里的情况；
② 用户把「已打出段里多出来的那张」看成牌库段；③ 某个本日志没覆盖的形状。
**要继续查得请用户说清楚：哪一张牌、牌库段那一行的数字是多少、当时已打出段里有没有它。**

### 第 2 条：整条链逐段测过，都是通的，断点没找到

任务书列的链从下往上全部用测试钉过一遍（全绿）：

| 环节 | 测试 | 结果 |
|---|---|---|
| `TrackerCardListViewModel.setHighlight` → `rows` | `testSettingTheSynergyHighlightRepaintsTheRow` | 闭包落到 `row.highlight`，清除也能回去 |
| 高亮 → 像素 | 同上，挂 `NSHostingView` 逐像素比 | 点亮 / 熄灭两次画面都不同，P2 位图路径没吞掉 |
| 高亮活过下一次刷新 | `testTheSynergyHighlightSurvivesTheNextRefresh` | `update(cards:)` 重建行时 `highlightFn` 仍在，高亮保住 |
| `RelatedCardsManager` → 真闭包 | `testTheRealSynergyClosureReachesTheRows` | 用真的 `Arcanologist.shouldHighlight`，只点亮奥秘 |
| 悬停入口（P2 之后） | `testTheHoverSensorStillCoversEveryRow` | 每行一个 sensor、铺满 171×21、有 tracking area、`hitTest` 命中的就是它（位图没盖住） |

静态核对也没找到断点：`CardRowRasterKey.highlight` 在键里（`rasterKey` 第 12 个字段），
T10 的 `CardRowView.==` 比的就是这个键，所以高亮一变 `body` 必重跑；
`TrackerCardRow.==` 也比 `highlight`；`setSwiftUIHighlight` 四个列表都喂到了。
`git log -S` 看过 V1（`e3797ba8`）→ T10（`04dae47a`）这一段：**`Tracker.swift` 里 hover /
highlight 相关的代码一行没动**，`TrackerCardListViewModel.highlightFn` 更早（`77970623`），
`setSwiftUIHighlight` 是 T1（`1c44b212`）加的。嫌疑区间里没有改过这条链的提交。

**所以第 2 条：断点不在我这次能改的文件里，也不在我能离线驱动的那几层。**
没测到的只剩「实机上 `BigCardWatcher` / `DiscoverStateWatcher` 有没有真的回调」
和「`Settings.showPlayerHighlightSynergies` 实机读到什么」——这两个都得实测。
**要继续查得请用户说清楚：三个入口（记牌器行悬停 / 游戏内大卡悬停 / 发现界面）哪个失效、
是全部牌不亮还是个别牌不亮、上一次看到它正常是哪个版本。**

### 顺带发现的一个真 bug（在允许修改的文件之外，按规则没动）

`HSTracker/Utility/ReflectionHelper.swift` 的 `initialize()` 用一条 `else if` 链给类分桶：

```swift
} else if let rccl = cl as? ICardWithRelatedCards.Type, rccl != ResurrectionCard.self, !isAbstractPoolBase {
    cacheRelatedClassList.append(rccl)
} else if let hccl = cl as? ICardWithHighlight.Type {
    cacheHighlightClassList.append(hccl)
}
```

**同时实现两个协议的卡只会进 related 桶，永远拿不到高亮。** 现有 4 个中招：

- `Cards/Multi/LiftOff.swift`（`LiftOff`）
- `Cards/Warrior/GladiatorialCombat.swift`（`GladiatorialCombat`）
- `Cards/DeathKnight/TalanjiOfTheGraves.swift`（`TalanjiOfTheGraves`）
- `Cards/DemonHunter/DirdraRebelCaptain.swift`（`DirdraRebelCaptain`）

证据：`testTheRealSynergyClosureReachesTheRows` 里那句
`XCTAssertNil(manager.getCardWithHighlight(CardIds.Collectible.Invalid.LiftOff))` 是绿的。
**建议改法**：把 `ICardWithHighlight` 那一支从 `else if` 拆成独立的 `if`
（和下面 `ISpellSchoolTutor` / `ICardGenerator` 两支一样的写法），一行的事。
这**不能解释「高亮整体失效」**（182 个高亮类正常入表），所以没有顺手改 —— 它在允许修改的
文件之外，且改了也验不了用户那条症状。

### 补一轮：整局跨重连回放（按协调者要求）

第一轮的 fixture 从重连那个 `CREATE_GAME` 起步，实机却是**带着重连前的状态**吃下第二个
`CREATE_GAME` 的。重切成整局（原始日志 217808~261398，43591 行 / 4.87 MB，跨重连，
到本局结束为止）重跑，结论没变，但**查出了一件更重要的事**。

#### 重连时实机到底 reset 了什么

`PowerGameStateParser.handle` 碰到 `CREATE_GAME` 只调用**它自己的** `reset()`（块状态、
`currentEntityId`），后面那句 `eventHandler.gameStart(at:)` 是**注释掉的**。
所以 `Game` 一个实体都不丢：`entities`、`info.originalZone` / `originalController` /
`discarded`、以及 T8 / T9 的 `wasShuffledIntoDeck` / `wasSetAsideAtSetup` 全部留着，
服务器的全量重 dump 直接盖在上面。回放因此**不做任何手动 reset**，和实机同一条路径。

#### 先失败：第一轮的回放跑出了一条假警报，原因是 harness 不像实机

整局喂进去之后，`testNoDeckListCardIsCountedAboveItsListCount` 立刻红：

```
ETC_071 is counted above its deck list count（牌表 1，牌库段 2）
```

定位到实体 69（末日管弦家林恩 `ETC_071`，牌表卡）被 `markShuffledIntoDeck` 误闩成洗入副本
—— 正是 T8「执行结果」里写下、当时没法验证的那个口子（牌表卡被 情势反转 `DAL_602`
从手牌洗回牌库，此时 `info.created` 已为 true，再来个 CREATOR 就三条件全中）。

但那个 CREATOR 是**假的**。逐行回溯（`creator -> 62` 落在第 15530 行）发现：

- 实机 `LogReaderManager.processLine` 对 `.power`：`GameState.` 开头的行只进 `powerLog` /
  choices / gameInfo，**永远不会进 `powerGameStateParser`**；`PowerProcessor.EndCurrentTaskList`
  进 choices。真正喂给解析器的只有 `PowerTaskList.DebugPrintPower` 那一半。
- T6 / T10 的回放类**两半都喂**。而两半的写法不一样：GameState 写
  `FULL_ENTITY - Creating ID=<n>`，PowerTaskList 写 `FULL_ENTITY - Updating [… id=<n> …]`，
  而 `PowerGameStateParser.CreationRegex` 只匹配 **Updating** 那一种。
- 于是 GameState 的 `Creating` 行不更新 `currentEntityId`，它下面整块缩进的 `tag=…` 行
  （`CreationTagRegex` 只认 `tag=(\w+) value=(\w+)`）全部落到**上一个实体**头上。
  这一局里 `FULL_ENTITY - Creating ID=222`（提克和托克，带 `tag=CREATOR value=62`）
  的 tag 块落到了实体 69 上。

**所以这是 harness 的问题，不是产品代码的问题。** 把 `ZoneGroupsT11ReplayTests` 的喂线改成
和 `LogReaderManager` 同一条路由（只解析 `PowerTaskList.DebugPrintPower`）之后，
实体 69 的 `creator` 全程为 0、从不落闩，测试转绿。新增
`testTheShuffledInLatchNeverLandsOnADeckListCard` 按每 250 行扫全程盯这一条
（这一局 情势反转 洗了两次手牌回库，正是 T8 说「没法验证」的那个形状，现在验过了：不误伤）。

> **建议（不在本书允许修改的文件之外，但属于别的任务）**：`ZoneGroupsReplayTests` /
> `ZoneGroupsT10ReplayTests` 两个旧类仍然两半都喂。它们目前全绿，本书没动，但同一个
> 错位随时可能让它们给出假结论。要么按同样方式过滤，要么给 `CreationRegex` 补上
> `FULL_ENTITY - Creating ID=(\d+)` 这一形（后者动的是 `PowerGameStateParser.swift`，
> 不在本书允许修改的文件里）。

#### 三个时刻的读数（实机路由，整局跨重连）

| | 牌库段 | 已打出段 |
|---|---|---|
| **爆炸 1 之前**（23:41:27） | `ETC_085t`（嫉妒乐章）1、`WW_372t` 5、`ULD_717` 1 … 共 19 行 | `ETC_085t` 1 |
| **爆炸 1 之后**（重连前） | **`ETC_085t` 不在**、`WW_372t` 5、`ULD_717` 1 … | `ETC_085t` **2**、`TTN_932` 1 |
| **重 dump 之后**（23:42:15） | `WW_372t` **5**（没变）、`ULD_717` 1、`ETC_085t` 仍然不在 | **和重连前逐字相同** |
| **爆炸 2 之前**（23:49:03） | `ULD_717` 1、`LOOT_017` 1、`CATA_496` 1、`MIS_027` 1、`WW_372t` 1、`ETC_085t2` 1 | — |
| **爆炸 2 之后** | **`ULD_717` 不在** | `ULD_717` 1、`ICC_041` 1 |

- **没有重复计数**：重 dump 前后已打出段的 map 逐字相同；牌库段里洗入的 5 张 TNT 数字没变；
  牌库段的差异只有两张真的被抽走的牌（`ULD_003`、`ETC_085t4` 进了手牌）。
- **重连前离开牌库的实体状态没被冲掉**：id=202（嫉妒乐章）重 dump 后仍是
  `originalZone=.deck`、`originalController=2`、`discarded=true`、`wasShuffledIntoDeck=true`；
  id=72（混乱吞噬）同样保住，且**没有**被重 dump 误闩。两者
  `hasOutstandingTagChanges` 都是 `false`。
- **23:49:03 之后 `ULD_717` 不在牌库段**，在已打出段。

这五条现在都是断言（`testTheBombBeforeTheReconnectMovesBothCards`、
`testTheReconnectDoesNotDoubleCountOrResurrect`）。

#### 一个真实的边界，顺手记下来

中途把 fixture 截在「炸掉 `ULD_717` 那一行」上时，读到 id=67 的
`info.hasOutstandingTagChanges == true` **卡住**，结果 `revealedEntities` 把它滤掉 →
`entitiesThatLeftTheDeck` 里没有它 → **牌库段一直留着这张被炸掉的牌，已打出段也没有它**。
喂完整个 block（`BLOCK_END` / `invokeQueuedActions` 会清掉这个标志）之后就正常了。

所以这是个**窗口期**：从创建 tag 入队到块结束之间，被炸掉的牌会既不在已打出段、又还在牌库段。
实机的 `updateTrackers()` 是 debounce 之后在别的队列上跑的，理论上可能正好落在这个窗口里
并画出用户描述的画面。**没能在离线回放里稳定复现**（回放是单线程、按行推进的，取数总在
块与块之间），所以只作为怀疑记下，不作为结论。要坐实它需要实机加探针。

### 改了哪些文件

- `HSTrackerTests/Fixtures/ZoneReplay/2026-09-20-bug-t11.log` —— 新增 fixture，
  原始日志第 217808~261398 行（第一个 `CREATE_GAME` → 本局结束），**整局、跨重连**、
  按 `LogReaderManager` 的过滤条件原样截，43591 行 / 4.87 MB。
- `HSTrackerTests/ZoneGroupsReplayTests.swift` —— 新增 `ZoneGroupsT11ReplayTests` 7 条：
  重连前那次爆炸、重连不重复计数 / 不复活、T8 闩不误伤牌表卡（扫全程）、
  牌库里被炸的牌、手牌里被炸的牌、手牌段全程对账、牌表上限 + 无零行护栏。
  喂线 `feedOne` 按 `LogReaderManager` 的路由只解析 `PowerTaskList.DebugPrintPower`。
  原有两个类（T6 / T10）一行没动。
- `HSTrackerTests/TrackerMetricsTests.swift` —— 新增 5 条（删行不残留、高亮点亮/熄灭逐像素、
  高亮活过刷新、真闭包走 `RelatedCardsManager`、悬停 sensor 没被位图盖住）和一个
  `token(_:)` 小助手。原有 35 条一行没动。
- `HSTracker.xcodeproj/project.pbxproj` —— fixture 登记 Resources 4 处。本次只有这一项。

**产品代码一行没动**：`Player.swift` / `Game.swift` / `Entity.swift` /
`TagChangeActions.swift` / `Tracker.swift` / `SwiftUI/` 全部原样。
`docs/PLAN.md` / `docs/PROGRESS.md` / `.xcstrings` 没碰，没 commit、没 `git add`。

> **工作区里另有不是本次改动的东西**：`HSTracker/Logging/Game.swift` 和
> `HSTracker/UIs/Trackers/Tracker.swift` 里出现了几处
> `logger.info("[T11] …")` 探针（注释写着 "Bug T11 diagnostic, remove once the dead link
> is found."）。**不是我加的**，会话开始时的 `git status` 里也没有，按规则没有还原。
> 最后一轮 build / test 是带着它们跑的，全绿。合入前记得清掉。

### 验收

- `xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug -destination 'platform=macOS' build`：`** BUILD SUCCEEDED **`
- `xcodebuild … test`：`** TEST SUCCEEDED **`，
  `Executed 165 tests, with 0 failures (0 unexpected) in 195.967 (196.601) seconds`
  —— 原 153 + 新增 12（`ZoneGroupsT11ReplayTests` 7 + `TrackerMetricsTests` 5）。
  T6~T10 的护栏全绿，P2 的
  `testAnUnchangedRowIsStillNotRedrawn` / `testColdAndWarmRasterCost` /
  `testFlatteningCollapsesTheRowLayerTree` / `testFlattenedRowIsTheSamePicture` 也全绿。
- 🎮 需要用户实测才能往下走，两条各需要一句话：
  - 第 1 条：下次看到「被炸掉的牌还在牌库」时，记下**哪张牌、牌库段那一行的数字、
    已打出段里有没有它**（截图最好）。
  - 第 2 条：三个入口分别试一次 —— ① 鼠标停在记牌器的一行上、② 游戏里把鼠标停在自己手牌上、
    ③ 发现界面 —— 哪个不亮；再说一句「全部牌都不亮」还是「只有某张卡不亮」。
  - `open ~/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/Build/Products/Debug/HSTracker.app`
