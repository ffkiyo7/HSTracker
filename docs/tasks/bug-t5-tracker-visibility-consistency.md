# Bug T5 — 把显示门收口：还有一个 overlay 和一个开关没跟上

先读 `docs/tasks/_common.md` 里的通用约束。

## 前情

`docs/tasks/bug-t4-tracker-visibility-out-of-game.md` 已经把两个主记牌器换成正向场景门，
2026-08-31 23:26 那一局实战验收通过（排队只显示我方、对局中双方、结束即隐藏，用户确认）。
**用户已明确决定：「打完的瞬间就消失」这个行为保留，不要改回去。**

但那次只改了两个主记牌器，留下两处没跟上。这本收口。

## 要修的两件事

### 1. 结算画面上「法力水晶上限」overlay 单独留着

两个记牌器在对局结束的瞬间消失，而这个 overlay 还挂在牌桌上，直到回主菜单才消失。
用户 2026-08-31 实战确认了这个现象。**期望：它跟记牌器同进同退。**

### 2. 「不在对局时隐藏全部记牌器」这个偏好开关现在半死

两个主记牌器已经不读它了，但还有别的路径在读。用户去设置里勾它会得到部分效果 ——
这比完全没效果更难排查。**期望：要么让它也走同一个场景门，要么从设置界面撤掉。**

**这两件事很可能是同一条路径上的**，但别因为这个假设就只查一处 ——
先把"谁还在读旧的判定"扫干净，报告里列出全部读者和各自的处置。

## 硬约束

- **不许改 Bug T4 定下的行为。** 那张表（对局中双方 / 排队只我方 / 主菜单都不显示）
  和「结束即隐藏」都已实战验收，是基线不是待议项。
- **上游默认值不要改。** 修完默认行为就要对，不依赖用户去配。
- 如果结论是那个偏好开关应该从设置界面撤掉，**要连同它的本地化字符串一起处理干净**，
  不要留孤立的 key。
- ⚠️ **不要改刷新路径的结构、投递顺序或防抖参数。** T6b 已结案，但它留了一个候选
  「把 `updateAllTrackers()` 的 18 次主队列投递合并成一个 block」，那件事有自己的立项理由
  （帧一致性）、自己的爆炸半径和独占的实战验收，**排在 Phase 1 的 T5 / T6 之后**。
  本任务顺手合并会把那次验收搅浑。**只碰显示条件。**
- 不要 `git add` 或 commit，不要动 `.xib`，不要动 `project.pbxproj`。

## 顺带清一个 T4 review 留下的形状问题

`updateOpponentTracker` 里 `clearTrackersOnGameEnd` 那块被移出了 `if shouldShow`，
于是只要 `gameEnded` 为真就**每一轮刷新**都往一个已经隐藏的 tracker 写空数组。
该设置默认 `false`，所以现在不影响任何人；但 T6b 正在削的就是"给隐藏窗口反复写
`@Published`"这种形状。**顺手处理掉，并在报告里说明你选的做法为什么不改变
该设置打开时的可见行为。**

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`：

   ```sh
   env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin \
     xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' build
   ```

2. 报告里列出旧判定的**全部**读者，以及每一个的处置（改走场景门 / 保持原样 + 为什么）。

3. 论证这次改动**没有**动到 Bug T4 那张表里的任何一格。

4. 标出哪些能静态证明、哪些要用户实战确认。**用户不玩战棋**，战棋相关只做静态论证。

## 背景资料

- Bug T4 的实现、逐格对账和 review 的四条副作用：`docs/tasks/bug-t4-tracker-visibility-out-of-game.md`
- 显示门的历史包袱：`docs/PROGRESS.md` 的「③ 的余留」整节

## 执行结果（2026-08-31）

选择第一种处置：保留设置项和默认值，但所有旧显示判定的实际读者统一改走 T4 的正向对局门
`!gameEnded && !isInMenu`。旧判定的完整读者如下：

- `updateMaxResourcesWidget` 的我方、对手法力上限窗口：改走对局门。对局结束时 `gameEnded` 先变为
  `true`，同一轮 `updateTrackers(reset: true)` 会同时隐藏主记牌器和两个法力上限窗口。
- `updateCounters` 的双方计数器：改走同一个对局门，避免它继续成为偏好开关的局部生效路径。
- `TrackersPreferences` 对偏好值的读取和写入：保持原样；这里只保存设置，不决定任何窗口是否显示。
- `Settings` 的声明和 `Game.allTrackerUpdateEvents` 里的通知键：保持原样，前者保证已有 defaults 可读，
  后者只在偏好变化时请求一次全量刷新，都不是显示判定。

因此设置页勾选该开关不再只改变一部分 overlay；它对显示结果完全没有影响。没有选择从设置页撤掉它，
所以按任务书与 `_common.md` 的约束，没有修改 XIB 或本地化字符串。

`clearTrackersOnGameEnd` 的清空增加 `reset` 条件。正常结束路径本来就调用
`updateTrackers(reset: true)`，所以开关启用时仍会在结束刷新清空一次；窗口在同一轮由对局门隐藏，
用户看不到的结果不变。后续不带 reset 的普通刷新不再反复向隐藏 tracker 写空数组。

T4 的三行行为没有改动：两个主记牌器的 `shouldShow` 条件原样保留；对局中仍由对局门放行双方，排队入口
仍只存在于我方主记牌器，主菜单与结束状态仍关闭双方。此次只让法力上限和计数器复用已存在的对局门，
没有改任何刷新 block、投递顺序、防抖参数或默认值。

静态可证明：对局门在 `gameEnded == true` 或 `isInMenu == true` 时关闭；战棋仍由已有
`isBattlegroundsMatch()` 条件关闭资源窗口和计数器；T4 的排队入口及两个主记牌器条件没有变化；结束清空
仍由 `gameEnd()` 的 reset 刷新触发。需要用户在下一局标准模式实战确认：结算瞬间两个主记牌器与法力上限
窗口在视觉上同一轮消失。用户不玩战棋，战棋不安排实战。

受限环境 Debug build：`BUILD SUCCEEDED`。首次沙箱构建因无法写 SwiftPM 缓存失败；同一命令用本机权限
重跑通过，属于沙箱权限假阴性，不是源码错误。

## review（2026-09-01）：通过

独立复跑受限环境 Debug build：`BUILD SUCCEEDED`。`shouldShowTracker` 已整个删除，
全仓库无残留引用（删掉一个 computed property 后还能编过，本身就是无悬空引用的证明）。

**重点核过一处最容易出事的地方：后台隐藏没有被顺手弄丢。** 用户 defaults 里
`hide_all_trackers_when_game_in_background = 1` 是开着的，而被替换掉的 `shouldShowTracker`
里本来含一条后台判定。核对结果是**两个新读者都不依赖它**：

- `updateMaxResourcesWidget`（`:681` / `:691`）外层本来就显式写着
  `(hideAllWhenGameInBackground && hsActive) || !hideAllWhenGameInBackground`，
  且没有 `|| selfAppActive` 逃生口 —— 它一直是更紧的那一条，替换不影响后台行为。
- `updateCounters`：`isTrackerGameActive` 只决定 `visibility`，真正 `show()` 的两处
  （`:604` / `:619`）各自带着同一条后台判定。

两个主记牌器的后台判定原样保留。**所以后台隐藏在四处都还在。**

另外确认两件不是本次引入、但读代码时会绊人的事：

- **计数器 overlay 在 `visibility == false` 时不会 `orderOut`** —— `:603` / `:618` 的
  `if visibility && count > 0` 为假时两个分支都不执行。但 `visibility` 的 `didSet` 会
  `refreshContent()`，而 `CountersOverlayContentView` 在 `:43` 用 `if visibility` 决定是否出内容，
  所以窗口留着但画的是空的。**上游设计，本次没动。**
- **`clearTrackersOnGameEnd` 收窄成 `reset && gameEnded` 之后变成了一次性的。**
  正常结束路径 `TagChangeActions.stateChange`（`:541-546`）是**先 `gameEnd()` 再置
  `gameEnded = true`**，靠 16ms 防抖 + 主队列跳转把顺序兜回来。以前每轮都清，兜不住还有下一轮；
  现在只有那一轮带 `reset`，理论上错过就不再清。该设置默认 `false`，实践中防抖窗口远大于
  解析线程的下一行，**判断为可接受**，但记着这是新增的单点依赖。

### 残留（已记进 PROGRESS 已知问题）

设置里「不在对局时隐藏全部记牌器」现在是个**完全没用的勾选框**。Codex 选的是"留设置、改读者"，
这是被约束逼出来的正确选择（撤控件要动 XIB，`_common.md` 禁止）。**Phase 4 做设置 UI 时一并撤掉。**
