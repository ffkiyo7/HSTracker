# 进度

> 计划全文见 `docs/PLAN.md`。本文件只记录**做到哪了 / 下一步是什么**，每完成一项就更新。

**最后更新**：2026-08-22
**分支**：`phase0+3`（基于 `master` = upstream `77a85be2` / **3.6.5**）—— 原名 `perf/phase0-overlay`；后续阶段落地后再改名
**构建状态**：Debug / Release 均 `BUILD SUCCEEDED`（clean + 增量都验证过，且是在剥掉 PATH 和代理的受限环境下）
**当前卡在**：无阻塞。**Phase 0 五项全部完成；Phase 1 的第一块（T1，卡行 + 主题缓存 + 并排比对窗）已合入。**
模型 A/B 于 2026-08-21 跑完（原定 8-22），结论是合 grok 那版，见下节。

**下一步**：Phase 1 的第二块切片。比对窗（`HSTRACKER_CARD_ROW_COMPARE=1`）已经在仓库里，
后续每块都用它验收。

**Phase 1 的 before 基线已收**（2026-08-22，Release + 同规格录像），见下面 8-22 那节。

**已跟上游 3.6.5**（2026-08-19）：`git merge master` 无冲突，两处重叠文件（`Game.swift` / `project.pbxproj`）
自动合并且两边改动都保留。3.6.5 对齐炉石 36.2.2（卡牌数据 248348 → 249896、BobsBuddy 1.57.6 → 1.62.1），
修了 Duos 里 Sandy 的崩溃，新增 Eternal Knight / Ancestral Automaton 两个战棋计数器。
**不产生新的本地化欠账** —— 3.6.5 没碰任何 `.xcstrings`，新文件里也没有用户可见文案。
顺带一提，上游 `89548845` 把 mirror 读取从 `currentGameType` 的 getter 里挪走了，和 Phase 0 同向。

---

## 2026-08-19 夜：跟上游 3.6.5 + 五处构建修复

合并本身无冲突，但**在 Xcode 里构建暴露了一连串问题**，全部修完并已推送：

| 提交 | 修的什么 | 性质 |
|---|---|---|
| `990af8ec` | Xcode 的 launchd 环境没有 homebrew，`wget` 找不到 | 环境（条件式） |
| `33a8b001` | 同上，没有代理，GitHub 拉不动；顺带给 100MB 卡牌数据加按版本缓存 | 环境（条件式） |
| `9648aabf` | `outputPaths`/`inputPaths` 写错 → Resources 拷贝冲掉 bundle 里的 `Cards/` 和 `Managed/arm64/` | **上游缺陷** |
| `9648aabf` | `ASSEMBLIES` 白名单漏 `System.Runtime.Intrinsics`（BobsBuddy 1.62.3 新增依赖）→ 改为拷贝整个 net8.0 | **上游缺陷** |
| `5e91c63f` | 启动自检抛未知异常时 `fatalError` 干掉整个 app | **上游缺陷** |

**验证方式已固化进 `AGENTS.md`**：必须在剥掉 PATH 和代理的受限环境下跑 clean + 增量两次。
先前三次「验证通过」全用 clean build，而 bug 只在增量构建触发 —— 这是这次排查最大的教训。

**遗留**：上游 3.6.5 的两个战棋计数器（Eternal Knight / Ancestral Automaton）**没登记进 pbxproj**，
上游发布版同样缺。`BobsBuddy-version.txt` 是装饰品，实际永远拉最新版。两者都待处理。

---

## 验收标准的修订（2026-08-20）

游戏内实测结果是「感觉不卡」，但这个标准**已被判定不合格**：M4 上记牌器让炉石掉帧属于工程事故，
不该拿它当及格线；而且它**不可比较** —— Phase 1 换 SwiftUI 之后无法判断是好了还是差了 5%。

真正的目标已经明确为**「抽到一张牌 → 右侧 overlay 有反应」的延迟**。已从代码读出预算：

```
炉石写 Power.log
   │   ← 炉石自己的 flush 延迟【未测，这是地板值】
LogReader 线程       Thread.sleep(0.05)              →  0~50ms
LogReaderManager     Thread.sleep(0.05)              →  0~50ms
Game._queue          guiUpdateDelay = 0.1            →  0~100ms
   ▼  updateAllTrackers() → 主线程
```

**我们自己造成的：均值 ~100ms，最坏 ~200ms**（T3 之前是均值 ~300ms / 最坏 600ms）。

三个候选优化，**必须先埋点测出炉石的 flush 地板再决定做哪些**：

1. GUI tick 改防抖（均值 50ms → ~5ms，最大单项收益，57 个调用点不用动）
2. 两个日志轮询用信号量串起来（均值 25ms → ~0）
3. 文件轮询换 `DispatchSource` 监听（均值 25ms → ~0，**收益完全取决于炉石 flush 行为**）

注：165Hz 外接屏下一帧只有 6ms，先前按 60Hz 定的 16ms 停顿阈值作废。

**2026-08-20 修正先验：延迟可能不是主因。**
读完 HDT（Windows 端，我们的上游）源码后发现，它的延迟预算**和我们完全一样**：

| 阶段 | HDT | 我们 |
|---|---|---|
| 日志文件轮询 | 100ms | 50ms |
| 汇总分发 | 100ms | 50ms |
| 触发 UI | **事件驱动，0ms** | **`guiUpdateDelay` 100ms 轮询合并** |
| 合计（均值 / 最坏） | 100 / 200ms | 100 / 200ms |

我们在日志层省下的 100ms，被 GUI 合并轮询原样吐了回去 —— 两边打平。
所以用户观察到的"HDT 明显更流畅"**不是延迟差异**，而是：

1. HDT 有 1.7s 的连续卡条动效（闪烁 → 布局塌陷 → 下方上移），把 100~200ms 的离散步进
   完全藏在 ramp 里；我们只有 alpha 动画、布局是一帧跳变，台阶完全裸露。
2. HDT 只更新变化的那一项（`ObservableCollection` + 对象池）；
   我们 `AnimatedCardList.updateFrames()` 每次刷新拆掉重建整棵子视图树。

**这直接改变候选优化的排序**：把 `guiUpdateDelay` 降到 16ms 的收益，
很可能小于把 HDT 那套动效补回来（见 PLAN 2.7 的 HDT spike）。
仍以 `LatencyProbe` 的 A 段实测为准，但先验已经变了。
完整调研见 `docs/research/hdt-overlay.md`。

### 2026-08-20 夜：埋点实测结果 —— 上面两版先验都不准

一整局标准模式（22:22–22:32），**Debug 构建**，`HSTRACKER_LATENCY_PROBE=1`：

```
A 日志行 -> 解析出来    n=3811  p50=197.5  p95=993.3   p99=1600.2  max=1773.7
C 置位   -> tick 消费   n=195   p50=106.4  p95=199.5   p99=233.3   max=937.2
D tick   -> UI 提交     n=160   p50=179.6  p95=819.1   p99=1324.8  max=1749.0
E2E 日志行 -> UI        n=146   p50=479.8  p95=1872.7  p99=6576.2  max=9038.3
```

**E2E 中位数 480ms**，不是本文件上面从代码推出来的「均值 ~100ms / 最坏 ~200ms」。差了近 5 倍。
p99 6.5s、max 9s 都在 10s 丢弃线以内，是真样本不是噪声。

三段的归属：

| 段 | 实测 p50 | 谁的责任 | 能不能动 |
|---|---|---|---|
| A 日志行 → 解析 | 197ms | 炉石 flush + 我们 50+50ms 轮询 | 地板，HDT 吃同样的亏 |
| C 置位 → tick | 106ms | `guiUpdateDelay = 0.1` | **能**，改防抖 |
| D tick → UI 提交 | 180ms | 我们自己 | **能**，但先要搞清是什么 |

**C+D = 286ms，占 E2E 的 60%，全在我们手里。** 所以上面那条「延迟不是主因」的修正**转向过头了**：
动效要补，延迟也确实有大头可捡，两件事都得做。

D 段有两个坑要注意：

1. **D 不是纯渲染成本。** `updateStarted()` 打在 `Game.swift:1581`（`internalUpdateCheck`），
   `updateCommitted()` 打在 `Game.swift:415`（`updatePlayerTracker` 主线程块末尾），中间隔着一个
   `DispatchQueue.main.async`。所以 D = **排队等主线程 + 真正干活**。p50 180ms / p95 819ms
   说明主线程本身是堵的，光优化 `updateFrames()` 未必够。
2. **D 的样本数（160）少于 C（195）。** 有 35 次 tick 起来了却没走到玩家追踪器提交，
   路径待查（可能是 tracker 不可见时的提前返回）。

**这组数字是 Debug（`-Onone`）构建，不能当基线。** Swift Debug 在热路径上慢数倍，
D 里有多少是构建配置、多少是我们的代码，必须用 Release 版跑同一局才能分开。**Release 对照未做。**

### 同一局的录屏分析（1920×1080@120fps，40s 窗口）

用 `tblend=difference + signalstats` 逐帧差分，统计游戏区（避开两侧面板）动画进行中
「相邻新画面的间隔」：

| 间隔 | 占比 | 等效帧率 |
|---|---|---|
| 1 帧 | 61.8% | 120 fps |
| 2 帧 | 25.8% | 60 fps |
| 3 帧 | 6.5% | 40 fps |
| **≥4 帧** | **5.5%** | **<30 fps** |

40 秒 101 次超过 33ms 的空档，最长 100ms —— 掉帧是真的，量级与「稍微掉帧、不太明显」相符。

**但卡顿和 overlay 重绘无关**：把卡顿时刻与面板重绘时刻交叉，落在重绘 ±100ms 内的占 24.8%，
而重绘窗口的时间覆盖率（随机基线）是 29.2% —— **低于基线**。
这只排除了「重绘尖峰砸帧」，没排除 Debug 版的弥散 CPU 占用。
录屏本身（4K 165Hz 面板采集成 120fps）也是重大嫌疑，同样未排除。
**待做对照：退掉 HSTracker 只录 40 秒，跑同一套分析。**

方法学备忘（下次复用）：单行像素扫描不可用，游戏背景噪声太大；
必须用 `crop` 取带 + `signalstats` 求区域均值。**任何面板内的亮度变化都要拿面板外的
纯游戏区域做对照** —— 本次就有一个假警报：面板整列「瞬间变暗、维持 1s、瞬间恢复」
一度被当成我们 alpha 动画的 bug，对照发现游戏区和面板区同帧一起暗、同帧一起亮，
那是炉石抓牌时的全屏压暗透过 `tracker_opacity = 0` 的透明面板漏过来的。

### 尺寸的实机确认

截图为 3840×2160（物理像素，2x；逻辑分辨率 1920×1080）。实测行距 **29pt**、面板宽 **186pt**，
与 `card_size = 1`（`medium`，`kMediumRowHeight = 29`、`kMediumFrameWidth ≈ 185`）一致。
即 PLAN 2.8 的对比表应以 medium 而非 `.big` 为准：宽度只差 8%，**行高差 38%**。
卡条贴图是 217×34 的 1x PNG，画在 186×29pt = **372×58 物理像素**上，放大 1.7 倍 —— 2.8 里
担心的贴图问题在这块屏上是实际发生的。

素材留档：录屏 `~/Movies/2026-08-20 22-21-48.mp4`（552s），截图
`~/Desktop/Snipaste_2026-08-20_22-25-23.png`。这是**改动前的基线**，动效补回来之后按同样方式再录一次对比。

---

## 2026-08-20 夜：T4 部署目标 → macOS 14.0

`MACOSX_DEPLOYMENT_TARGET` 由 `10.14` 升到 `14.0`，只改 app target 的 Debug / Release 两行。
pbxproj 里共 6 处：工程级默认 `10.12` ×2、HSTrackerTests `11.0` ×2 都没动（app target 的值会覆盖工程级）。
`Info.plist` 的 `LSMinimumSystemVersion` 写的是 `$(MACOSX_DEPLOYMENT_TARGET)`，自动跟着走，不用改。

**这一步不改善性能，是 Phase 1 的前提** —— `@Observable` / Observation 框架要 macOS 14。
代价是本 fork 从此**不能在 macOS 13 及更早的系统上运行**；个人自用版，可接受。

那 97 处 `@available(macOS 10.15, *)` 守卫按计划没动，升级后只是恒真，编译器没有为此报警告。

代码由本机 grok-4.6（`--effort high`）按 `docs/tasks/phase0-t4-deployment-target.md` 写成，diff 恰好 2 行。
review 时在受限环境下自跑三轮验证：Debug clean、Debug 增量、Release 全部 `BUILD SUCCEEDED`，
且三层都对上了 —— `-showBuildSettings` 生效值 `14.0`、产物 `Info.plist` 的
`LSMinimumSystemVersion = 14.0`、Mach-O `LC_BUILD_VERSION minos 14.0`（SDK 26.5）。

### 升级后新增的两处 deprecated 警告（都没修，都要留意）

| API | 位置 | 说明 |
|---|---|---|
| `.activateIgnoringOtherApps` | `AppDelegate.swift:257`、`NSAlert.swift:28`、`CoreManager.swift:446` | macOS 14 起该选项被系统忽略，改成协作式激活。`bringHSToFront()` 和弹窗前置**可能行为已变**，下次开游戏时留意 alert 会不会被压在炉石后面 |
| `CGWindowListCreateImage` | `SizeHelper.swift:236` 的 `screenshot()`（3 个调用点在 `ImageUtilities.swift`） | 官方推荐 ScreenCaptureKit。目前仍可用，只是 deprecated；部署目标 ≥14 之后迁移不再有版本包袱 |

其余源码警告（`NSUserNotification`、`allowedFileTypes`、`borderType`、`CC_MD5` 等）升级前就有，与部署目标无关。

### 顺带发现、按「只改任务书指定的那个文件」没动的两处过期描述

1. `PreferencePaneController.swift:21` 的注释要求 tab icon 用 PDF 而非 SVG，理由是
   「the app's macOS 10.14 deployment target；asset-catalog SVG requires 10.15+」——
   **这个理由已经不成立**。它是上游 `bdb0ec12` 写的，改了会和上游冲突，先记在这里。
2. `README.md:9` 写「macOS 10.10 or higher」，上游升到 10.14 时就没跟，同样没动。

---

## 2026-08-21 凌晨：Release 版对照 —— Debug 的锅有多大

同一套探针、Release 构建、一整局标准模式（00:06:48–00:16:18），OBS 与 8-20 那轮同规格
（1920×1080@120fps），保持录屏这个负载恒定，否则差值里会混进第二个变量。

| 段 | Debug（8-20） | Release（8-21） | 结论 |
|---|---|---|---|
| A 日志行 → 解析 | p50 197.5 / p95 993.3 / max 1773.7 | p50 **150.3** / p95 **227.9** / max **296.6** | 长尾塌了 |
| C 置位 → tick | p50 106.4 / p95 199.5 | p50 **106.9** / p95 195.3 | 纹丝不动 |
| D tick → UI 提交 | p50 179.6 / p95 819.1 | p50 **20.1** / p95 273.5 | **-89%** |
| E2E 日志行 → UI | p50 479.8 / p95 1872.7 | p50 **309.8** / p95 **787.4** | -35% |

**D 段那 180ms 里约 160ms 是 Debug `-Onone` 的锅，真实渲染成本只有 20ms。**
这直接推翻本文件上面「D 段 + 动效缺失才是主因」的排序 —— 渲染这块没肉了。

A 段也要重新理解：地板不会因为换构建配置就塌一半，所以 Debug 那条 p95 993ms 的长尾
**是我们自己的解析积压**（解析慢 → 行在队列里排队 → `processLine` 拿到时年龄已经很大），
不是炉石的 flush。Release 下 A 的 max 只有 297ms，与「50+50ms 轮询 + 炉石 flush ~100ms」吻合。

C 段与构建配置无关（它就是 `guiUpdateDelay = 0.1`），**现在是 E2E 里最大的一块可控成本，占 35%**。

### 优化排序（替换上面 2026-08-20 那版）

| 候选 | 现在的收益 | 说明 |
|---|---|---|
| 1. GUI tick 改防抖 | **~100ms** | C 段 p50 107ms 几乎可全部拿掉，仍是最大单项 |
| 2. 两个日志轮询用信号量串起来 | ~50ms | A 段里属于我们的那部分 |
| 3. 文件轮询换 `DispatchSource` | ~25ms | 取决于炉石 flush 行为 |
| ~~4. 优化 `updateFrames()`~~ | **~0** | D 只有 20ms，Phase 1 的理由只剩动效和分区，不再是延迟 |

1+2 做完，E2E p50 有望 310ms → ~160ms。

### 机制修正：C 段等的是一整个周期，不是半个

PLAN 按「轮询平均等半个周期」估的 50ms → 5ms。实测 **C p50 = 106.9ms ≈ 一个完整周期**、
max = 199.7ms ≈ 两个周期，比那个估计差一倍。

原因是对局激烈时日志事件几乎不断：`updateTrackers()`（`Game.swift:243`）把标志置上，
`internalUpdateCheck()`（`:1562`）当拍清掉，**下一个请求立刻又把它置上** ——
于是每次刷新都要等满一整个周期，而不是平均半个。
**所以防抖的实际收益是 ~100ms → ~5ms，比 PLAN 估的更大。**

p95 那 195ms（约两个周期）最可能来自 `internalUpdateCheck()` 里每 250ms 一次的
`SizeHelper.hearthstoneWindow.reload()` —— 4 次阻塞式跨进程 AX 调用，**和 tick 跑在同一条
串行队列 `_queue` 上**，炉石忙时会把下一拍整个推后。这是 T3 review 时为了跟窗加的
（见「与计划不一致的地方」），当时只考虑了 AX 调用频率，没意识到它会挤占 tick 的时序。
改防抖时应当把它挪到独立队列，顺手削掉这条尾巴。

另外读代码时确认：`updateAllTrackers()`（`:208`）一次派发 **20 个** update 方法，
每个都立刻 `DispatchQueue.main.async`，所以 `_queue` 上的 body 本身很轻，
真正的成本全在主线程那 20 个块里。而 **D 段只测了其中 1 个**
（`updateCommitted()` 打在 `:415` 的 `updatePlayerTracker` 主线程块末尾），
其余 19 条路径没有任何数据 —— 「渲染只要 20ms」这个结论的适用范围比字面上窄得多。

### E2E 的 p99 / max 不可信（探针的归因缺陷）

Release 这轮 E2E p99=8122 / max=9168，但 **A+C+D 三段的 max 加起来只有 906ms**
（297+200+409）。差的 8 秒多不在任何被测段里，只能落在没埋点的 B 段。
更可能是**归因错了**：`updateRequested()` 记的是「最后一行日志的时间戳」，而有些刷新
根本不是日志触发的（`Game.swift:1725` 的 1 秒后重试 `cacheGameType`、`:3446` 的 300ms 后
补刷 ritual、`:62` 的 1 秒后延迟刷新等）。这时 `lastLineClock` 可能已陈旧数秒，
算出来的「日志行 → UI」是个假数字。n=89 时 p99 就是第 2 差的样本，两个异常点足以撑起尾巴。

**E2E 的 p50 / p95 可信，p99 / max 先别当真。** 要修就给 B 段补埋点，
或在 `updateRequested()` 里把非日志触发的刷新标记出来单独排除。

样本数从 C 195 / E2E 146 掉到 C 101 / E2E 89，而 A 段行数相当（3811 vs 3587），
说明局长可比 —— 少的是刷新次数：Release 解析快，更多置位在同一个 tick 里被合并了，这正是设计意图。

### 掉帧：不是我们造成的

同一局录像跑上次那套 `tblend=difference + signalstats`（游戏区取带 `crop=1100:300:410:450`）。

**方法修正：整段视频直接比是无效的。** 两局内容不同、空闲时长不同，而「没有新画面」
和「掉帧」在指标上无法区分。按整段算 Release 反而差一倍（≥4 帧 3.9% vs Debug 2.0%），
这是内容差异造成的假象。改成按「动画确实在进行的时段」归一化
（1 秒滑窗、窗内新画面占比 ≥60% 才计入）之后：

| 阈值 | Debug ≥4 帧 | Release ≥4 帧 | 对照组 ≥4 帧 | Debug >33ms | Release >33ms | 对照组 >33ms |
|---|---|---|---|---|---|---|
| 0.05 | 1.4% | 2.6% | 1.7% | 51 次/40s | 95 次/40s | 49 次/40s |
| 0.10 | 1.5% | 1.8% | 3.7% | 51 次/40s | 64 次/40s | 100 次/40s |
| 0.20 | 1.9% | 1.8% | 1.2% | 59 次/40s | 56 次/40s | 28 次/40s |

**对照组来自一段误开的录像**：`~/Movies/2026-08-21 00-04-08.mp4`（17s，炉石主菜单，
HSTracker 完全没启动）。

两件事：一是 Debug 与 Release 的差异**在阈值之间来回翻转**（0.05 时 Release 差一倍，
0.20 时反而略好），说明已经到了这套方法的分辨极限，不该从中读出方向性结论；
二是**对照组横跨了同样的范围** —— 掉帧在 HSTracker 根本没运行、画面上只有一个静态主菜单时照样发生。

结合上次的交叉相关（卡顿落在重绘 ±100ms 内占 24.8%，低于 29.2% 的随机基线），
**在这套录屏方法的精度内，掉帧不是 HSTracker 造成的**；头号嫌疑仍是采集管线
（4K 165Hz 面板压成 1080p120）。「退掉 HSTracker 录 40 秒」这个对照优先级因此降低 ——
真要排除录屏管线，应该换一个不经过 OBS 的测量手段，而不是再录一段。

工具已固化为 `docs/tasks/tools/frame_gaps.py`（`--busy` 就是上面这个归一化，跨录像对比必须加）。
素材：`~/Movies/2026-08-21 00-07-23.mp4`（Release 那局，477s）。

---

## 2026-08-21：T5 —— GUI 刷新由轮询改为防抖调度

按上面重排后的第 1 项动手。任务书 `docs/tasks/phase0-t5-gui-debounce.md`，
代码由本机 grok-4.6（`--effort high`）写成。

**改动**：`updateTrackers()`（`Game.swift:243`）置位后直接排一次 16ms 的合并刷新，
取代原来 100ms 的自轮询。`internalUpdateCheck()` 拆成两半 ——
`housekeepingTick()`（窗口轮询 250ms 节流 + `updateBoardOverlay()`）搬到新的
`_windowQueue`，`applyWindowChange()` 留在 `_queue`。51 个 `updateTrackers()` 调用点一处未动。

预期 C 段 p50 由 106.9ms 降到 ~16ms + 上一轮主线程耗时。

### 三个必须记住的设计点

1. **不是经典 trailing-edge debounce。** 那种「每次新请求都把定时器推后」的写法，
   在日志密集时请求永不停歇 → 定时器无限推后 → **overlay 永远不刷新**。
   这里是「第一个请求排一次、窗口内后续只置标志」（`guard !guiUpdateScheduled`）。
2. **`guiUpdateInFlight` 不是可选项。** 防抖窗口 16ms，而 D 段 p95 有 273ms ——
   没有在途标志，上一轮还堵在主线程时下一轮就排进去了，必然堆积。
   有了它节奏自动变成「上一轮主线程耗时 + 16ms」，**由结构保证压不垮主线程**。
   完成时机靠一个排在那 20 个块之后的 marker 判断（主队列 FIFO）。
3. **`Game.swift:857` / `:868` 两处曾直接写 `guiNeedsUpdate = true`**，不走 `updateTrackers()`。
   有轮询兜底时它们照样生效，改成事件驱动后**将永远等不到刷新** ——
   这是「单看任务本身发现不了」的组合型回归，和 T3 那次同一类。两处已改走 `updateTrackers()`，
   顺带消掉了它们对 `_queue` 私有状态的数据竞争（一处跑在主线程上）。

顺带把 `SizeHelper.hearthstoneWindow.reload()`（4 次阻塞式跨进程 AX 调用）挪出 `_queue`。
它和 tick 共用一条串行队列，正是 C 段 p95 195ms（约两拍）最可能的来源。

### review 时改了什么

**注释语言。** grok 把任务书里代码片段的中文注释原样抄进了 `Game.swift`，
而这个仓库的代码注释一律英文。已全部改写为英文。**这是任务书的锅** ——
以后往任务书里贴代码片段，注释就得先用英文写好。

### 验证与遗留

Debug / Release 构建均 `BUILD SUCCEEDED`（受限环境）。**按判断没做游戏内实测**：
改的是调度时序，正确性由构建 + 上面三点的代码审查覆盖。

**但收益数字尚未实测。** 想确认 C 段真的降下来了，就再跑一次探针
（`HSTRACKER_LATENCY_PROBE=1`，Release 版，一整局），拿去和 8-21 那组
`C p50=106.9 / E2E p50=309.8` 对比。`guiUpdateDebounce = 0.016` 是有理由的初值而非实测最优，
调它必须拿探针数据说话。

一个已知的副作用：窗口矩形变化触发的刷新会打出 `updateStarted()` 却没有配对的
`updateRequested()`，于是产生没有 C 样本的 D 样本（旧代码在那条分支上连 `updateStarted()`
都不打）。拖动窗口时才会发生，不影响日志驱动的 C/D/E2E 基线，但对比时要知道有这回事。

---

## 2026-08-21：Phase 1 / T1 的模型 A/B —— **grok 版已合入**

任务书 `docs/tasks/phase1-t1-card-row.md`（60 行、0 代码块，按 AGENTS.md 新规矩只给约束）。
两份产出各自提交在 `ab/t1-grok`（`e831fefa`）和 `ab/t1-codex`（`3bf73187`），是**未经人工修改的原始输出**，都没 push。
worktree 在 `~/Desktop/dev/HSTracker-ab/{grok,codex}`，日志在同目录 `logs/`。

**结论（8-22 人工看过比对窗后确认）：合 grok 那版。**
决定性的是描边那条 —— 见下面「正确性」一节，它是换方案才能修的结构性差异，
而 grok 那版的两处错都是一行的事。codex 版保留在 `ab/t1-codex` 作对照，worktree 不删。

### 跑之前必须先填的三个 worktree 坑

1. **`_common.md` 把仓库根写死成 `/Users/wadorudi/Desktop/dev/HSTracker`**，验收构建那段还以 `cd` 到该路径开头。
   照做的话两个模型会去构建甚至改动主仓库或对方的 checkout。已改成「仓库根就是你当前工作目录」（`50e2ec7f`）。
2. **`Config.xcconfig` 是 `skip-worktree` 的本地签名版**，新 worktree checkout 出来的是 Developer ID 那版。
   已在两个 worktree 各写本地签名版并各自 `git update-index --skip-worktree` ——
   否则它会出现在 `git diff --stat` 里，**直接打破任务书验收第 3 条**。
3. **`downloaded-frameworks/` 是 `$SRCROOT` 相对且 gitignored**（269MB）。用 APFS clone（`cp -Rc`）复制进两个 worktree，
   秒完、不额外占盘，省掉两遍 100MB `CardDefs.xml` 下载。

两边先各跑一次基线构建确认环境（150s / 130s，都 `BUILD SUCCEEDED`），起跑时冷热一致。

### 结果

| 维度 | grok-4.6 high | GPT-5.6-sol medium |
|---|---|---|
| 耗时 | 17m40s | 12m59s |
| token | **不可得** —— `--output-format plain` 不打账 | 280,815 |
| 产出 | 1004 行 / 3 文件 | 573 行 / 3 文件 |
| 既有文件 | pbxproj +20、AppDelegate +2 | pbxproj +20、AppDelegate +11 |
| pbxproj 4 处登记 | 3 个文件都 4/4 | 3 个文件都 4/4 |
| 一次过 | 否，自修一轮（仓库的 `enum State` 撞 SwiftUI `@State`） | 否，自修至少一轮 |
| 自验做到哪 | 构建 | 构建 + `plutil -lint` + `git diff --check` + **真的启动 app 确认比对窗打开** |

**沙箱不对等，记一笔**：grok 用 `--permission-mode auto`（无沙箱），codex 那边
`--dangerously-bypass-approvals-and-sandbox` 被 Claude Code 的分类器拦了，退而用
`--sandbox workspace-write` + `network_access=true` + `--add-dir` 放行 DerivedData 和 SPM 缓存。
codex 受的限制略紧，耗时对比要打这个折扣。

### 正确性：拿 `CardBar` + 四个子类逐条核

**grok 更忠实的三处**

- **文字描边。** `CardBar.add(text:)` 用 `.strokeWidth: -2.0`（cost 是 `-1.0`）+ `.strokeColor: .black`。
  grok 用 `NSViewRepresentable` 走同一条 NSString 绘制路径，连 `minimumScaleFactor = 0.001` 都一样；
  **codex 用四个 1px 阴影模拟描边**。`strokeWidth` 是字号的百分比、阴影是固定像素，
  行高 17 的 tiny 档会明显偏重。这一条直接顶在验收第 1 条「视觉不可区分」上。
- **`addCardImage` 的运算符优先级。** `offset && abs(count) > 1 && playerType != .editDeck || rarity == .legendary`
  没加括号，`&&` 结合更紧，所以 **frost / minimal（`offsetByCountBox: false`）遇上传说卡仍要位移 `imageOffset`（-23）**。
  grok 复刻了并在注释里点名；codex 的 frost 写死 `-1`、minimal 用 `frameRect`，传说卡的卡图位置会错。
- **两档缩放比。** `CardBar` 的 `ratioWidth` / `ratioHeight` 是两个值，且有 `baseHeight > bounds.height` 的分支；
  grok 复刻，codex 只用一个比值。（codex 那版在 huge 档反而更"对"，但不忠实 —— 见下面两边都发现的 `AnimatedCardList` 隐患。）

**codex 更忠实的两处**

- `MinimalBar.countTextColor` 用的是 `card.rarity`，**不是**把 ELITE 折算成 legendary 之后的 rarity。codex 对，grok 错。
- darken 的条件 `&& playerType != .cardList && playerType != .editDeck`，codex 有，grok 漏。
  （反过来，卡名/费用在 cardList / editDeck 下强制白色这条，grok 有、codex 漏。）

**一处工程性差异单独记：codex 缺图时用 `preconditionFailure` / `precondition`。**
`precondition` 在 `-O` 下不会被剥掉，所以主题少一张 PNG 的后果是 **Release 崩溃**；
而 `CardBar` 的 `hasAllRequired` 是「这一帧不画」。任务书写了「不要崩、不要报错」。

### 自主性：两边都超预期，而且互相印证

两个模型**各自独立**报出了同样两条范围外的问题：

- **`Resources/Small/<cardId>.png` 在 bundle 里不存在** → `MinimalBar.swift:32` 那条模糊卡图路径是死的。
  已 `ls` 验证：`HSTracker/Resources/` 下确实没有 `Small/`。所以 Minimal 主题新旧两侧都没有卡图。
- **`AnimatedCardList` 在 `cardHeight == nil` 时拿 `kHighRowFrameWidth`（宽度常量，~332）当 huge 档的行高。**
  实战路径 `Tracker` 会传真值所以碰不到，但是个埋着的雷。

两个独立实现同时指向同一处，可信度比任何单边报告都高 —— 这是双模型对照最实在的收益。

grok 另外报了四条（`ClassicBar.textFontSize` / `_costRect` 定义了没用、`cardLayer` 从不接内容每帧被清、
`flashLayer` 只加不删、上游两个战棋计数器仍没进 pbxproj）；codex 另外报了启动时 OAuth `invalid_grant`（真跑起来才看得到）。

codex 有一条态度值得记：它明说「macOS 拒绝了自动屏幕截图，因此没有冒充完成最终肉眼像素验收」——
**主动声明自己没做到**，而不是含糊带过。

### 挂载点：两种选法，理由都成立

- grok 选环境变量、**不加** `#if DEBUG`。理由：比对是 Phase 1 后续每块的验收产物，视觉基线是 Release 版，
  所以必须能在 Release 下开；而不许改 `.xib` 就没法给 Debug 菜单加项。
- codex 选 `#if DEBUG` + 环境变量，Release 里完全不存在。

grok 的理由是从任务书约束反推出来的，倾向它。

### 合入时 review 改了什么

只有两处，都是上面「codex 更忠实」那两条：

1. `countTextColor` 改用 `card.rarity` 而不是折算过 ELITE 的 `effectiveRarity` ——
   `MinimalBar.countTextColor` 用的是原始 rarity。
2. darken 补上 `&& playerType != .cardList && playerType != .editDeck`。

其余一行未动。合入后在受限环境（剥掉 PATH 和代理）跑了 Debug 构建，`BUILD SUCCEEDED`。

顺带核过、确认 grok 原样就是对的几处：卡名宽度的三段扣减（`- 38`、
`- boxRect.width`、`- abs(createdIconOffset)`）与 `addCardName` 一致；
gem 与 cost 一起开关是对的，因为 `addGem` 和 `addCost` 带的是同一对 guard
（`isHero && !isPlayableHero`、`cost < 0`）；classic 的卡名固定宽度对应
`ClassicBar.addCardName` 的覆写。

### 像素比对

`screencapture` 需要「屏幕录制」权限，本机终端没有，所以是**人工看的**（8-22，结论：grok 版明显更好）。
要再看的话：

```
env HSTRACKER_CARD_ROW_COMPARE=1 \
  ~/Library/Developer/Xcode/DerivedData/HSTracker-ajzeuoosmscserctkdytyfltkokj/Build/Products/Debug/HSTracker.app/Contents/MacOS/HSTracker

env HSTRACKER_CARD_ROW_COMPARISON=1 \
  ~/Library/Developer/Xcode/DerivedData/HSTracker-bbofxpfahpsxfaayfqgmlhsdaqjq/Build/Products/Debug/HSTracker.app/Contents/MacOS/HSTracker
```

（前者是 grok 版、后者是 codex 版；环境变量名两边不同。一次只开一个，两份产物共用同一份用户设置。）

---

## 2026-08-22：T5 之后的 Release 实测 —— 收益没兑现，且 D 段的量程存疑

Release 3.6.5（含 T5 + T1），一整局标准模式，OBS 同规格。
录像 `~/Movies/2026-08-22 00-31-43.mp4`，最终 dump 存档在
`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-22-release-t5.txt`。

| 段 | 8-21（T5 前） | 8-22（T5 后） |
|---|---|---|
| A 日志行 → 解析 | p50 150.3 / p95 227.9 | p50 162.5 / p95 285.6 |
| C 置位 → tick | p50 **106.9** / p95 195.3 | p50 **114.3** / p95 398.0 |
| D tick → UI 提交 | p50 20.1 / p95 273.5 | p50 **14.8** / p95 384.3 |
| E2E | p50 309.8 / p95 787.4 | p50 **283.3** / p95 1570.7 |

（8-22 那列 n=476/491/435，样本量足，C 稳在 114ms 不是噪声。）

**T5 预期的 ~100ms 没有兑现，C 段几乎没动。** 最可能的解释：

**`D` 段一直只测了十八分之一。** `updateCommitted()` 在 `Game.swift:453`，位于
`updatePlayerTracker` 内部，而 `updateAllTrackers()` 一共往主队列派 **18 个 block**，
玩家记牌器只是第一个。T5 的 `guiUpdateInFlight` 守卫等的却是**全部排空**。
于是 C ≈ 全量排空 + 16ms 防抖 ≈ 114ms —— 瓶颈从「100ms 轮询定时器」换成了
「一次完整刷新占住主队列多久」，两者数量级碰巧相同，所以 C 看着没变。

> **因此 8-21 那条「D 只有 20ms，渲染这块没肉了」的结论现在存疑。**
> 真实的一次完整刷新可能是 ~100ms 而不是 20ms。
> **没有去验**（把 `updateCommitted()` 挪到 `runGuiUpdate` 尾部那个 block 就能分辨），
> 因为它不阻塞 Phase 1：三条验收标准没有一条依赖这个数，
> 而两种读法对「该不该做 Phase 1」是同向的（若真是 100ms，理由只会更强）。
> **它阻塞的是 Phase 0 剩下的优化 2 / 3 和 `guiUpdateDebounce` 调参** ——
> 那几项动手前必须先把量程修好，否则又是拿错数排序。

### 卡牌消失时的"卡顿"：不是延迟，是没有过渡

实测反馈"卡牌从右侧消失时明显卡顿"。查下来是两件事叠加，都与 E2E 的 283ms 无关：

1. **`CardBar.fadeOut(highlight:)`（`:285`）的函数体只有一个 `if highlight { ... }`。**
   而调用方 `AnimatedCardList.remove(card:fadeOut:)`（`:164`）传的是 `card.card!.count > 0`。
   所以一张已打完变暗（count==0）的卡再离开列表时**淡出根本不播**，
   但那句 `asyncAfter` 仍然要等满 **600ms** 才把行删掉 —— 600 毫秒纹丝不动，然后一帧消失。
   那 600ms 本来就是留给 0.5s 淡出的，这条路径上是纯死等。
2. **数量变化（4→3）是插新 bar + 立即删旧 bar**，`fadeOut: false`，一帧跳变。

加上全局没有任何布局动画（HDT 有 1.7s 连续 ramp），"消失"永远表现为跳变。
**这两条不在旧 AppKit 布局里修** —— 见 PLAN，在旧布局上做动效是白扔的工，
留给 Phase 1 把列表换成 SwiftUI 之后一起解决。

---

## 2026-08-22：Phase 1 / T2 —— 卡行接进记牌器

任务书 `docs/tasks/phase1-t2-tracker-list.md`（68 行、0 代码块）。代码由本机 grok-4.6（`--effort high`）
一次跑成，日志在 `~/Desktop/dev/HSTracker-ab/logs/run-grok-t2.log`。A/B 已在 T1 结束，这次只跑 grok。

主牌表（`Tracker.swift` 的 `cardsView`）现在可以由 `Settings.useSwiftUITracker` 切到 SwiftUI 渲染。
两个新文件 `TrackerCardListView.swift` / `TrackerCardListViewModel.swift`，玩家和对手记牌器共用 `Tracker`，一起生效。

```
defaults write net.hearthsim.hstracker use_swiftui_tracker -bool true
```

### 默认值是 false，和 PLAN 第 3 节写的不一样

PLAN 说 `useSwiftUITracker` 默认 true，那是**全部验收通过后**的终态。现在按切片推进，
每一片都要在真实对局里看过才算数，而这台机器每天在打游戏 —— 默认值不能是没验收过的那条路径。
Phase 1 收尾时连同开关一起删掉。

### 挂载：宿主是 `cardsView` 的兄弟视图

`.xib` 不许改，`cardsView` 的 outlet 类型只能还是 `AnimatedCardList`。
grok 的解法是把 `NSHostingView` 包一层 `TrackerCardListHost`，程序里 `addSubview` 到 `contentView`，
和 `cardsView` 同级，两者按开关互相让位（一个 `isHidden = true` + `frame = .zero`）。
`Tracker.updateFrames()` 里原来读 `cardsView.count` 的两处换成 `mainListCount`，按开关取值。

从 SwiftUI 切回 AppKit 时对 `cardsView` 强制 `reset: true` —— 隐藏期间那份 diff 已经过期，
不重置会把回来的列表带偏。这一条是它自己想到的。

### 悬停：superview 遍历这次没删成，但也没扩散

`getHoverComponent()`（靠向上遍历 superview 猜分段）还在，因为 `DeckLens` / `DeckSideboards` 仍是
`AnimatedCardList`，那条路径还得用它。新路径不走它：分段身份在 `hover()` 时直接传参。
顺带把 tooltip 载荷从 `[String: Any]` 换成了一个 class —— 原因是 `Timer.userInfo` 里塞 Swift enum
会在桥接时丢类型，相关牌 tooltip 会静默失效。这是它自己发现并绕开的。

### review 时改了什么

一处。`TrackerCardRowID` 完全照 `AnimatedCardList.areEqualForList` 复刻（id + jousted + isCreated +
条件性 wasDiscarded + deckListIndex + `IncindiusCounter`），逐条核过是对的，但**这套键可以撞**：
一张创生牌同时在手上和在牌库里，两行的六个字段全一样。旧路径撞了会静默合成一行；
`ForEach` 撞 id 是未定义行为，可能少画一行 —— 在记牌器里就是牌数报错。
给 ID 加了个 `occurrence` 序号，正常情况恒为 0，撞了才编号。

### 第一次实测作废了：包里没有卡库

给出去的 Debug 包是增量 `build` 出来的，`Contents/Resources/Resources/Cards/` 整个不在。
一整局下来记牌器只有计数 / 抽牌概率 / 胜率三个框，一根卡条都没有 —— 看着像渲染层炸了，
实际是 `Database.swift:252` 读不到 `CardDefs.xml`，`Cards.by(cardId:)` 全返回 nil，卡表本身就是空的。

而且 `use_swiftui_tracker` 那一刻根本没写进 defaults，**这一局全程走的旧 AppKit 路径**，
T2 一点没被碰到。两件事叠在一起，这次实测零信息量。

机制和补救写进了 `AGENTS.md` 的「构建」一节：`Embed Mono` 不声明 outputs 所以每次都跑、
`Managed/` 能自愈；`Download cards XML` 声明了 outputs 会被跳过、`Cards/` 不能自愈。
**交给人实测的包必须 `clean build`。**

### 验证到哪

- 受限环境（剥掉 PATH 和代理）Debug 构建 `BUILD SUCCEEDED`，新文件没有新警告
- 两个新文件在 `project.pbxproj` 里各 4 处登记
- `git diff --stat` 多出一个既有文件 `CardRowView.swift`：协同高亮的边框要画在 gem/费用之后、
  卡名之前（对应 `CardBar.addHighlightColor` 的图层顺序），T1 把这层排除在范围外了。加的是默认
  `.none` 的参数，比对窗不传，外观不变。理由成立，接受
- **实战已过**（8-22 第二局，clean build + 开关打开）：卡条正常显示、位置对、整局没崩。
  没触发到的三项**不是没通过、是没条件**：协同高亮边框（那副牌里没有带联动规则的卡）、
  行高压缩（中号 29px + 高窗口，总高没溢出）、frost / minimal 的传说卡位移
  （用的是 dark 主题，`offsetImageByCountBox` 为 true，这条在该主题上不显现）。
  这三项不值得再打一局，改设置或用比对窗静态看即可

### 已知的、本切片故意没做的

- 动效全部没做：淡入淡出、抽卡闪光、位置动画。`AnimatedCardList` 那个 600ms 空等没有被搬过来
- `DeckLens` / `DeckSideboards` / 战棋三处仍是 `AnimatedCardList`，600ms 空等还在
- 协同高亮只画边框，没有闪光
- `Game.swift` 的 `playerTrackerUpdateEvents` 没加这个 key（任务书没允许改那个文件）——
  `defaults write` 不发通知，要等下一拍 tracker 刷新才生效

---

## 状态总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| T0 | 前置环境 | ✅ 完成 |
| T1 | `WindowManager.show()` 去抖 | ✅ 完成并 review |
| T2 | AX 调用移出主线程 | ✅ 完成并 review |
| T3 | 提高 tick 频率 + 跟窗 | ✅ 完成并 review（review 时加了一处设计改动） |
| — | **游戏内实测** | ✅ 已做（2026-08-19 夜）——「感觉不卡」，但**这个标准已作废**，见下 |
| — | **延迟埋点** | ✅ Debug（8-20）+ Release 对照（8-21）都已实测，优化顺序已重排 |
| T4 | 部署目标 → macOS 14.0 | ✅ 完成并 review |
| T5 | GUI 刷新改防抖（实测后新增） | ✅ 完成并 review；8-22 已实测，**预期收益未兑现**，见该节 |
| Phase 1 | SwiftUI 记牌器渲染 | 🟡 进行中 —— T1（卡行 + 主题缓存 + 比对窗）✅ 完成并 review |
| — | T1 切片的模型 A/B | ✅ 完成，合入 grok 版（codex 版留在 `ab/t1-codex`） |
| — | T2 卡行接进记牌器 | ✅ 完成并 review + 实战验过（8-22 一局）；开关默认关 |
| — | Phase 1 还剩 T3–T8 | ⬜ 切片划分见 `PLAN.md`「切片划分」一节 |
| Phase 2 | 记牌器分区（牌库/手牌/已打出） | ⬜ 未开始（依赖 Phase 1） |
| Phase 3 | 补全简体中文 | ✅ 完成并 review（未译 410 → 7，99.2%） |
| Phase 4 | 设置 UI + Dock 菜单 | ⬜ 未开始（**4.3 的阻塞已由 T4 解除**，三项都可随时开始） |
| Phase 5 | 计数器 overlay 可拖动 | ⬜ 未开始（新增，见 PLAN Phase 5） |

---

## 已完成的提交

```
a89fce6d  Record the T2/T3 window-polling interaction found on review
330ef0e8  Raise overlay tick to 10Hz and decouple window polling        ← T3
c6bab26f  Keep Hearthstone window Accessibility reads off the main thread ← T2
45d36c47  Only reassign overlay window properties when they change      ← T1
a7c1aaf2  Add Phase 0 plan and grok task books under docs/
1ff31cb1  Fix Embed Mono build phase for mono 8.0.29                    ← T0
```

T1/T2/T3 的代码由本机 grok-4.6（`--effort xhigh`）按 `docs/tasks/` 里的任务书写成，逐个人工 review 后提交。

## Phase 3 —— 补全简体中文（已完成）

zh-Hans 覆盖率 **436/846 (51.5%) → 841/848 (99.2%)**，剩 7 个是标点/字形 key（`""` `\n` `!` `?` `✕` `i`），有意不译。

代码由本机 grok-4.6（`--effort xhigh`）按 `docs/tasks/phase3-t*.md` 六本任务书依次写成，
每步之间有自动闸（`docs/tasks/tools/check_xcstrings.py`），六步的缺失数精确命中预期（271→271→271→147→92→7）。

| 任务 | 内容 | 产出 |
|---|---|---|
| T1 | 按 key 合并 `gaenyong/HSTracker@9e7b653f` | 补 139 条；77 条译法差异写进 `docs/tasks/phase3-t1-diff-report.md` |
| T2 | 清掉从不参与编译的 `.lproj/*.strings` | 删 104 个文件 / 72 个目录；可抢救译文 **0 条** |
| T3 | 修 3.3 两个"翻译了也不生效"的 bug | + `Archive`/`Unarchive` 两个 key，+ DEBUG 缺 key 日志 |
| T4 | 主 catalog `Localizable.xcstrings` | 124 条 |
| T5 | 设置窗口 6 个 catalog | 55 条 |
| T6 | 卡组/对局 4 个 catalog + 8 条"假翻译" | 85 + 8 条 |

**review 时另做了 72 处改动**（见下节）。

### 复用的外部译文

- `gaenyong/HSTracker@9e7b653f`（MIT）—— T1 的 139 条 + 采纳的 56 条差异。16 个 `.xcstrings` 已下到
  `.refs/gaenyong-9e7b653f/`（在 `.git/info/exclude` 里），合并可复现，不需要联网。
- T4 自己发现 `MulliganGV2_*` / `BattlegroundsXxx_*` / `ConstructedPreLobbyWidget_*` 与 **HDT 和 HSReplay 官方 i18n 是同一套 key**，
  按官方中文对齐 —— 这条路任务书里没写，是它自己找到的。

## 与计划不一致的地方

**T3 在 review 时改了设计。** 任务书原文写「去掉 `counter > 3`，每个 tick 都刷新窗口矩形」，按字面实现会引入一个回归：
T2 已把 `reload()` 从 `updateAllTrackers()` 里摘掉，于是 `reload()` 只剩在 `else` 分支里；日志密集时
`guiNeedsUpdate` 每拍为真，窗口矩形将长时间不刷新，overlay 被钉在旧位置 —— 比改之前更差。
这是 T2 与 T3 组合才出现的问题，单看任一任务都发现不了。

实际实现：把窗口轮询提到分支之外，并用独立的 **250ms** 阈值节流（不跟随 100ms 的 GUI tick）。
除了让两个分支都拿到新鲜矩形，也是因为每次 `reload()` 是 4 次阻塞式 AX 跨进程调用 ——
真按 10Hz 跑就是每秒 40 次打进炉石自己的 run loop，反而拖累我们想保住流畅度的那个进程。
250ms 把 AX 频率维持在接近原先的水平，同时把跟窗延迟从 ~2s 降到 ~250ms。

见 `Game.swift` 的 `windowPollInterval` / `lastWindowPoll`。

**Phase 3 的 3.2 前提是错的。** 计划说那套废弃的 `zh-Hans.lproj/*.strings` 里"有现成的中文翻译从未上线"，
可以先挖出来再删。实测挖不出东西：5 个 `Localizable.strings` 只有 5 条能对上我们缺的 key，且**全是英文原样**
（`"HSReplay" = "HSReplay";`）；`MainMenu.strings` 那 38 条全被 gaenyong 的 41 条覆盖。
更要紧的是它把 Deck 译作**「套牌」**，而现行 catalog 一律「卡组」——
`AppDelegate.swift:440` 按标题字符串找菜单项，真按计划去"挖"反而会弄坏中文下的菜单栏。
所以 T2 改成了「先证明它确实是死的 → 删掉 → 不许覆盖 T1 写的值」。

**Phase 4.2 的诊断也要修正。** 计划说合并 `MainMenu.xcstrings` 后菜单项查找会「变成中文能查到、英文查不到」。
实际不会 —— gaenyong 给 MainMenu 的译法与 `Localizable.xcstrings` 已有的**逐字相同**
（卡组 / 回放 / 最近回放 / 窗口 / 锁定窗口），所以 T1 落地后中英文两边都能查到，这个 bug **顺手被修好了**。
4.2 改成按 tag/outlet 定位仍然值得做（两个 catalog 任何一边以后重译一次就再次静默失效），
但它从「硬性前提」降级为「消除脆弱性」。

### review 时在 grok 产物之上做的 72 处改动

任务书禁止 grok 改既有译文，所以这些留给 review：

- **56 条**：采纳 `phase3-t1-diff-report.md` 里建议「采纳它」的 gaenyong 译法。值取自 `.refs/`，不取报告里的 markdown 单元格。
- **7 条**：报告里标「都不好」的，用它另拟的译法（`Fatigue : ` 的尾空格、`Show flavor text`→「显示卡牌趣闻」、
  两条 draw chance→「抽到概率」、`Arena or Brawl deck`→「竞技场或乱斗卡组」等）。
- **9 条**：我自己扫出来的 ——
  `MainMenu` 的「隐藏 其他」多一个空格（gaenyong 带进来的，macOS 系统菜单是「隐藏其他」）；
  「血量」→「生命值」×2；「友谊赛」→「好友对战」；「竞技模式」→「竞技场」×2；
  「旅店大乱斗」→「乱斗模式」；`DeckManager` 工具栏「存档」→「归档」×2（与 T3 补的 `Archive` 对齐）。

效果：跨 catalog 的术语漂移从 **37 处降到 0**（「套牌」23 处全清），
「同一英文译法不一」从 13 组降到 8 组，剩下 8 组都是有意的语境差异
（`mode_*` 系列统一带「模式」；工具栏项带宾语「删除卡组」而菜单项只写「删除」）。

另删掉 `HSTracker/TrackOBot/ko-KR.lproj/` —— T2 按规则没碰（不在任务书路径里）但报告了，同样是 0 引用的死文件。

---

## 埋点的分段定义（**已实测完毕**，结果见前面 8-20 / 8-21 两节）

> 这一节留作分段口径的定义。**下面那两句关于优先级的判断都已被实测推翻**，
> 以「2026-08-21 凌晨」那节的排序为准。**B 段至今没有埋点**，
> 而 E2E 的长尾恰恰落在这里 —— 要继续深挖就从补 B 段开始。

**四段：**

| 段 | 起点 | 终点 | 说明 |
|---|---|---|---|
| A | 日志行自带的时间戳（`LogDate`） | `LogReaderManager.processLine` 拿到它 | **包含炉石自己的 flush 延迟**，是不可优化的地板 |
| B | `processLine` 开始 | `updateTrackers()` 置 `guiNeedsUpdate` | 解析耗时 |
| C | `guiNeedsUpdate` 置位 | `internalUpdateCheck` 消费它 | 就是 `guiUpdateDelay` 那 0~100ms |
| D | `updateAllTrackers()` 开始 | 主线程 UI 提交完成 | 渲染耗时，Phase 1 要优化的就是它 |

统计 p50 / p95 / p99，落日志（`LatencyProbe`，`HSTRACKER_LATENCY_PROBE=1`，每 30s dump 一次、累计不清零）。

> **以下两条先验都已被 Release 实测证伪，留档以免重犯：**
> 「D 段（渲染）+ 动效缺失大概率是不流畅的主因」—— Release 下 D 只有 20ms；
> 「C 段那 100ms 未必是性价比最高的下手处」—— 它现在是最大的一块可控成本。
> 教训：**任何拿 Debug 构建得出的性能结论，在 Release 对照做完之前都不算数。**

---

## 环境备注（换机器或重开时需要）

1. `brew install wget` —— 两个 build phase 依赖它（下载 HearthMirror 和 Mono）。**不装必然构建失败。**
2. `Config.xcconfig` 已改为本地签名（`CODE_SIGN_IDENTITY = -`），并已 `git update-index --skip-worktree`，
   `git status` 里看不到它。换机器要重做这一步。
3. `project.pbxproj` 里 `NET_VERSION` 已由 `net7.0` 修为 `net8.0`（commit `1ff31cb1`）——
   这是修 upstream 的真实 bug，不是本地 hack。
4. SwiftLint **故意没装**。build phase 里未安装只告警、不阻塞；装了反而会给 grok 的验收构建引入无关失败。
5. git 身份是 repo-local 配置的（`ffkiyo7 / ffkiyo7@gmail.com`），没有写进 global。

## 待办清单里还欠的

- `docs/tasks/` 现有 Phase 0 和 Phase 3 的任务书。Phase 1 / 2 / 4 若也要交给 grok，需要按同样颗粒度另写。
- Phase 1 不建议整块丢给 grok —— 它按任务书执行很稳，但不会替你发现任务书本身有问题（T3 就是例子）。
- **Phase 3 遗留（都不阻塞任何事）：**
  1. `LadderTab` / `StatsTab` 有 16 条 zh-Hans 是 `Text Cell` / `Table View Cell` 这类 XIB 占位，
     gaenyong 拿英文原样填的。用户看不见，但它让覆盖率数字虚高。撤掉会让这两个文件永远显示"未翻译"，所以留着。
  2. `Base.lproj/` 里还躺着 6 个同样没被 pbxproj 引用的 `Localizable.strings`。
     意味着 `String.localizedString` 那条 "Base.lproj 回退" 分支永远取不到东西 —— key 不存在时只会原样返回 key。
     没删是因为 `Base.lproj` 是活目录（有在用的 `.xib`），混着删风险大。
  3. `HSReplayPreferences` 有几条旧译和英文对不上（`My Account`→「上传收藏」），双方 catalog 都没有更好的版本，
     需要人肉重译。
- **Phase 4 的前置已解除**：4.3（SwiftUI 重做设置页）依赖的 T4 已完成，三项现在都不依赖任何东西。
