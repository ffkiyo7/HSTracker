# AGENTS.md

写给在这个仓库里干活的 AI 助手（Claude Code / Codex 等）。人也可以看。

HSTracker：macOS 炉石传说记牌器，Swift + AppKit。本仓库是 `HearthSim/HSTracker` 的
**个人自用 fork**（`ffkiyo7/HSTracker`），**不回流上游**，**本文件 > 上游 `CONTRIBUTING.md`**；
但每个 release 都从上游 merge 一次，下面多条约定由此推出。

计划 `docs/PLAN.md`，进度 `docs/PROGRESS.md`（都是精简版：要做什么 / 做到哪）。
执行细节、review 记录、A/B 比对在 `docs/archive/`。

## Commit 规范

Conventional Commits 前缀：`feat` / `fix` / `perf` / `docs` / `chore` / `build`（merge commit 不加）。
上游也用这套，统一只为合完之后 `git log` 好读。

- 标题 ≤50 字符，祈使语气，不加句号，前缀后小写开头（专有名词除外）
- 正文写**为什么**，不复述 diff；显示宽度 ≤80 列折行（中日韩字符算 2 列）
- 注明代码谁写的：执行模型生成的写清依据哪本任务书、review 额外改了什么
- 保留 `Co-Authored-By:` 尾注
- **不写 `Claude-Session:` 或任何 `https://claude.ai/code/session_...` 链接**
- 一个 commit 只做一件事

## 跟上游

```
git fetch upstream --tags
git checkout master && git merge --ff-only upstream/master   # master 只快进
git checkout <工作分支> && git merge master
```

`master` 是上游纯镜像，**任何自己的改动都不许提交到 master**，否则以后无法快进。
合完更新 `docs/PROGRESS.md` 的基线 commit 和构建状态。

## 分工：任务书交给执行模型

代码由 **Codex** 按 `docs/tasks/*.md` 写成，人工 review 后提交。
`docs/tasks/` 只放**在做和待验**的书，验收通过挪进 `docs/archive/tasks/`（有索引）。
任务书必须复述以下硬规则（现有版本在 `docs/tasks/_common*.md`）：

1. **只改任务书指定的文件。** 别处有问题写进报告，不顺手改。
2. **不 `git add`，不 `commit`。** 留在工作区，人 review 后统一提交。
3. **不动 `Config.xcconfig`。** 已改本地签名并 `git update-index --skip-worktree`。
4. 风格与周围一致。本仓库注释少，**不加大段注释**，只在原因不明显时写一两行。
5. 改完跑验收构建，确认 `BUILD SUCCEEDED`。
6. **改完跑一次测试**（命令见「构建」）。2026-09-03 起 50 / 50 全绿，红了就是回归，
   不许为了变绿改被测代码 —— 旧预期确实过期才改测试，并在报告里说明依据。

### 写任务书：给约束，不给实现

**代码块只用于引用现状和验收命令，不贴函数体。** 篇幅 50~70 行。

- **review 信度**：实现由写任务书的人给，review 就成了自己批自己。
- **可观测性**：看不到执行模型的真实能力，无从判断下个任务给多大。
- **token 分摊**：实现写进任务书，成本全压在贵的一侧。

判据：2026-08-21 的 T5，任务书 226 行、33% 是代码块，55 行新增里 **43 行逐字来自任务书**，
执行模型实际写的逻辑是 0 行。对照 T1–T4（代码块 0 行、48~73 行）同样顺利。

难的是**把约束写准**：语义要求、不变量、点名「按字面实现会比现状更糟」的失败模式并要求
它论证自己没踩、验收命令。能让它自己 grep 的别替它列 —— 找不到正是 review 该抓的。

**约束本身也可能错。** 2026-08-28 的 T4 要求「段头复刻 `DeckLens` 边框色 `#141617`」，
而 `DeckLens` 的 `NSBox` 是 `.noBorder` + `borderWidth = 0`，那行 `borderColor` 不生效 ——
照做多画一条线。列属性不如指路径：**写「照哪个函数的 frame 账复刻」**。

### 也不给排查路径

排查类任务只给症状、证据（日志 / hang report / 截图事实）、硬约束、验收标准，
**不给候选清单、不给"已排除"结论**，搜索空间留给执行侧。

- 反例 2026-08-30 Bug T3（对手记牌器混进我方卡）：任务书收敛成「A 跨局残留 / B 实体归属」
  加一份已排除清单。**真根因是第三条路径**（我方奇闻牌开局揭示时写进对手牌库预测）。
  执行侧查出来了，但 review 侧被自己的框架带偏 —— 任务书越全，review 越退化成
  「有没有照我说的做」，而不是「这事到底对不对」。
- 正例同日 Bug T2：明写「以下是 review 侧读法，逐条可能读错，独立复核后直说哪条不成立」，
  并交代 review 侧卡在哪。结果执行侧推翻了 review（漏看一层 `main.async`）。
  **交叉检验要留出被推翻的余地。**

### watcher 回调与 UI 线程

`HearthWatcher/` 的回调各自跑在自己的 `DispatchQueue`。任何从回调直接或间接写 SwiftUI
view model（`@Published` / `ObservableObject` / `objectWillChange`）的路径，必须先异步回主线程；
同一份状态在同一个 main block 内提交；禁止 `DispatchQueue.main.sync`。
原因：Combine publisher 内部锁与主线程渲染争用。实证
`/Library/Logs/DiagnosticReports/HSTracker_2026-08-30-173357_wadomarkm4.hang`：
`DiscoverStateWatcher → TrackerCardListViewModel.setHighlight` 与主线程
`Tracker.update → playerType.setter` 互锁。

### 改 overlay / view model 时序前，数清每一跳 `main.async`

**不要假设回调是同步的。** 判断「两次写谁先谁后」「后面那次会不会纠正前面那次」之前，
列出从写入到 `windowManager.show()` 的**每一次** `DispatchQueue.main.async`。已知两处：

- `Game.updateBattlegroundsOverlays()`（`Game.swift:753-754`）整个函数体包在**无条件**
  `main.async` 里，调用方在主线程也要等下一轮。
- `Tier7PreLobby.awakeFromNib()`（`:43-47`）把 `viewModel.propertyChanged` 写成
  `{ name in DispatchQueue.main.async { self.update(name) } }` —— **属性回调比 setter 晚一轮**。

代价：2026-08-30 修完 watcher 线程归属（`ac116be0`），构筑对局冒出战棋 Tier7 pre-lobby 浮窗
（`eb52832e` 修）。review 侧把第二条当成同步回调，推出"规范路径最后会隐藏、能自我纠正"的
**错误**结论；实际是规范路径先隐藏、延迟一轮的属性回调再绕过场景门显示回来。

**读代码读不出把握时，加一行只在状态翻转时打的日志跑一局。** 样板是 `[trackervis]`
（只在决策翻转时打、一行带全部判定输入、一整局十几行），已删，原样在 `ac116be0`。

## 构建

```
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' build
```

**Xcode.app 由 launchd 拉起，没有 homebrew PATH 和 shell 的代理变量**；命令行 `xcodebuild`
两样都继承，所以命令行能过、Xcode 里会挂。三个联网 phase 开头因此都注入 PATH 和**条件代理**
（`nc -z 127.0.0.1 7890` 探到才设，否则直连）。**验证「构建能不能过」用受限环境**：

```
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' clean build
```

### 测试

同一受限环境，把 `clean build` 换成 `test`。测试 target 以 `HSTracker.app` 为宿主、
只编译 `HSTrackerTests/` 下的 9 个文件，不需要炉石在跑。沙箱里第一次可能因无权写
`~/Library/Caches/org.swift.swiftpm` 失败，本机权限重跑即可，不是源码错误。
`DatabaseTests` 断言英文用 `card.enText`，不用 `card.text` —— 宿主 app 已按本机语言加载过卡库。

### 跑 Release 包取数：日志在文件里，不在 stdout

`ConsoleDestination` 被 `#if DEBUG` 包着（`AppDelegate.swift:200-203`），常开的只有
`FileDestination` → `~/Library/Logs/HSTracker/hstracker.log`（2MB × 2）。
**Release 包在终端一行日志都不打**，`tee` stdout 再 `grep` 必然读到空文件（2026-08-31 浪费一局）。

**更像"没启动"的坑**：首次从 `Build/Products/Release` 直接启动，AppMover 弹
"Move to Applications folder" 模态框，在 `applicationWillFinishLaunching` 阻塞，而日志系统在
`applicationDidFinishLaunching` 才配置 —— 现象是**进程在跑、log mtime 停在上次**。窗口常被炉石
盖住，切到 HSTracker 点 Don't Move。判断是否真起来看 `pgrep -lx HSTracker` **加** log mtime。

### bundle 装配（3.6.7）

`Resources` phase 仍把 `HSTracker/Resources/` folder reference 整目录拷到
`Contents/Resources/Resources/`，**build phase 不许改写源码目录 `HSTracker/Resources/`**。
3.6.7 已把两个运行时产物移出这个位置：

- 三份卡库 XML 按 `cards-version.txt` 缓存在 `downloaded-frameworks/cards/<version>/`，
  构建时暂存到 `BUILT_PRODUCTS_DIR`，`Compile CardDefs` 编译成 `Contents/Resources/CardDefs.bin`。
- Mono BCL、BobsBuddy、HearthDb 装到 `Contents/Resources/Managed/`。

2026-08-29 实测：`clean build` 后强制更新 `HSTracker/Resources/` 时间再增量 `build`，
`CardDefs.bin`、两架构各 168 个 BCL DLL、BobsBuddy / HearthDb 都在。**交包不再要求每次 `clean build`。**

仍要 clean 的一种情况：`HearthMirror-version.txt` 变化，同一次增量构建替换 framework 后预编译头报
"modified since the precompiled header was built"。这是缓存失效，`clean build` 一次即可，不是源码错误。

**改 build phase 先想清楚 inputs / outputs 是否覆盖它真正读写的东西。** 声明了 outputs 就放弃了
「每次都跑」，此后只有 inputs 变化或 outputs 缺失才重跑。3.6.7 给 `Embed Mono` 加了 6 个 outputs，
inputs 只有 `mono-version.txt`，但它同时负责把 `downloaded-frameworks/managed/` 的 BobsBuddy /
HearthDb 拷进 bundle —— 只改 `BobsBuddy-version.txt` 增量时，`Embed Mono` 被跳过，**包里留着旧 DLL**。
修法：三个 DLL 和 `HearthDb.xml` 补进 `Embed Mono` 的 inputPaths；四项同时是安装阶段 outputs、
`Embed Mono` inputs、bundle 内 outputs。

共同症状是**看起来像代码 bug，实际是产物残缺**。2026-08-22：包里缺 `CardDefs.xml` →
`Cards.by(cardId:)` 全 nil → 记牌器只剩几个计数框（那几个走 entity 计数和 Realm）。
**排查渲染层前先确认包完整。**

### 其余

- `Embed Mono` 拷 `net8.0` **整个目录**而非白名单：BobsBuddy 可能新增 BCL 依赖，
  手写清单会静默漏项、只在运行时报错。当前 168 个 DLL / arch。
- BobsBuddy / HearthDb 官方只有会变的 latest 地址，两份 zip 固定在 `Vendor/Managed/`，
  普通构建不访问。版本只由 `BobsBuddy-version.txt` / `HearthDb-version.txt` 声明，制品路径不重复版本号。
  两份 txt 登记在 Xcode 导航器但不复制进 app；上游遗留的 BobsBuddy 资源项已删。
- `Install vendored BobsBuddy and HearthDb` 在 `DERIVED_FILE_DIR` staging，确认四个文件齐全并
  强校验程序集版本，通过才 `cp` 到 `downloaded-frameworks/managed/`。**必须保留 staging → `cp`**：
  直接 unzip 到 outputs 会继承 zip 内旧时间，Xcode 永远判 phase 过期。
- 升级：`scripts/update-managed-deps.sh` 从两个 latest URL 下载并打印实际版本，确认后执行它
  打印的 `--apply <BobsBuddy版本> <HearthDb版本>`，脚本一起替换 zip 和版本文件；latest 在两次调用间
  又变会拒绝落盘。之后必须跑构建，不放宽校验、不手改第二份版本真相。
- 只有 **github.com 需要代理**（直连超时）；nuget / libs.hearthsim.net / api.hearthstonejson.com 直连。
  `CardDefs.xml` 约 100MB，按版本缓存在 `downloaded-frameworks/cards/`，`cards-version.txt` 变了才重下。
- `Embed Mono` 的 `NET_VERSION` 是 `net8.0`（上游 3.6.7 仍是 `net7.0`）。
  **除非任务明确要求，不动 `project.pbxproj`。**

### 新加 `.swift` 必须手工登记进 `project.pbxproj`

`PBXBuildFile` + `PBXFileReference` + 所属 group + Sources build phase，共 4 处。工程是
`objectVersion = 70`，但唯一的 `PBXFileSystemSynchronizedRootGroup` 只覆盖 `AnimalCompanionGenerator/`。

**漏登记不报编译错误**，文件被静默忽略。上游踩过：`EternalKnightCounter.swift` /
`AncestralAutomatonCounter.swift` 进了仓库没进 pbxproj，CHANGELOG 宣传的两个战棋计数器没被编译
（到 3.6.7 仍未修）。自查：

```
grep -c "你的新文件.swift" HSTracker.xcodeproj/project.pbxproj   # 应为 3~4，不是 0
```

## 本地化

zh-Hans 已 945 / 945（100%），见 `docs/PLAN.md` Phase 3。

- 译文只放 **String Catalog（`.xcstrings`）**。各语言 `.lproj/*.strings` 已在 `3f87e5cb` 删除，
  从未参与编译，**不要再新建**。
- 动过 `.xcstrings` 必须过校验器：

  ```
  python3 docs/tasks/tools/check_xcstrings.py --baseline <改动前的 git ref>
  ```

  它挡：格式偏离 Xcode 规范、增删 key、改 zh-Hans 以外语言、覆盖已有 zh-Hans 译文、
  占位符（`%@` / `%1$@`）不匹配、`state` 不是 `translated`。

## 文档

`docs/` 用中文。`docs/PROGRESS.md` 是「做到哪 / 下一步」唯一入口，**每完成一项就更新**，
不落后于 `git log`。
