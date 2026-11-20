# 包 4　日志侧兜底：游戏模式和我方 / 对手识别（W2b、W2c）

> 总 spec：`../spec.md`。顺序第 4，依赖包 3 先合入（两者都改 `PowerGameStateParser.swift`）。包 5 依赖本包。

## 总原则

- HearthMirror 能用时，行为和现在**完全一致**，它给出的值始终优先。日志兜底只在它拿不到值时才生效。
- 兜底只覆盖构筑模式，观战、佣兵、战棋都不启用。
- 本包只做单元测试和回放测试；实机验收放到包 5，因为要用包 5 的 Debug 开关。
- **提交顺序：先 W2b，后 W2c**。W2c 要排除战棋和佣兵，HearthMirror 失效时只能靠 W2b 从日志读出的游戏模式来判断。

## W2c　我方 / 对手识别

### 现状【核实】

- `player.id` / `opponent.id` 全仓库只在 `Game.swift:1429-1430` 和 `:1976-1977` 赋值，数据来自 HearthMirror 的 `MatchInfo`。
- `GameInfoHandler` 只把「玩家编号 → 名字」存进 `playerIdsByPlayerName`，不会设置这两个 id。
- 编号缺失时：
  - 区域变化的判断（例如 `TagChangeActions.swift` L1170、L1288 的 `controller == eventHandler.player.id`）全部对不上；
  - 创建类 tag 的动作会一直排队，等 `determinedPlayers()`（`Game.swift:239`）变成 true。
- 2017 年 `f30225cd`（"HearthMirror first implementation"）删掉过一段只靠日志判断双方的逻辑，用 `git show f30225cd` 能看到原代码。

### 要做的事

1. HearthMirror 没给出 `MatchInfo` 时，只靠 Power.log 确定双方编号。恢复并改写 `f30225cd` 的判断：
   - 第一张进入手牌、带 `cardId`、并且有 `CONTROLLER` 的实体，它的控制者就是我方；
   - 进入手牌但 `cardId` 为空的实体，它的 `CONTROLLER` 是对手。
2. 「名字不是 `UNKNOWN HUMAN PLAYER` 的就是自己」这条规则**不作为判断依据**：`Fixtures/ZoneReplay/2026-09-20-bug-t11.log` 第二局双方都显示 BattleTag。
3. 确定之后，像现在 `determinedPlayers()` 变成 true 时那样，执行一遍排队中的 `invokeQueuedActions`。
4. **优先级**：
   - `MatchInfo` 先到：日志兜底不再执行；
   - 日志先确定：之后 `MatchInfo` 到达时比对一下。一致就什么都不做；不一致就记 warning，并以 HearthMirror 为准。
   - 局中改变归属会带来什么影响，要评估后写进提交说明【未核实】。

### 风险

如果有对双方都可见的手牌实体（比如对手的幸运币），可能把对手误判成自己【未核实】。以下面回放测试的结果为准。

## W2b　游戏模式兜底

### 现状【核实】

- `currentGameType` 只在 `matchInfo`（`Game.swift` 约 L1431）和 `cacheGameType()`（L1832，读不到就每秒重试）里赋值。
- `isTraditionalHearthstoneMatch`（L2903）要求它不是 unknown。全仓库有 155 处引用这个判断，所有计数器都在其中。
- `GameType` / `FormatType` 是 Int 枚举，没有按名字构造的方法。

### 要做的事

1. **解析**：在 `GameInfoHandler` 解析 `GameState.DebugPrintGame() - GameType=GT_…` 和 `FormatType=FT_…` 两行。仿照 `GameTag.init?(rawString:)`（`GameTag.swift:575`）补一个从字符串到枚举的映射。
2. **存放和读取**：日志解析出的值存进单独的字段，不要写 `_currentGameType` / `_currentFormatType`。读取时 HearthMirror 的值优先，它是 unknown 时才用日志值。
3. **清空时机**：
   - 在 **`GameState.DebugPrintPower() - CREATE_GAME`** 这一行清空。它和 `DebugPrintGame` 都走 `LogReaderManager.swift:246` 的 `GameState.` 分支，同一个线程，而且在文件里排在前面。
   - **不能**在 `PowerGameStateParser.swift:1598` 清空。那里处理的是 `PowerTaskList` 的 `CREATE_GAME`，排在 `GameType=` 之后。以 11-15 的 Power.log 为例：第 2 行是 `GameState` 的 CREATE_GAME，第 586 行是 `GameType=`，第 597 行是 `PowerTaskList` 的 CREATE_GAME【核实】。
   - `Game.reset()` 由加载画面和排队事件在另一条线程上触发，也不要让它清这两个字段。
   - 对局结束后日志值还留着，会不会让菜单里的功能误以为在对局中，要检查【未核实】。
4. **不要动**：`cacheGameType()` 里战棋双打的纠正逻辑。

### 设计要点

`GameInfoHandler` 现在直接取 `AppDelegate.instance().coreManager.game`，测试没法注入。改成像 `PowerGameStateParser(with:)` 那样由外部传入 game。

## 验收

- **回放测试（W2c）**：
  - 把 `HSTrackerTests/Fixtures` 里带 `DebugPrintGame` 的 15 个 log 逐局回放，其中红龙 12 个、ZoneReplay 3 个，t11 有两局；
  - 回放时**不预设编号**，日志兜底得出的编号要和现有测试里写死的值（例如 `ZoneGroupsReplayTests.swift:66-67`、`:358-359`、`:670-671`）或按局核对过的真实值全部一致；
  - 现有的 `ZoneGroupsReplayTests` 和红龙回放测试照样通过。
- **单元测试（W2b）**：
  - 喂入 `DebugPrintGame` 的几行，解析出 `gt_ranked` / `ft_wild`；
  - 同时有 HearthMirror 的值时以它为准；
  - 再来一次 `GameState` 的 `CREATE_GAME`，日志值被清空。
- 全套测试通过。

## 记录

W2b、W2c 各一个 `feat:` 提交；`docs/PLAN.md` 逐行记。
