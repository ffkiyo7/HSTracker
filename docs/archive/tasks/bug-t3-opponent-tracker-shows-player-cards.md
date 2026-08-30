# Bug T3：对手记牌器里混进我方职业的卡

## 症状

2026-08-30 21:11–21:35 那三局标准模式狂野排位里，**对手记牌器（屏幕左侧那一栏）从第一回合
开始就列着三张恶魔猎手的卡**，并且整局都不消失：

- 塞纳留斯之斧
- 布洛克斯加
- 第一道阿古斯传送门

用户是恶魔猎手（牌组「地沟油」），**对手是圣骑士** —— 日志里
`HSReplayAPI.getConstructedMulliganV2` 那行明写 `"player_class":"DEMONHUNTER","opponent_class":"PALADIN"`。
圣骑士不可能带恶魔猎手的职业卡。

截图里同一栏还有「幸运币」和「指挥官碧阿娜」，计数框显示 `5 | 36`。**36 这个数字值得注意** ——
它说明对手记牌器算的是一副 40 张的牌库，而用户自己的牌组是 30 张（同一条日志里的
`deck_cards` 正好 30 项）。所以列表不是简单地把用户的牌组整个搬过去了。

用户原话：「从第一回合开始，对手的记牌器里一直有我的三张卡……我不知道这是上游行为还是我们弄错的。」

## 已经确定的：这是上游行为，不是本 fork 改出来的

相对 upstream `534ee2d8`（3.6.7），下面这些路径**一个字节都没动**（`git diff --stat 534ee2d8 --`
输出为空）：

- `HSTracker/Logging/Player.swift`
- `HSTracker/Hearthstone/RelatedCardsSystem/`
- `HSTracker/Hearthstone/CardUtils.swift`
- `HSTracker/Logging/Parsers/` 整个目录

也就是说对手卡表的构建和实体归属全是上游原样。**但"上游的"不等于"对的"** —— 这个显示结果
本身是错的，本任务就是要修它，不是要论证它合理。

## 复现

标准模式打一局，看对手记牌器第一回合的内容。用户三局都撞到了，复现率看起来很高。

## review 侧已经排除的（**当作待验证的说法**）

下面是 review 侧的排查结论，**每条都可能读错，独立复核后如果不成立请直说**：

1. **不是「相关卡牌」推测。** `RelatedCardsManager.swift:123` 的 `getCardsOpponentMayHave`
   按 `shouldShowForOpponent(opponent:)` 过滤；`Cards/` 下所有能返回 true 的实现都调了
   `CardUtils.mayCardBeRelevant(..., playerClass: opponent.originalClass)`。而这道职业门是
   **fail-closed** 的 —— `CardUtils.swift:12-18` 的 `isCardFromPlayerClass` 在 `playerClass`
   为 nil 时直接 `return false`。所以对手职业没解析出来时它只会少显示，不会多显示。
   唯一没调这道门的是一张 Neutral 卡，中立不需要职业门。
2. **不是 `revealedEntities` 越界。** `Player.swift:170-175` 已按控制者收口：
   `isControlled(by: self.id) || info.originalController == self.id`。

## 两条还活着的线索（**都没证实，别当结论**）

### 线索 A：`Player.knownOpponentDeck` 的跨局残留

- 它是 `Player` 上的 **`static`**（`Player.swift:199`）。
- `opponentCardList`（`Player.swift:471-472`）一上来就 `if Player.knownOpponentDeck == nil`，
  非 nil 时走 `Player.swift:697` 的另一条分支。
- 全仓库只有两处会设它：`LinkOpponentDeckPanel.swift:82`（手动「关联对手牌组」）和
  `PowerGameStateParser.swift:479`（对手打出 Whizbang）。
- 清零只有三处：手动解除关联（`LinkOpponentDeckPanel.swift:146`）、以及
  **`Game.swift:2456` 一个 game-end 的条件分支里**。

**static + 条件清零 = 跨局残留的经典形状**，而且「第一回合就有、整局不变」正好符合"列表来自一份
固定牌表"的症状。**但用户不确定自己是否手动关联过对手牌组**（可能误触），所以这条既不能排除
也不能坐实。另外那个 `36` 的计数似乎和"关联了用户自己 30 张牌组"对不上，也需要解释。

### 线索 B：实体归属

如果 A 不成立，那就是某些实体在解析时被算到了对手名下。`opponentCardList` 的过滤条件里
（`Player.swift:473-496`）有几处值得盯：`e[.creator] == 1`、`e.info.originalController == self.id`、
以及末尾那个不带控制者判断的 `|| e.isInHand || e.isInDeck`。谁在开局把这三张卡的
`originalController` 或控制者写成了对手，是这条线索要回答的问题。

## 排查要求

**先定死是 A 还是 B，再动手改。** 现在两条都是猜测，直接改任何一条都可能是白改。

推荐做法（不强制，你有更好的办法就用你的）：**加一行临时诊断日志跑一局**，照
`Game.swift` 里 `[trackervis]` 的样子做 —— 开局时打出 `Player.knownOpponentDeck` 是 nil 还是
有多少张、以及非 nil 时头几张是什么。这一局就能把 A 排除或坐实，比继续读代码快得多。
如果落到 B，再加针对性的实体归属日志。

review 侧这次在 Bug T2 上就栽在"只读代码不跑日志"——漏看了 `propertyChanged` 闭包里的一层
`main.async`，推出了错误结论。**这里不要重蹈覆辙。**

## 允许修改

改哪些文件由排查结论决定，但要收敛在这个 bug 上。硬约束：

- **不要为了让列表干净就在显示层做职业过滤兜底。** 如果根因是归属错了，在
  `updateOpponentTracker` 或 `opponentCardList` 末尾加一道"过滤掉非对手职业的卡"只是遮症状 ——
  归属错了的地方还会以别的形式冒出来（比如计数、牌库剩余数、抽牌概率）。
  除非你能论证上游本来就该有这道门。
- **不要删或改 `Game.swift` 里带 `[trackervis]` 标记的临时诊断代码。**
- **不要动 `ac116be0` / `eb52832e` 这两个 commit 修好的东西**（watcher 线程归属、Tier7 显示路径）。
- 不要 `git add` 或 commit，不要动 `.xib`，不要动 `HSTracker.xcodeproj/project.pbxproj`。
- 上游文件可以改 —— 这是上游 bug，本 fork 修它是合理的。但要在任务书里写清楚改了上游的哪里、
  为什么，方便下次合并上游时对账。

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`：

   ```sh
   env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin \
     xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' build
   ```

2. 🎮 标准模式一局：**对手记牌器里不再出现我方职业的卡**，从第一回合到打完都不出现。
   同时确认对手记牌器**该显示的东西没被误伤** —— 对手真实亮过的牌、剩余牌库数、抽牌概率
   都还正常。

3. 把结论写进本任务书：是 A 还是 B、证据是什么、review 侧上面那两条排除结论是否成立。
   加过的临时日志如果留着，说明为什么。

4. 如果结论是"这是上游有意为之的行为、显示是对的"，**那就直说并给出依据**，不要为了交差
   硬改。那种情况下正确的产出是一份说明，而不是一个 patch。

## 执行结论（2026-08-30）

### 根因不是 A 或 B，而是排查时漏掉的第三条预测路径

实际根因是 **C：玩家自己的奇闻牌在开局揭示时，被无条件写进了对手的牌库预测列表**。

- 原始 `Power.log` 中四局都能一一对上：本机玩家 ID 依次是 `2 / 2 / 1 / 2`，布洛克斯加
  `TIME_020` 的控制者也依次是 `2 / 2 / 1 / 2`。实体归属从头到尾都正确。
- `CardIds.fabledGroups[.demonhunter]` 正好只有 `TIME_020`、`TIME_020t1`、`TIME_020t2`，
  与截图里的布洛克斯加、塞纳留斯之斧、第一道阿古斯传送门逐项吻合。
- `TagChangeActions.onRevealed` 在 `START_OF_GAME_KEYWORD` 下会调用自己的 `predictFabled`；
  这个函数此前不判断实体属于谁，一律调用 `game.opponent.predictUniqueCardInDeck`。三张牌随后由
  `opponentCardList` 的 `getPredictedCardsInDeck` 加入左侧列表，所以它们不影响真实的 40 张牌库
  计数，也解释了截图为什么同时是固定三张错误牌和 `5 | 36`。

### A / B 和 review 结论的复核

- **A 不是本次根因。** review 所写“每局开始清”不成立：实际是传统模式 `gameEnd()` 的条件分支
  清零，确实存在别的跨模式残留风险。但本次四局每局都在开局由本机布洛克斯加重新触发完全相同的
  三张预测，且前三局的传统模式结束路径都会清零，跨局残留解释不了这个重复触发。曾按建议加入一条
  临时日志同时打印奇闻控制者和 `knownOpponentDeck`；诊断版构建成功，但炉石已经退出，HSTracker
  不会重读旧会话，所以没有拿它冒充实测证据，临时日志也没有保留。
- **B 也不成立。** 原始日志直接证明布洛克斯加始终属于本机玩家，不是控制者或
  `originalController` 被写成了对手。
- review 对 **`revealedEntities` 没越界** 的结论成立，但与本次根因无关；错误数据来自
  `inDeckPredictions`。
- review 对 **RelatedCards 职业门** 的代码结论成立：142 个 `shouldShowForOpponent` 中 125 个
  恒为 false，16 个可显示的职业牌都用 `opponent.originalClass` 调 `mayCardBeRelevant`，剩下唯一
  可显示的是 Neutral 的 Velen。不过“不是相关卡牌推测”只排除了 RelatedCards 子系统，漏掉了
  `fabledDict → inDeckPredictions` 这套独立预测机制。

### 修复

修改上游文件 `HSTracker/Logging/Parsers/TagChangeActions.swift`：开局奇闻预测只有在揭示实体确实由
对手控制时，才写入 `game.opponent`。对手自己的奇闻预测保持原样；玩家自己的奇闻直接跳过。没有在
显示层加职业过滤，也没有改实体归属、牌库计数或 `[trackervis]` 诊断代码。

### 验证状态

- 原始 21:10 会话的 `Power.log` 已完成四局交叉核对，四次本机玩家 ID 都与布洛克斯加控制者一致。
- 删除临时日志后的最终代码已通过受限环境 Debug build，输出 `BUILD SUCCEEDED`。
- 标准模式实战仍需下一局确认：玩家奇闻三张不再出现在对手侧，同时对手真实亮牌、牌库剩余数和
  抽牌概率保持正常。这个观察必须由真实新对局完成，旧日志静态重放不能代替界面验收。
