# 评估：红龙计算器解耦与 mod 化（2026-10-15）

> 起因：红龙是自加的功能，每次调优都要把整个 app 重编、重新打包。问题从「要不要解耦、新开仓库、做成按需加载的插件」扩展到「能不能让 HSTracker 本身支持 mod，mod 怎么改都能按约定插进来」。**本文只评估，没动代码。**

## 结论

按你说的目标（调红龙不用重编整个 app），值得让 HSTracker 支持 mod，而且做得到；仓库不用新开。红龙本来就不打算交给上游，做成 mod 正合适。先前「不做插件」的结论是按「减少合并冲突」评的，那个角度下插件确实不划算；你补充的动机改变了答案。

- **现在为什么每次都重编整个 app。** 红龙的胶水编在 app 模块里，app 约 13.6 万行 Swift，Release 是整模块编译（`SWIFT_COMPILATION_MODE = wholemodule`），胶水改一行整个模块重编，然后整个 app 重新签名打包。
- **mod 化之后。** 红龙整个（引擎、调度、面板、设置页，约 9 千行）编成一个独立的 mod，HSTracker 启动时从 Mods 目录加载。调一次只编 mod，重启 HSTracker 就生效，app 不用重编也不用重新打包。
- **「始终插得进来」靠一层约定好的接口 ModKit。** HSTracker 只通过它给 mod 开 5 个口子；上游怎么改，只改 fork 里把 ModKit 接到 HSTracker 的适配层，mod 不用动。ModKit 只加不改、带版本号，版本对不上的 mod 拒绝加载并提示。
- **代价。** 一次性新写约 1,300～2,100 行（ModKit、适配层、加载器，估计），再把红龙搬成 mod；之前推荐的仓库内解耦三步正好是第一阶段。mod 和 HSTracker 同进程，mod 崩了 HSTracker 一起崩；换 mod 要重启 HSTracker，不能热替换。
- **仓库。** mod 先放同一个仓库的独立目录（`Mods/RedDragon/`），日志回放测试还能照跑；想独立仓库以后随时搬。

## 让 HSTracker 支持 mod

做法是在 HSTracker 和 mod 之间加一层约定好的接口（下称 ModKit）：HSTracker 只通过它开 5 个口子，mod 只认它。口子按红龙今天实际用到的宿主代码定，不多开。

| 口子 | HSTracker 给 mod 什么 | 红龙今天直接调的宿主代码 |
| --- | --- | --- |
| 对局事件 | 解析线程到一致边界时同步回调（批尾无未闭合 BLOCK、最外层 BLOCK 刚闭合），另有对局开始 / 结束；回调在解析线程上，mod 自己切主线程更新界面 | `LogReaderManager` 里的 2 处挂点 |
| 读对局状态 | 只在回调里按需读：实体（id、cardId、tag 按原始数值）、双方玩家、当前套牌和 sideboard、剩余牌库、对方场攻、模式标志、对局身份。不读不拷 | `RDGameSnapshot.capture(game:)` 里的 `Game`、`Entity`、`BoardState`、`PlayingDeck` |
| overlay 图层 | mod 给一个 SwiftUI 视图，放进固定像素层；宿主给画布尺寸、手牌和场面位置、记牌器占位；mod 报自己的可点区域 | `RootOverlayView`、`BoardOverlayView`、`SizeHelper`、`TrackerPanelViewModel`、`InteractiveRegionPreferenceKey` |
| 设置页 | mod 给标题、图标、搜索词和 SwiftUI 视图，宿主包成设置窗的一页；设置键自动加 mod 前缀 | `PreferencePane`、`Settings` |
| 宿主服务 | 日志、跟随应用语言的卡名、记牌器配色、mod 自己的数据目录 | `logger`、`Cards.any`、`TrackerBarStyle` |

热键 mod 自己用系统 API 注册（红龙现在就是这样），不经 HSTracker。

「按结构格式始终插得进来」靠这几条约定：

- **只有一份 ModKit，动态库，开 library evolution。** 它随 HSTracker 编进 app 的 Frameworks，mod 只动态链接它、不得自带一份（自带会让类型重复，HSTracker 认不出 mod）。开了 library evolution，ModKit 只加东西时旧 mod 不用重编。
- **版本号。** ModKit 带「主.次」版本，mod 声明自己按哪个版本编：主版本不同就拒绝加载并在设置页提示，次版本只加不改。合并上游时只改适配层，ModKit 不动，mod 照常加载。
- **目录和开关。** mod 是一个依赖 ModKit 的 Swift 包，编出来是一个动态库。启动时加载 `~/Library/Application Support/HSTracker/Mods/` 里的 mod，设置窗里有 mod 列表可逐个开关；开发时可以指向构建输出路径，省掉拷贝。
- **mod 之间的冲突。** 设置键按 mod id 分命名空间；热键被占时注册失败只记日志；overlay 各自一层，不自动避让，靠各自让开记牌器占位。
- **出事兜底。** mod 和 HSTracker 同进程：上次启动后很快崩溃的话，下次启动先关掉所有 mod 并提示（安全模式）；解析线程回调太慢会记日志点名。
- **换版本要重启。** 含 Swift 代码的库加载后卸不掉。上游支持对局中途启动（`eb4deaad`），重启后会从 Power.log 把当前对局补回来（推断，要在 Mac 上实测）。

调一次红龙，现在是：改代码 → 整个 app 按 Release 整模块重编（约 13.6 万行）→ 签名打包整个 HSTracker.app → 换新包重开。mod 化之后是：改 mod → 只编 mod（约 9 千行，app 和 ModKit 不动）→ 放进 Mods 目录（开发时可直接指向构建输出）→ 重启 HSTracker，从 Power.log 补回本局（推断）。两条流程差在第二步：现在每次都要把 13.6 万行的 app 一起编、再整个重新打包；mod 化之后 app 不动，只编红龙自己。

分三个阶段做，每个阶段做完都能停下来照常用：

1. **仓库内解耦**（下文「第一阶段」那三步）：包挪成标准目录、立公开接口、拆引擎测试。
2. **ModKit + 适配层 + 加载器。** ModKit 做成本地 Swift 包的动态库产品，pbxproj 只多包引用和嵌入那几行；上游文件里的挂点仍是那 5 处，改成调 mod 管理器。红龙这时还编在 app 里，但改走 ModKit 接口，行为不变。
3. **红龙搬成 mod。** 引擎、调度、面板、设置页编进 `Mods/RedDragon/`，app 里删掉红龙；拷快照改成读 ModKit 的实体（今天的 `capture(entities:)` 已经是纯函数，换输入类型即可）。验收：205 条红龙测试换了位置后条数和结果不变，10 局 fixture 回放出的结论逐回合一致。

代价（估计，没在 Mac 上实测）：ModKit 约 500～900 行协议和值类型；适配层、加载器和 mod 列表页约 800～1,200 行；红龙搬家主要是把直接调宿主的地方换成 ModKit。之后调优只编红龙 mod（约 9 千行，含引擎），不再重编 app 的 13.6 万行。日志回放类测试仍要 HSTracker 在场，留在 app 的测试 target 里直接编 mod 源码跑。

## 现状：已经解耦了一大半

红龙的引擎早就是一个本地 SwiftPM 包（`RedDragonCore`，只 import Foundation）；真正和 HSTracker 缠在一起的是编进 app 的 7 个胶水文件和上游文件里的 5 处挂点。以下数字取自 `origin/dev0923`（`f0efbbb3`，3.7.0 合并前；上游 3.7.0 没碰红龙，所以对红龙部分同样成立）。

红龙在 fork 里分三层：上游 HSTracker 的宿主代码、编进 app 的胶水、引擎包；胶水跟着上游变，引擎上游动不到。今天不改接口，能直接拆出去的只有引擎：胶水直接用宿主类型。有了 ModKit 之后，胶水改走 ModKit，就能和引擎一起进 mod，留在 fork 的只剩适配层。

| 层 | 内容 | 规模 | 依赖宿主的什么 |
| --- | --- | --- | --- |
| 引擎（本地包 `RedDragonCore`） | 卡表、局面、规则、搜索、破冰、结论、读取、回放，共 11 个文件 | 6,269 行 | 无。`threadCPUTime` 用 POSIX `clock_gettime`，锁用 `NSLock` |
| 胶水（编进 app） | 调度 `Assistant` 872、拷快照 `Snapshot` 202、面板模型 763、面板视图 679、文案 255、热键 146、设置页 108 | 3,025 行 | `Game` / `Entity` / `BoardState` / `PlayingDeck`；`RootOverlayView`、`TrackerPanelViewModel`、`BoardOverlayView`、`SizeHelper`、`BoardOrderSlotViewModel`；`PreferencePane`；`Settings`、`Cards`、`logger`、分区记牌器的 `TrackerBarStyle` |
| 上游文件里的挂点 | `LogReaderManager` 2 处（批尾、最外层 BLOCK 闭合）、`RootOverlayView` 1、`RootOverlayViewModel` 1、`AppDelegate` 1 | 约 16 行 | 解析线程的一致边界、overlay 画布、设置窗 |
| 红龙顺带修的宿主 bug | 回溯区间从 PLAY 的 BLOCK\_START 起算（`LogReaderManager.isRewound`）、新导入套牌补存 sideboard（`RealmHelper`） | 约 20 行 | 修的是宿主行为，记牌器也受益 |
| 测试 | 8 个文件 205 条，10 局真实日志 fixture | 11,246 行 + 23.8 MB | 粗分约 86 条要宿主（日志回放走 HSTracker 解析器、卡库、设置），约 119 条只碰引擎（按符号粗筛，未逐条核） |
| 工程登记 | `project.pbxproj` | 104 行含 RedDragon | 14 个红龙提交里 8 个改了它 |

三个和本题直接相关的事实：

- **包存在的理由是性能，不是解耦。** `Package.swift` 头注释写明：Debug 整体 `-Onone` 时搜索慢约 11 倍，3 秒 CPU 兜底下会漏斩杀，所以单拎出来用 `unsafeFlags(["-O", "-enable-testing"])` 编。app 侧 7 个文件靠 `@testable import RedDragonCore` 用引擎的 internal 符号，Release 也一样，没有正式的公开接口。
- **关着时几乎零开销。** 解析线程每批只加锁读一次缓存的开关；不是红龙套牌时一次 `main.async` 都不投；热键只在开关开着且炉石在前台时注册。所以「按需加载」能省下的运行时开销接近零（按代码推断，没有在本机测）。
- **引擎和胶水一起演进。** 14 个红龙提交里 7 个同时改了引擎和胶水（T2b、T2c、T3、T4、T5、T8 两次），2 个只改胶水，5 个只改引擎或测试。

## 四种做法对比

按「减少合并冲突」看，四种做法差别不大：会跟着上游变的拷快照、overlay 定位、设置页，不管哪种做法都要在 fork 里改。按「调红龙不用重编 app」看，只有 D 做得到；D 现在指上一节的 mod 方案（同一个仓库、经 ModKit 加载），不再是新仓库加插件 SDK。

| 做法 | 上游合并冲突面 | 引擎能否脱离 app 测 | 调一次红龙要编什么 | 一次性工作 | 持续成本 |
| --- | --- | --- | --- | --- | --- |
| A 维持现状 | 5 处挂点约 16 行；pbxproj 每加一个文件改一次 | 不能，205 条全跑在 app 宿主里 | 整个 app Release 重编、打包 | 无 | Release 也带 `-enable-testing`，没有公开接口 |
| **B 仓库内解耦（第一阶段）** | 挂点不变；pbxproj 里不再有引擎文件，加引擎文件不再动它 | 约 119 条用 `swift test` 直接跑 | 同 A | 中：挪目录、标 `public`、拆测试 | 维护约 30 个公开类型 |
| C 新仓库，编译期依赖 | 比 A 多：远程包引用 + `Package.resolved` 里多一条钉 | 同 B，另有独立 CI | 同 A，另要先推引擎再改钉 | B + 建仓库、迁历史和文档 | 历史上一半提交要跨两个仓库同步 |
| **D HSTracker 支持 mod（推荐）** | 5 处挂点改调 mod 管理器；ModKit 是本地包，pbxproj 只多几行；上游的变化只落在适配层 | 同 B | 只编 mod（约 9 千行），重启 HSTracker | B + ModKit、适配层、加载器，红龙搬成 mod | 上游改宿主类型时改适配层，mod 不动；ModKit 只加不改 |

「按需加载」单独看：关着开关时现在就几乎不花什么（见上节）。做成 mod 后，不放红龙 mod 的 HSTracker 里就没有红龙，出不带红龙的公开包也不用编译开关了。

## 第一阶段：仓库内解耦三步

这三步是 mod 化的第一阶段，单做也有用：只动 fork 自己的文件和 pbxproj 里我们自己的条目，上游合并不受影响，引擎测试可以脱离 app 跑。

1. **包挪成标准目录。** `HSTracker/RedDragon/Package.swift` 和 11 个引擎文件挪到 `Packages/RedDragonCore/Sources/RedDragonCore/`，去掉 `sources:` 点名清单；pbxproj 只改包引用的路径、删 11 条只供导航显示的文件引用。以后加引擎文件不再碰 pbxproj。
2. **立公开接口。** app 侧 7 个胶水文件用到的引擎类型正好 30 个（`RDGameSnapshot`、`RedDragonHint`、`RedDragonSearch`、`RDIceBreak` 等），标 `public`；`-enable-testing` 改成只在 Debug 带，app 侧的 `@testable import` 换成普通 `import`。`-O` 照旧用 `unsafeFlags`，本地包允许。
3. **拆测试。** 只碰引擎的约 119 条挪进包自己的测试 target，`swift test` 直接跑，不启动 app、不加载卡库；卡表对卡库的核对、日志回放、overlay 约 86 条留在 `HSTrackerTests`。验收：两边条数加起来等于拆前，全套和红龙组结果不变。

第四步（单做可选，搬成 mod 前要做）：把 `RedDragonAssistant` 的调度（872 行，只有拷快照和套牌判定几处碰 `Game` / `PlayingDeck`）、纯值的 `RDOverlayModel`（约 290 行）和文案也挪进包，宿主经闭包把快照、设置、日志、卡名交给它（`Environment` 里已经有这种闭包）。做完 app 侧只剩拷快照、overlay 定位、面板视图、热键、设置页约 1,600 行，公开接口缩到十个类型左右，`RedDragonLiveTests` 里直接喂快照的那批也能进包。

顺带的好处：引擎只依赖 Foundation，拆出独立测试后理论上在 Linux 上也能 `swift test`，云端线程改引擎就不必每次借你的 Mac 跑测试。这点没实测：本次云端环境下载 Swift 工具链被网络策略拦了（download.swift.org 返回 403），要用得先在环境设置里放行。

## 代价

B 是一次机械性整理，风险集中在改一次 pbxproj；D 的大头是写 ModKit 和适配层，换来的是之后调红龙只编 mod、不碰 app。

| 项 | B 仓库内解耦 | D HSTracker 支持 mod |
| --- | --- | --- |
| 一次性工作 | 挪 12 个文件，30 个类型标 `public`，拆约 119 条测试，改 pbxproj 一次 | B 的全部；ModKit 协议和值类型约 500～900 行；适配层、加载器、mod 列表页约 800～1,200 行；红龙改走 ModKit 再搬成 mod（估计，没在 Mac 上实测） |
| ABI 与链接 | 无变化 | mod 只链 ModKit，碰不到 `Game` / `Entity` / `TrackerPanelViewModel`。ModKit 开 library evolution，只加东西时旧 mod 不用重编；ModKit 只能在 app 里嵌一份，mod 不得自带 |
| 加载与签名 | 无变化 | 宿主已带 `disable-library-validation`，本机自己编的 mod 不用和 app 同一个签名就能加载。含 Swift 代码的库加载后卸不掉，换 mod 要重启 HSTracker |
| 分发 | 不变，一个 app | 自用不变；给别人用时 mod 是另一个未公证的下载物，大概率要再过一次 Gatekeeper（推断） |
| 调试与测试 | 引擎测试不再启动 app；回放测试照旧 | 回放测试仍要 HSTracker 在场，留在 app 的测试 target 里直接编 mod 源码跑；同进程运行，mod 崩了 HSTracker 一起崩，靠安全模式兜底 |
| 持续成本 | 胶水新用到的引擎类型要记得标 `public` | 上游改 `Game`、overlay、设置页时只改适配层，mod 不动；ModKit 要加口子时只加不改，升主版本时 mod 才要重编 |

C（新仓库但编译期依赖）的代价介于两者之间，另有一个坑：按版本号引用的远程包不能带 `unsafeFlags`，而 Debug 下 `-O` 正靠它，只能按提交或分支引用（SwiftPM 的规则，未在本项目实测）。另外本机受限环境里 SwiftPM 拉 github.com 要临时加代理配置（`docs/PLAN.md` 项目细节），每次改钉都多一次拉取。

## 对上游合并冲突面的影响

红龙到目前为止只给上游合并带来过 1 块文本冲突，是 pbxproj 里的相邻行；真正的维护面是胶水依赖的宿主类型每版都在变，这部分哪种做法都免不了改，mod 化之后改的只是适配层。

| 合并 | 红龙相关冲突 | 红龙相关的合后工作 |
| --- | --- | --- |
| 3.7.0（10-14） | 8 个冲突文件里只有 pbxproj 1 块：上游删 BigInt / CustomToolTip，紧挨我们的 `RedDragonCore` 条目，机械解决。红龙目录和 5 处挂点上游一行没碰 | 2 条红龙回放测试在负载下撞 CPU 预算变红，重跑通过；新扩展卡牌数据要单独看一遍红龙组 |
| 3.6.13（09-29） | 0（当时只有引擎核心，挂点还没加） | 无 |

宿主类型变得有多快：我挑了胶水直接调用的 14 个上游文件，3.6.12 → 3.6.13 这一版（28 个提交）改了其中 11 个。设置窗改成侧栏，红龙设置页实现的 `PreferencePane` 协议就是这版新加的（`PreferencePaneController` +9 / −72）；`Game` +123、`LogReaderManager` +34（回溯）；面板借用的入场序号徽章尺寸也是这版才有。在树内，这些变化当场编译报错，同一次 `xcodebuild test` 里 205 条红龙测试兜底；做成 mod 后，这些变化由适配层吸收：活一样多，但只落在适配层一处；适配层和 ModKit 仍编在 app 里，照样当场报错，mod 不用动。

各做法下的变化：

- **A 维持现状**：基线。每次合并看 pbxproj 里我们的条目、跑红龙组。
- **B 仓库内解耦**：上游文件里的挂点不变；pbxproj 里红龙的条目从 104 行降到约 70 行（删掉 11 个引擎文件和挪走的测试，剩下的是留在 app 的胶水、回放测试和日志 fixture；胶水目录再改成同步文件夹组可到 40 行左右；推断，按 B 的目录结构估），引擎加文件不再碰它。冲突面略小。
- **C 新仓库编译期依赖**：多一个远程包引用和一条 `Package.resolved` 钉。拿 3.7.0 对照：钉按名字排序会落在 `promisekit` 和 `realm-cocoa` 之间，而上游这次正好删了 PromiseKit，会多出一处相邻冲突（推断）。本地包不进 `Package.resolved`，现在没有这个问题。
- **D HSTracker 支持 mod**：上游文件里的挂点还是 5 处，改调 mod 管理器；ModKit 是本地包，pbxproj 里只多包引用和嵌入几行，不是一大块；上游改宿主类型时只改适配层，ModKit 主版本不变，mod 就不用重编。红龙搬成 mod 后，pbxproj 里红龙的条目基本只剩回放测试和日志 fixture（推断）。

## 附录：证据

都在 `ffkiyo7/HSTracker` 的 `dev0923`（`f0efbbb3`）上看的；上游 3.6.12 / 3.6.13 取自仓库里的 `c723bfd4` / `41f89c04`，3.7.0 的数字来自 3.7.0 合并评估（`upstream-3.7.0-eval.md`）和合并提交 `b227ef15`（写本文时还没推到 origin）。

| 说法 | 依据 |
| --- | --- |
| 引擎是本地包、为 Debug 下 `-O` 而建、带 `-enable-testing` | `HSTracker/RedDragon/Package.swift:1-41` |
| app 侧靠 `@testable import RedDragonCore` | 7 个胶水文件的 import，如 `RedDragonAssistant.swift:40` |
| 解析线程挂点 | `HSTracker/Logging/LogReaderManager.swift:180`、`:266` |
| overlay 与设置页挂点 | `RootOverlayView.swift:615`、`RootOverlayViewModel.swift:133`、`AppDelegate.swift:71` |
| 关着时只读缓存开关 | `RedDragonAssistant.swift:222-228`（`parserBatchDidEnd`） |
| 热键只在开关开着、炉石在前台时注册 | `RedDragonHotkeys.swift` `shouldRegister` |
| 拷快照要碰 `Game` / `Entity` / `BoardState` | `RedDragonSnapshot.swift:20-39` |
| 面板几何依赖 `BoardOverlayView` / `SizeHelper` / `TrackerPanelViewModel` | `RedDragonOverlayModel.swift:307-569`、`RedDragonOverlayView.swift:98-140` |
| 宿主已带 `disable-library-validation` | `HSTracker/HSTracker.entitlements` |
| 14 个红龙提交里 7 个同时改引擎和胶水、8 个改 pbxproj | `git log --grep=red-dragon origin/dev0923` 逐个看改动文件 |
| 胶水依赖的 14 个宿主文件，3.6.13 改了 11 个 | `git diff --stat c723bfd4 41f89c04 -- <这 14 个文件>` |
| 测试 205 条，约 119 条只碰引擎 | 按宿主符号粗筛每个 `test` 函数及其调用的辅助函数，未逐条核 |
| `Package.resolved` 里的钉按名字排，含 `promisekit`、`realm-cocoa` | `HSTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |
| Release 整模块编译，app 约 13.6 万行 | `project.pbxproj:9480`、`:9604`（app 的 Debug / Release 里只有 Release 是 wholemodule）；`HSTracker/` 下除红龙外的 Swift 共 136,229 行 |
| 红龙 mod 约 9 千行 | `HSTracker/RedDragon/` 全部 Swift 共 9,337 行（引擎 6,269 + 胶水 3,025 + Package.swift） |
| 重启后能补回当前对局 | 上游 `eb4deaad`（对局中途启动时按回溯正确重置）；没在 Mac 上实测 |

没做到的：没在 Mac 上构建或跑测试（这是评估，没动代码）；关着时的开销和二进制里引擎占多大没有实测；没拉上游 3.7.0 的源码逐行核对；mod 方案的代码量是估计，ModKit 动态库的嵌入、mod 的加载和重启后补回本局都没在 Mac 上试。
