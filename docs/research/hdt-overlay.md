# HDT overlay 调研 —— 我们上游的上游

> HSTracker 是 HDT 的 macOS 端口，两边的类名、方法名、字段名基本一一对应
> （`AnimatedCardList` / `AnimatedCard` ↔ `AnimatedCardList` / `CardBar`）。
> 所以 HDT 不是"另一个记牌器"，而是**我们这套代码本来该长成的样子**。
>
> 本文回答两个问题：
> 1. 抽牌时那套动效具体是什么（用户描述："闪烁几秒 → 从牌库消失 → 下方卡条向上合并"）
> 2. "流畅度比 macOS 这边好很多"到底来自哪里 —— **结论出乎意料，不是延迟更低**

**许可证警告**（比 Firestone 那篇更需要留意，因为同属 HearthSim 容易误以为可以互抄）：

| 仓库 | 授权 |
|---|---|
| `HearthSim/HSTracker`（我们 fork 的源） | **MIT**（`LICENSE`） |
| `HearthSim/Hearthstone-Deck-Tracker` | **`Copyright © HearthSim. All Rights Reserved.`**（README「License」节，仓库内无 LICENSE 文件） |

同一个组织，**授权不同**。HDT 的 C# / XAML **不能拷进我们这个 MIT 仓库**。
本文只记录行为与参数，实现必须用 AppKit / SwiftUI 重写。

## 素材与方法

| 来源 | 说明 |
|---|---|
| 源码 | `HearthSim/Hearthstone-Deck-Tracker@58b7799`（tag `v1.56.2`，shallow clone） |
| 截图 | 用户提供的实机 overlay 截图（海盗贼牌库 + ETC 分区） |
| 对照 | 本仓库 `HSTracker/UIs/Cards/CardBar.swift`、`HSTracker/UIs/Trackers/AnimatedCardList.swift` |

和 Firestone 那篇不同，这次**不需要逐帧测量** —— 动效参数是写死在 XAML 里的常量，直接读得到。

## 一、抽牌动效：三段 storyboard

全部定义在 `Controls/AnimatedCard.xaml` 的 `UserControl.Resources` 里。

### 1.1 `StoryboardUpdate` —— 闪烁（1.0s）

```xml
<Storyboard x:Key="StoryboardUpdate" Duration="0:0:1">
  <DoubleAnimation TargetName="RectHighlight" TargetProperty="Opacity"
                   From="0" To="1" Duration="0:0:0.5"/>
  <DoubleAnimation TargetName="RectHighlight" TargetProperty="Opacity"
                   From="1" To="0" Duration="0:0:0.5" BeginTime="0:0:0.5"/>
</Storyboard>
```

一个覆盖整条卡条的 `Rectangle`（`217×34`，`IsHitTestVisible="False"`），
填充是主题贴图 `ThemeManager.CurrentTheme.HighlightImage`（`Hearthstone/Card.cs:627`）。
**0.5s 淡入 + 0.5s 淡出，共 1.0s。** XAML 里的注释原文就是
`Highlight that flashes when user draws a card`。

### 1.2 `StoryboardFadeOut` —— 消失 + 向上合并（0.7s）

```xml
<Storyboard x:Key="StoryboardFadeOut" Duration="0:0:0.7">
  <DoubleAnimation TargetProperty="Opacity" From="1" To="0" Duration="0:0:0.7"/>
  <DoubleAnimation TargetProperty="(UserControl.LayoutTransform).(ScaleTransform.ScaleY)"
                   From="1" To="0" BeginTime="0:0:0.4" Duration="0:0:0.3"/>
</Storyboard>
```

**关键在 `LayoutTransform`，不是 `RenderTransform`。**
WPF 里 `LayoutTransform` 参与布局测量：`ScaleY` 从 1 连续收到 0，这条卡条的**布局高度**
就从 34px 连续收到 0，父容器每帧重新排版，下方所有卡条**平滑上移**。
用户看到的"向上合并"就是这个。换成 `RenderTransform` 只会把自己压扁，下方纹丝不动。

时序设计：前 0.4s 只淡出不塌陷（先让眼睛注意到"这条要走了"），后 0.3s 边淡边塌。

### 1.3 `StoryboardFadeIn` —— 插入（1.0s）

```
ScaleY 0→1，0.5s   +   Opacity 0→1，1.0s
```

新卡条是**"撑开"进来**的（布局高度 0 → 34px），下方内容被平滑推下去。
这就是用户记得的"洗入牌之后牌库区有卡条插入动画"——
方向是纵向撑开，不是横向滑入。

> `AnimatedCardList.xaml.cs:147-151` 有一条注释解释为什么必须**先启动动画再插进 UI**：
> `Otherwise the card will be initialized with Scale.Y=1 instead of 0` —— 否则会先闪一帧全高。

### 1.4 完整时序：抽走一张牌

`AnimatedCardList.DoUpdate` → `RemoveCard(card, fadeOut: true)`
→ `AnimatedCard.FadeOut(highlight: Count > 0)`：

```
t=0.00s  StoryboardUpdate 开始（await，阻塞后续）
t=0.50s  高亮满
t=1.00s  高亮归零，storyboard 完成
         ↓ Card.Update() → OnPropertyChanged(Background)
         ↓ 此时数字/暗化才变
t=1.00s  StoryboardFadeOut 开始
t=1.40s  开始塌陷，下方卡条开始上移
t=1.70s  高度归零，从 ObservableCollection 移除
```

**总计 1.7 秒**，全程连续。注意 `Card.Update()` 夹在两个 storyboard 中间 ——
**先闪，闪完才改数字**，不是同时。`Card.Update()` 只 raise 了 `Background` 一个属性
（`Card.cs:624`），也就是重渲染卡条贴图。

两个开关：

- `Config.OverlayCardAnimations`（总开关，默认 `true`，`Config.cs:625`）
- `Config.OverlayCardAnimationsOpacity`（默认 `true`，`Config.cs:628`）
  关掉后走 `StoryboardFadeInNoOpacity` / `StoryboardFadeOutNoOpacity` 变体，
  **只留高度动画、去掉透明度动画** —— 给直播推流用（`StreamingCapturableOverlay.xaml.cs:91`），
  因为半透明帧在部分采集卡上会拖影。

## 二、我们的端口丢了什么

`AnimatedCardList.swift` 是 `AnimatedCardList.xaml.cs` 的逐行 Swift 翻译 ——
`areEqualForList`、`toUpdate` / `toRemove` / `newCards` 的结构完全一致。
**但动画层没有跟着翻译。**

| | HDT | HSTracker | 位置 |
|---|---|---|---|
| 抽牌闪烁 | 1.0s（0.5 入 + 0.5 出），主题贴图 | **0.5s，只有淡出**（0.7 → 0，无淡入段） | `CardBar.swift:262-268` |
| 卡条移除 | 淡出 0.7s **+ 布局高度塌陷** | 只有 `alphaValue 1 → 0.3`，**无高度动画** | `CardBar.swift:285-292` |
| 下方卡条上移 | 随塌陷连续上移 | **无 —— 600ms 后整体跳一格** | `AnimatedCardList.swift:164-176` |
| 卡条插入 | ScaleY 0→1 撑开 + 淡入 | 只有 `alphaValue 0.3 → 1.0` | `CardBar.swift:275-283` |
| 数字更新时机 | 闪完（t=1.0s）才改 | 立刻 | — |
| 移除时机 | storyboard 完成回调 | **硬编码 `asyncAfter(600ms)`** | `AnimatedCardList.swift:167-172` |

### 2.1 没有布局动画，只有透明度

AppKit 的 `NSAnimationContext` + `animator()` 在 `CardBar` 里**只被用来动 `alphaValue`**。
卡条的 `frame` 是在 `updateFrames()` 里**直接赋值**的（`cell.frame = NSRect(...)`），
不走 animator，所以布局变化永远是一帧跳变。**这是"向上合并"缺失的直接原因。**

### 2.2 600ms 与 500ms 对不上

`fadeOut` 的动画时长是 `context.duration = 0.5`（`CardBar.swift:288`），
但 `remove(card:fadeOut:)` 用一个写死的 600ms `asyncAfter`
才把卡条从 `animatedCards` 里摘掉（`AnimatedCardList.swift:167-172`）。
中间这 100ms 卡条停在 α=0.3 不动，然后**瞬间消失**、下方全部跳上一格。

### 2.3 `updateFrames()` 每次都把整棵子视图树拆了重建

```swift
for view in subviews {
    view.removeFromSuperview()
}
for cell in animatedCards {
    y -= cardHeight
    cell.frame = NSRect(x: 0, y: y, width: frame.width, height: cardHeight)
    addSubview(cell)
}
```
（`AnimatedCardList.swift:186-199`）

而 `Game.updatePlayerTracker` 每次更新都会走到 `windowManager.show(controller:...)`
（`Game.swift:409`）→ `controller.updateFrames()`（`WindowManager.swift:448`）
→ `Tracker.updateFrames()` → `cardsView.updateFrames()`（`Tracker.swift:323`）。

**即：每一次记牌器刷新，30 条卡条全部 `removeFromSuperview` + `addSubview` 一遍。**
这正是 PLAN Phase 1.3「消灭每帧视图树重建」要解决的东西，这里是它最贵的一处实例。

对照 HDT：卡条是 `ObservableCollection<AnimatedCard>` 绑到 `ItemsControl`，
增删只影响变化的那一项；实例还进对象池
（`KeyedPool<AnimatedCard>(200)`，**按 card id 复用**，`AnimatedCardList.xaml.cs:26`），
复用到同一张卡时连重新绑定都省掉。我们这边是每次 `CardBar.factory()` 新建。

### 2.4 附带发现：`flashLayer` 的子层从不清理

`CardBar.update(highlight:)` 每次闪烁都 `flashLayer?.addSublayer(flashingLayer)`
（`CardBar.swift:261`），动画设了 `isRemovedOnCompletion = false`（`:266`），
而 `draw` 只清 `cardLayer` 的子层（`:302`），**`flashLayer` 没人清**。
同一条卡条闪几次就积几层。视觉上因为最终 opacity=0 看不出来，但层数确实在涨。

## 三、"更流畅"的真正来源 —— 不是延迟

直觉会认为 HDT 反应更快。**读完源码结论相反：日志层 HDT 反而比我们慢一倍。**

| 阶段 | HDT | HSTracker |
|---|---|---|
| 日志文件轮询 | `Thread.Sleep(100)`<br>`HearthWatcher/LogReader/LogFileWatcher.cs:267` | `Thread.sleep(0.05)`<br>`LogReader.swift:144` |
| 汇总 / 分发 | `Task.Delay(100)`<br>`HearthWatcher/LogWatcher.cs:71` | `Thread.sleep(0.05)`<br>`LogReaderManager.swift:139` |
| 触发 UI 更新 | **事件驱动，零延迟**<br>`GameEventHandler` 直接调 `Core.UpdatePlayerCards()`（40+ 处调用点） | **100ms 轮询合并**<br>`guiNeedsUpdate` 标志位 + `internalUpdateCheck` 每 100ms 消费一次<br>`Game.swift:42`、`Game.swift:1579-1599` |
| 合计（最坏） | 200ms | 200ms |
| 合计（均值） | 100ms | 100ms |

**两边一样。** 我们在日志层省下的 100ms，被 `Game.guiUpdateDelay = 0.1` 那个合并轮询原样吐了回去。

> 注：HDT 的 `Core.UpdateDelay = 16`（`Core.cs:46`）容易被误读成"60Hz 刷 UI"。
> 它驱动的是 `UpdateOverlayAsync()`，一个**进程/窗口状态看门狗**
> （检测炉石启动退出、region 变化），**不刷卡表**。别拿它当对标数字。

所以"HDT 更流畅"不是延迟差异，而是三件事：

1. **动效把离散步进藏起来了。** 1.7s 的连续过渡里，那 100~200ms 的日志延迟根本无处可见 ——
   眼睛跟的是 ramp，不是台阶。我们这边是"愣 100ms → 跳一下"，台阶完全裸露。
2. **布局连续 vs 布局跳变。** 见第二节。
3. **更新粒度。** HDT 只动变化的那一项；我们整棵树重建。

> **这个结论直接影响 PLAN 里候选优化的排序**：
> 把 `guiUpdateDelay` 从 100ms 降到 16ms 的收益，很可能**小于**把动效补回来。
> 等 `LatencyProbe` 的 A 段数据出来再最终定，但先验已经变了。

## 四、计数器可拖动 —— Phase 5 的现成答案

用户提的「场攻/无界空宇这些计数器不能拖」，HDT 早就解决了。

`Windows/OverlayWindow.Initialize.cs:131-144` 把 14 个元素登记进 `_movableElements`，
其中包含 `PlayerCounters` / `OpponentCounters`（`CountersOverlay`）、
`IconBoardAttackPlayer`（场攻）、`PlayerActiveEffects`、`PlayerResourcesWidget`、`LblTurnTime`。

拖动逻辑（`Windows/OverlayWindow.Input.cs:164-180`）：

```csharp
Config.Instance.PlayerCountersVertical   += delta.Y / Height;
Config.Instance.PlayerCountersHorizontal += delta.X / (Width * ScreenRatio);
Canvas.SetTop(el,  Height * Config.Instance.PlayerCountersVertical / 100);
Canvas.SetLeft(el, Helper.GetScaledXPos(
    Config.Instance.PlayerCountersHorizontal / 100, (int)Width, ScreenRatio));
```

三个设计点，**全部印证了 PLAN Phase 5「存锚点不存矩形」的判断**：

1. **存百分比，不存像素。** 换分辨率 / 窗口尺寸自动跟随。
2. **横向额外过 `GetScaledXPos(..., ScreenRatio)`。** 炉石画面在超宽屏上是居中 letterbox，
   直接按窗口宽度取百分比会飘；这个函数按画面实际比例折算。
   我们 `SizeHelper` 里有同类问题（外接 165Hz 显示器场景尤其相关）。
3. **玩家侧锚上边、对手侧锚下边**：
   ```csharp
   // player
   Canvas.SetTop(el, Height * pct / 100);
   // opponent
   Canvas.SetTop(el, Height - (el.ActualHeight * scale + Height * pct / 100));
   ```
   对手侧减去自身高度 —— 面板**朝远离锚定边的方向生长**。
   这正好解决 PLAN Phase 5 里担心的"计数器数量变化时布局往哪长"。

另有一个 UX 细节值得抄：进入解锁 / 拖动模式时调 `PlayerCounters.ForceShowExampleCounters()`
（`OverlayWindow.Input.cs:312`，退出时 `ForceHideExampleCounters()`，`:404`）——
**强制显示一组示例计数器**，否则当前没有任何计数器激活时用户看不到自己在拖什么。

## 五、结论

**要补的（按性价比排序）**

1. **卡条移除的高度塌陷动画** —— 用户最明确的诉求，也是"流畅感"的主要来源。
   AppKit 侧对应 `NSAnimationContext` 动 `frame`；Phase 1 之后走 SwiftUI 隐式动画。
2. **闪烁补上淡入段**（0.5s 入 + 0.5s 出）。现在只有淡出，观感是"突然亮一下然后消失"。
3. **移除时机改成动画完成回调**，去掉写死的 600ms。
4. **计数器拖动**，直接照 HDT 的百分比 + 双锚点方案（Phase 5）。

**不要照抄的**

- **1.7s 总时长偏长。** 它建立在 WPF 保留模式渲染上，而且卡条数字要等 1.0s 才变 ——
  快速连抽时会明显滞后于游戏画面。建议压到 **闪烁 0.4s + 塌陷 0.25s，数字立即更新**。
- **100ms 的日志轮询没有优势**，别跟。

**前提**

除第 2 条外全部依赖 **PLAN Phase 1.3 先干掉 `updateFrames()` 的整树重建** ——
在一个每次刷新都把全部子视图 `removeFromSuperview` 的容器里做布局动画，没有意义。

这一点和 Firestone 那篇的结论一致（[`firestone-overlay.md`](firestone-overlay.md) 第六节），
区别在于：Firestone 卡在 Angular 的 DOM 重建上是结构性无解，
我们这边是自己写的 `updateFrames()`，可以解。

**两篇调研放在一起看**

| | Firestone | HDT | 我们该做的 |
|---|---|---|---|
| 卡条插入 | 无动画（125ms 空白占位，是缺陷） | ScaleY 撑开 1.0s | 学 HDT，时长减半 |
| 卡条移除 | 无动画 | 淡出 + 布局塌陷 1.7s | 学 HDT，时长减半 |
| 跨分区移动 | 结构性做不到 | 无（HDT 没有分区） | **`matchedGeometryEffect`，两家都没有** |
| 关联高亮 | 8.3ms 硬切换 | — | 加 100~150ms 淡入（PLAN 2.6） |
| 状态表达 | 8 种 SVG 图标 | 暗化 + 图标 | 学 Firestone 的图标（PLAN 2.7） |
| 计数器 | 收进可折叠独立面板 | 可拖动，百分比 + 双锚点 | **两者结合**（Phase 5） |
