# 进度

| | |
|---|---|
| 最后更新 | 2026-08-22 |
| 分支 | `phase0+3`（基于 `master` = upstream `77a85be2` / **3.6.5**） |
| 构建 | Debug / Release 均 `BUILD SUCCEEDED`，受限环境（剥掉 PATH 和代理）下 clean + 增量都验过 |
| 阻塞 | 无 |
| **下一步** | **Phase 1 的 T3 切片**（ETC / 深邃之王 改悬停浮出） |

> 本文件只回答三件事：**做到哪了 / 下一步是什么 / 哪些结论还作数**。
>
> 过程记录（每个任务怎么做的、review 改了什么、模型 A/B 怎么比的、录屏怎么分析的）
> 已整体归档到 **`docs/archive/progress-detail-2026-08-22.md`**，本文件不再复述。
> 计划全文见 `docs/PLAN.md`。

---

## 状态总览

### Phase 0 — 地基（✅ 全部完成）

| | 内容 | 状态 |
|---|---|---|
| T0 | 前置环境（`wget`、本地签名、`net8.0` 修复） | ✅ |
| T1 | `WindowManager.show()` 去抖 | ✅ |
| T2 | AX 调用移出主线程 | ✅ |
| T3 | 提高 tick 频率 + 跟窗 | ✅ review 时改了设计，见 PLAN |
| T4 | 部署目标 → macOS 14.0 | ✅ |
| T5 | GUI 刷新改防抖 | ✅ 代码已合，但**实测收益未兑现**，见下节 |

### Phase 1 — SwiftUI 记牌器渲染（🟡 2 / 9）

| 片 | 内容 | 状态 |
|---|---|---|
| T1 | `CardRowView` + `ThemeImageCache` + 并排比对窗 | ✅ 合入 grok 版（模型 A/B 的产物，codex 版留在 `ab/t1-codex`） |
| T2 | 主牌表接进 `Tracker` + `Settings.useSwiftUITracker` 开关 | ✅ 实战验过一局，**开关默认关** |
| T3 | ETC / 深邃之王 改悬停浮出 | ⬜ 下一步 |
| T4 | 其余三段卡表 → `TrackerSectionView` | ⬜ |
| T5 | 顶部信息区重做（Firestone 三行头） | ⬜ |
| T6 | 根视图 + 布局收口 | ⬜ |
| T7 | 卡图异步加载 + LRU | ⬜ |
| T8 | 动效 | ⬜ |

**实测卡点**：① T3+T4+T7 → ② T5 → ③ T6 → ④ T8。分批理由见 PLAN 的「执行卡点」一节。
原来的 T9（删开关、删旧路径）**已挪到 Phase 2 之后**。

### 其余阶段

| | 内容 | 状态 |
|---|---|---|
| Phase 2 | 记牌器分区（牌库 / 手牌 / 已打出） | ⬜ 依赖 Phase 1 的 T4 / T6 |
| 收尾 | 删 A/B 开关、删旧路径 | ⬜ 排在 Phase 2 之后 |
| Phase 3 | 补全简体中文 | ✅ 未译 410 → 7（51.5% → **99.2%**） |
| Phase 4 | 设置 UI + Dock 菜单 | ⬜ 三项都不依赖任何东西，随时可开始 |
| Phase 5 | 计数器 overlay 可拖动 | ⬜ |
| Phase 6 | 排队时就显示牌组 | ⬜ 2026-08-22 新增；与 4.1 同根因，**改动很小，随时可插队** |

---

## 延迟实测

三轮探针数据（`HSTRACKER_LATENCY_PROBE=1`，各一整局标准模式，OBS 同规格录屏保持负载恒定）。
单位毫秒，格式 **p50 / p95**。分段口径见本文件末尾。

| 段 | 8-20 Debug | 8-21 Release | 8-22 Release（T5 后） |
|---|---|---|---|
| A 日志行 → 解析 | 197.5 / 993.3 | 150.3 / 227.9 | 162.5 / 285.6 |
| C 置位 → tick | 106.4 / 199.5 | 106.9 / 195.3 | 114.3 / 398.0 |
| D tick → UI 提交 | 179.6 / 819.1 | 20.1 / 273.5 | 14.8 / 384.3 |
| E2E 日志行 → UI | 479.8 / 1872.7 | 309.8 / 787.4 | 283.3 / 1570.7 |

### 仍然作数的结论

- **Debug 数据不算数。** D 段那 180ms 里约 160ms 是 `-Onone` 的锅。
  任何性能结论在 Release 对照做完之前都不成立 —— 这条踩过两次。
- **T5 预期的 ~100ms 没有兑现**，C 段只从 107 动到 114。
  瓶颈从「100ms 轮询定时器」换成了「一次完整刷新占住主队列多久」，两者数量级碰巧相同。
- 🔴 **D 段的量程存疑，这是个阻塞项。** `updateCommitted()`（`Game.swift:453`）只覆盖
  `updateAllTrackers()` 派出的 **18 个主队列 block 里的第一个**，一次完整刷新可能是
  ~100ms 而不是 15ms。修法是把 `updateCommitted()` 挪到 `runGuiUpdate` 尾部那个 block。
  **不阻塞 Phase 1**（三条验收标准都不用 ms 表达，且两种读法对「该不该做」是同向的）；
  **阻塞 Phase 0 剩下的优化和 `guiUpdateDebounce` 调参** —— 那几项动手前必须先修好量程，
  否则又是拿错数排序。
- **E2E 的 p99 / max 不可信**：`updateRequested()` 把非日志触发的刷新（延迟重试、补刷）
  也按「最后一行日志的时间戳」归因了。**p50 / p95 可信。**
- **B 段至今没有埋点**，而 E2E 的长尾恰恰落在这里。要继续深挖就从补 B 段开始。
- **掉帧不是 HSTracker 造成的**（在这套录屏方法的精度内）：对照组
  （HSTracker 完全没启动、只有静态主菜单）横跨了同样的范围。头号嫌疑是采集管线
  （4K 165Hz 面板压成 1080p120）。要排除它得换一个不经过 OBS 的测量手段，再录一段没用。

### Phase 0 剩下的优化候选（**先修 D 段量程再动手**）

| 候选 | 预计收益 |
|---|---|
| 两个日志轮询用信号量串起来 | ~50ms（A 段里属于我们的那部分） |
| 文件轮询换 `DispatchSource` | ~25ms，完全取决于炉石的 flush 行为 |
| ~~优化 `updateFrames()`~~ | ~~作废~~ —— Phase 1 的理由只剩动效和分区，不再是延迟 |

---

## 已知问题（都已定位，等对应阶段处理）

| 问题 | 根因 | 归属 |
|---|---|---|
| 卡牌从右侧消失时"卡顿" | `CardBar.fadeOut(highlight:)`（`:285`）函数体只有 `if highlight`，count==0 的卡淡出根本不播，但 `asyncAfter` 仍死等满 **600ms** 才删行 | Phase 1 / T8 |
| 数量变化（4→3）一帧跳变 | 插新 bar + 立即删旧 bar，`fadeOut: false`；全局没有任何布局动画 | Phase 1 / T8 |
| 两个战棋计数器没被编译 | 上游 3.6.5 的 `EternalKnightCounter.swift` / `AncestralAutomatonCounter.swift` 没登记进 pbxproj（上游发布版同样缺） | 随时可修 |
| `BobsBuddy-version.txt` 是装饰品 | 实际永远拉最新版 | 随时可修 |

### macOS 14 部署目标带来的两处 deprecated（都没修）

| API | 位置 | 说明 |
|---|---|---|
| `.activateIgnoringOtherApps` | `AppDelegate.swift:257`、`NSAlert.swift:28`、`CoreManager.swift:446` | macOS 14 起被系统忽略，改成协作式激活。**下次开游戏留意 alert 会不会被压在炉石后面** |
| `CGWindowListCreateImage` | `SizeHelper.swift:236`（3 个调用点在 `ImageUtilities.swift`） | 官方推荐 ScreenCaptureKit；部署目标 ≥14 后迁移不再有版本包袱 |

### 两处过期描述（按"只改任务书指定文件"的规矩没动）

1. `PreferencePaneController.swift:21` 的注释说 tab icon 必须用 PDF，理由是「10.14 部署目标」——
   **理由已不成立**。它是上游 `bdb0ec12` 写的，改了会和上游冲突。
2. `README.md:9` 写「macOS 10.10 or higher」，上游升到 10.14 时就没跟。

### Phase 3 遗留（都不阻塞任何事）

1. `LadderTab` / `StatsTab` 有 16 条 zh-Hans 是 `Text Cell` 这类 XIB 占位（英文原样填的），
   用户看不见，但让覆盖率数字虚高。撤掉会让这两个文件永远显示"未翻译"，所以留着。
2. `Base.lproj/` 里还有 6 个没被 pbxproj 引用的 `Localizable.strings`，意味着
   `String.localizedString` 的 "Base.lproj 回退" 分支永远取不到东西。没删是因为
   `Base.lproj` 是活目录（有在用的 `.xib`），混着删风险大。
3. `HSReplayPreferences` 有几条旧译和英文对不上（`My Account` → 「上传收藏」），
   两边 catalog 都没有更好的版本，需要人肉重译。

---

## Phase 1 / T2 的当前状态

主牌表（`Tracker.swift` 的 `cardsView`）已可切到 SwiftUI 渲染，玩家和对手记牌器共用 `Tracker`、一起生效。

```
defaults write net.hearthsim.hstracker use_swiftui_tracker -bool true
```

**默认值是 `false`**，和 PLAN 第 3 节写的终态不一样：按切片推进，每一片都要在真实对局里看过才算数，
而这台机器每天在打游戏 —— 默认值不能是没验收过的那条路径。**开关在 Phase 2 之后才删**
（Phase 2 的分区还要靠它做对照）。

**故意没做的**：动效全部没做；`DeckLens` / `DeckSideboards` / 战棋三处仍是 `AnimatedCardList`
（600ms 空等还在）；协同高亮只画边框没有闪光；`Game.swift` 的 `playerTrackerUpdateEvents`
没加这个 key，所以 `defaults write` 要等下一拍 tracker 刷新才生效。

**没条件验证、不是没通过的三项**（不值得再打一局，改设置或用比对窗静态看即可）：
协同高亮边框、行高压缩、frost / minimal 的传说卡位移。

---

## 操作备忘

### 并排比对窗

```
env HSTRACKER_CARD_ROW_COMPARE=1 \
  ~/Library/Developer/Xcode/DerivedData/HSTracker-ajzeuoosmscserctkdytyfltkokj/Build/Products/Debug/HSTracker.app/Contents/MacOS/HSTracker
```

（这是合入的 grok 版。codex 版在另一个 DerivedData 下、环境变量叫 `HSTRACKER_CARD_ROW_COMPARISON`，
见归档文件。一次只开一个，两份产物共用同一份用户设置。）

### 素材留档

| 用途 | 路径 |
|---|---|
| 改动前基线（Debug，T5 前） | `~/Movies/2026-08-20 22-21-48.mp4`、`~/Desktop/Snipaste_2026-08-20_22-25-23.png` |
| Release 对照 | `~/Movies/2026-08-21 00-07-23.mp4` |
| 掉帧对照组（HSTracker 未启动） | `~/Movies/2026-08-21 00-04-08.mp4` |
| T5 之后 | `~/Movies/2026-08-22 00-31-43.mp4`、`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-22-release-t5.txt` |

掉帧分析工具 `docs/tasks/tools/frame_gaps.py`，**跨录像对比必须加 `--busy`**
（按"动画确实在进行的时段"归一化；不加的话内容差异会造出假结论）。

### 埋点分段口径

| 段 | 起点 | 终点 |
|---|---|---|
| A | 日志行自带的时间戳（`LogDate`） | `LogReaderManager.processLine` 拿到它 |
| B | `processLine` 开始 | `updateTrackers()` 置 `guiNeedsUpdate` |
| C | `guiNeedsUpdate` 置位 | tick 消费它 |
| D | `updateAllTrackers()` 开始 | 主线程 UI 提交完成 |

A 段包含炉石自己的 flush 延迟，是不可优化的地板。`LatencyProbe` 每 30s dump 一次、累计不清零。

---

## 环境备注（换机器或重开时需要）

1. `brew install wget` —— 两个 build phase 依赖它（下载 HearthMirror 和 Mono）。**不装必然构建失败。**
2. `Config.xcconfig` 已改为本地签名（`CODE_SIGN_IDENTITY = -`）并 `git update-index --skip-worktree`，
   `git status` 里看不到它。换机器要重做这一步。
3. `project.pbxproj` 的 `NET_VERSION` 已由 `net7.0` 修为 `net8.0`（`1ff31cb1`）—— 修的是 upstream 真实 bug。
4. SwiftLint **故意没装**：build phase 里未安装只告警不阻塞，装了反而会给 grok 的验收构建引入无关失败。
5. git 身份是 repo-local 配置的（`ffkiyo7 / ffkiyo7@gmail.com`），没有写进 global。
6. **交给人实测的包必须 `clean build`** —— `Download cards XML` 声明了 outputs 会被跳过，
   增量包里 `Contents/Resources/Resources/Cards/` 整个不在，记牌器会一根卡条都没有。
   机制写在 `AGENTS.md` 的「构建」一节。

---

## 详细记录去哪了

| 想找 | 去看 |
|---|---|
| 每个任务的执行细节、review 改了什么、踩过的坑 | `docs/archive/progress-detail-2026-08-22.md` |
| T1 切片的模型 A/B 完整比对（grok vs codex，逐元素） | 同上，「Phase 1 / T1 的模型 A/B」一节 |
| Phase 3 的六步任务、译文来源、72 处 review 改动 | 同上，「Phase 3」一节 |
| 录屏差分的方法学备忘 | 同上，「同一局的录屏分析」一节 |
| 任务书 | `docs/tasks/` |
| Firestone / HDT 的调研 | `docs/research/` |
