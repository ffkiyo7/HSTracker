# Phase 1 / T7 — 卡图加载改真异步 + 缓存加 LRU 上限

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。
本任务对应 `docs/PLAN.md` 的 **1.2**，动手前把那一节读完。

这一片是**纯性能**，不改任何渲染结构，也不改任何外观。它与 SwiftUI 迁移没有依赖关系。

## 两个问题（都已核对到行）

**（1）缓存未命中时，磁盘读 + 解码跑在调用线程上。**
`ImageUtils.loadImage(type:cardId:completion:)`（`ImageUtils.swift:118`）一进来就是
`NSImage(contentsOf: path)` —— 同步读盘 + 解 JPEG，**在谁调它就在谁的线程上跑**。
调用方包括 `CardBar.draw()`（`CardBar.swift:406`）和 `CardRowView.loadTile()`
（`CardRowView.swift:405`），两者都在主线程。只有后面那条**下载**分支才是异步的。
所以一张卡第一次出现时，主线程会被一次磁盘读 + 解码堵住。

**（2）四个缓存无上限、无淘汰。**
`ImageUtils.swift:36-39` 的 `cache` / `cacheArt` / `cacheCardArt` / `cacheCardArtBG`
都是 `SynchronizedDictionary<String, NSImage>`，只增不减，只有 `clearCache()`（用户手动触发）
才会清空。长时间运行会一直涨。

## 要做出什么

1. **磁盘读与解码移出调用线程。** 命中内存缓存时可以（也应该）立刻同步返回；
   只有需要读盘或下载时才走后台。
2. **给这四个缓存加 LRU 上限。**

## 关键约束

- **不许修改 `HSTracker/Utility/SynchronizedDictionary.swift`。**
  它被 `Cards.swift`、`BobsBuddyInvoker.swift`、`SecretsManager.swift`、
  `CollectionHelper.swift`、`BattlegroundsBoardState.swift` 等多处共用，
  在它身上加淘汰逻辑会波及一堆无关代码。要 LRU 就**另建一个类型**，只给 `ImageUtils` 用。
- 🔴 **completion 的线程契约是本任务最大的风险，必须处理干净。**
  现在「磁盘命中」是**同步**回调、「需要下载」是**异步**回调，同一个 API 两种时序。
  改完之后契约会变。`ImageUtils` 的 `tile` / `art` / `cardArt` / `cardArtBG` 一共有
  **十几个调用点**（自己 `grep -rn "ImageUtils\." HSTracker --include="*.swift"` 列全），
  横跨 AppKit 的 `draw()`、SwiftUI 的 `onAppear`、战棋、佣兵、Mulligan 等。
  **要求**：
  - 定一个明确的契约（比如「completion 一律在主队列」），**写在 `ImageUtils` 的代码注释里**；
  - 逐个调用点核对新契约下是否仍然正确，**在报告里列出你核过的清单和结论**；
  - 尤其注意 `CardBar.swift:396-410`：它在 `draw()` 里发起加载、回调里再触发重绘，
    如果回调变成异步且它假设了同步，卡图会晚一帧或不出现。
- **不许改变任何外观。** 未命中时怎么显示由现有代码决定，本任务不引入新的占位图、
  不加淡入、不改尺寸。**唯一允许的视觉差异**是「卡图从第一帧就有」变成「晚几十毫秒出现」，
  这是异步化的必然结果。
- **LRU 的容量要有依据。** 记牌器一屏最多几十张卡，但战棋 / 卡组管理器会拉进来更多。
  容量定多少、按什么估的，写进报告。**宁可偏大**：这一项的目的是防止无界增长，不是省内存。
- **`clearCache()` 的语义不许变**（`ImageUtils.swift:41`），它同时清内存和磁盘目录。
- **线程安全不许退化。** 现在靠 `SynchronizedDictionary` 的 `UnfairLock`。
  新的 LRU 类型同样会被多线程读写（下载回调在 URLSession 的队列上），**必须自己带锁**。
- **不要顺手改下载逻辑。** URL 拼接、`data.write(to:)` 落盘、错误处理都保持原样。
  注意现有代码里下载失败的 `else` 分支**根本不调 `completion`**（`ImageUtils.swift:184` 附近，
  `data` 为 nil 或 `NSImage(data:)` 失败时直接漏掉）—— 这是既有缺陷，
  **如果你的改动会让这个漏调变成泄漏（比如有等待方），才修它，并在报告里说明**；否则记进报告不要动。
- 代码注释一律用英文，与仓库一致。

## 范围边界

- **只做 `ImageUtils` 这一层和它的直接调用契约。** 不要顺手优化任何调用方的渲染逻辑。
- **不要动 `CardBar.swift`**，除非新契约让它出错 —— 那种情况下把改动控制在最小，并在报告里单独说明。
- 不引入任何第三方依赖。

## 允许修改的文件

- `HSTracker/UIs/ImageUtils.swift`
- `HSTracker/UIs/Trackers/SwiftUI/CardRowView.swift`（仅在新契约需要时）
- 新增 `.swift` 文件（LRU 类型）

新增 `.swift` **必须手工登记进 `project.pbxproj`**（`PBXBuildFile` + `PBXFileReference` +
group + Sources，共 4 处）。**漏登记不会报编译错误**，文件被静默忽略，详见 `AGENTS.md`「构建」一节。

## 验收

1. 构建通过（`Debug`）。
2. 新增文件 `grep -c "<文件名>.swift" HSTracker.xcodeproj/project.pbxproj` ≥ 3。
3. `git diff --stat` 的既有文件不超出「允许修改的文件」列表。多一个都要给理由。
4. **`loadImage` 里不再有任何在调用线程上的同步磁盘 I/O** —— 指出改后的代码里读盘发生在哪。
5. app 能启动，记牌器里卡图正常显示；`HSTRACKER_CARD_ROW_COMPARE=1` 比对窗里卡图也正常。
6. 实战验证由人来做。

## 报告里请回答

- 新的 completion 线程契约是什么，写在了哪。
- 你核过的调用点清单，每个的结论（"仍然正确" / "需要改，改了什么"）。
- LRU 的容量、淘汰策略、怎么加的锁。
- 内存命中的快路径是否仍然同步返回；如果不是，为什么。
- 范围边界之外你注意到、但按规则没有动的问题。
