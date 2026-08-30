# Phase 6 / T1 — 排队时显示的是上一局的残局

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。
本任务对应 `docs/PLAN.md` 的 **Phase 6**，动手前把那一节读完 —— **但那一节的「好消息」第 3 条是错的，
本任务书推翻它**，见下面「PLAN 的假设被推翻」。

**这是一本 spike + 修复合一的任务书。** 先做 spike 并把结论写进报告，再动手改。
如果 spike 的结论与本文件的判断冲突，**停下来报告，不要按自己的结论继续改**。

## 现象

卡点 ① 实战（2026-08-30）用户观察：

> 现在在排队的时候，记牌器的确会显示在右侧了：符合我的需求，但是显示的记牌器是刚刚那把剩下的状态，
> 看看能不能改成显示完整的套牌。

## 已经查清的部分

### 残局是怎么留下的

`game.reset()` 只在 `Gameplay.Start` 触发（`HSTracker/Logging/Handlers/LoadingScreenHandler.swift:137`），
另一处是 `PowerGameStateParser.swift:1461` 的 `CREATE_GAME`。**两处都在"对局真的开始"那一刻**。

而进队列走的是 `QueueEvents.handle()`（`HSTracker/Logging/QueueEvents.swift:40-45`），
它只做 `autoDetectDeck` → `game.set(activeDeck:)`，后者结尾是 `updateTrackers(reset: true)`
（`Game.swift:1863`）。**`player` / `opponent` 的 `entities`、`revealedEntities` 一个都没清。**

于是 `playerCardList` → `getDeckState()`（`Player.swift:538`）拿着上一局的 `revealedEntities`
去减 `originalCardsInDeckIds`，算出来自然是残局。

### PLAN 的假设被推翻

`docs/PLAN.md` 的 Phase 6「好消息」第 3 条写：

> **牌表内容天然正确。** `getDeckState()` 的 `remainingInDeck` 是「`currentDeck.cards` 减去
> `revealedEntities`」，而开局前 `revealedEntities` 是空的 → **正好是完整的 30 张**。

**"开局前 `revealedEntities` 是空的"不成立** —— 上一局结束后它一直是满的，直到下一局
`Gameplay.Start`。这条假设是本任务书要修的东西之一（PLAN 已同步修正，此处留档说明来由）。

### ⚠️ 最关键的一条：「能显示」和「显示的是残局」是同一个根因

`Game.updatePlayerTracker()` 的显示条件里有 `self.currentGameType != .gt_unknown`（`Game.swift:376`），
`updateOpponentTracker()` 的 `:301` 一模一样。而 `_currentGameType` **也只在 `reset()` 里被清回
`.gt_unknown`**（`Game.swift:1694`）。

所以现在排队时记牌器之所以会出现，**恰恰是因为上一局的 `currentGameType` 没被清掉**，
把 Phase 6 本来要放宽的那个条件绕过去了。

**推论：只要你把状态清干净，记牌器在排队时就会消失** —— 修好残局的同时会打坏用户明确说
"符合我的需求"的那个行为。**两件事必须一次做完**：清残留 + 按 PLAN 的 Phase 6 放宽显示条件。
只做前者是净退步。

## spike 要回答的问题

1. **在哪清？** 候选：进队列（`QueueEvents.handle`，`e.isInQueue == true`）、
   `handleEndGame()` 之后、`gameEnd()` 之后。给出选择和理由。
   注意首次启动就在队列里、以及退队列再进队列的情况。
2. **`reset()` 的副作用面有多大？** 它清 `_matchInfo` / `gameResult` / `wasConceded` /
   `gameId` / `entities` / `secretsManager` / 各种 overlay 状态（`Game.swift:1678-1770`）。
   **必须确认对局结束后还有谁在读这些**，重点三处：
   - HSReplay 上传：`handleEndGame()`（`:2328`）里 `UploadMetaData.generate(stats:buildNumber:game:)`
     （`:2502`）**同步**读 `game`，之后的 `LogUploader.upload` 是异步的 —— 确认它的回调不再碰 `game`。
   - BobsBuddy / Sentry 的排队事件（`:2512` / `:2521`）。
   - 战绩写库和 `Events.reload_decks`。
   给出「上传路径在进队列之前就把要读的东西读完了」的证据，或者反例。
3. **需不需要整个 `reset()`？** 如果只清 `player.reset()` / `opponent.reset()` / `entities`
   就够，说明为什么；如果必须整个 `reset()`，说明为什么。**倾向复用现成的 `reset()`** ——
   自己挑字段清是长期维护负担，上游以后加字段不会来同步。
4. **`reset()` 之后 `currentDeck` 还在吗？** `reset()` 不碰 `currentDeck`，但
   `QueueEvents` 里 `set(activeDeck:)` 的实际赋值在 `DispatchQueue.main.async` 里
   （`Game.swift:1850`）。**清和设的先后顺序要理清楚**，否则会出现"清完了但牌组还没设回来"的空窗。

## 修复要做出什么

`docs/PLAN.md` Phase 6 的验收清单，逐条：

1. 进队列 → 记牌器出现、**30 张全在**（不是残局）、计数框 `30 / 0`
2. 匹配成功进对局 → **平滑过渡，不闪一下、不重置**
3. 退出队列 → 按设置消失
4. **战棋 / 佣兵排队时不出现**

## 关键约束

- **战棋 / 佣兵的排除不能靠 `isBattlegroundsMatch()` / `isMercenariesMatch()`** ——
  那两个判断本身依赖 `gameType`，排队时同样是 unknown。按 `currentMode` 白名单挡，
  `QueueEvents.swift:12-13` 已经有现成的两组常量（`modes` / `lettuceModes`）。
- **新设置只能是 defaults-only。** PLAN 倾向加 `Settings.showTrackerWhileQueuing`（默认开），
  但通用约束第 4 条禁止改 `.xib`，所以**没有设置界面**，照 `use_swiftui_tracker` 的先例做
  （`Settings.swift` 加属性 + key 常量即可）。加不加由你判断并说明理由 —— 如果你认为
  不加开关更干净，给出理由也可以。
- **加了新 key 就必须加进 `Game.swift` 的 `playerTrackerUpdateEvents`**，否则改设置不会实时重绘
  （PLAN 的 2.3 有这条，T2 踩过）。
- **对手记牌器同样要处理。** `updateOpponentTracker()` 的条件是复制粘贴的，排队时对手侧
  应当是空的 / 不显示，不能留着上一局对手的牌。
- **不要动 `getDeckState()` / `playerCardList`。** 它们还被战绩上传（`Game.swift:2161` 附近）
  和套牌导出（`AppDelegate.swift`）依赖，Phase 2 也约定这两个函数保持原样。
  正确的修法是让它们**拿到干净的输入**，不是改它们的算法。

## 范围边界

- 不做 PLAN Phase 6 提到的"站在大厅就显示"那一档，**只做队列**。
- 不做 PLAN 4.1 的 Dock 菜单反馈（Toast / 打勾），虽然同根因。那是 Phase 4。
- 不动渲染层（`Tracker.swift` / `SwiftUI/`）。

## 允许修改的文件

- `HSTracker/Logging/QueueEvents.swift`
- `HSTracker/Logging/Game.swift`
- `HSTracker/Core/Settings.swift`（仅在你决定加开关时）

## 验收

1. Debug 构建通过。
2. `git diff --stat` 里没有范围外的文件。
3. **实战由人来做。** 标准模式排一次队；战棋侧**只需进队列再退出** —— 用户不玩战棋，
   不会为验收去打一局，所以第 4 条只能这样验。你只需保证构建通过、逻辑自洽。
4. 报告里必须明确写出：**你改完之后，排队时记牌器还会不会显示**。这是最容易被打坏的那条。

## 报告里请回答

- spike 四个问题的结论，每条给证据（行号）。
- 你在哪一点清状态、清的是什么、为什么是那里。
- 清状态和 `set(activeDeck:)` 的先后顺序你怎么保证的（注意后者有 `DispatchQueue.main.async`）。
- 加没加新设置，理由。
- 对手记牌器排队时的行为。
- 范围边界之外你注意到、但按规则没有动的问题。
