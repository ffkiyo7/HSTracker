# AGENTS.md

写给在这个仓库里干活的 AI 助手（Claude Code / Codex 等）。人也可以看。

HSTracker 是 macOS 上的炉石传说记牌器，Swift + AppKit。本仓库是 `HearthSim/HSTracker` 的
**个人自用 fork**（`ffkiyo7/HSTracker`），**不回流上游**，所以**本文件 > 上游 `CONTRIBUTING.md`**；
但**会持续从上游 merge**，每个 release 跟一次 —— 下面好几条约定都由这一条推出。

改造计划见 `docs/PLAN.md`，进度见 `docs/PROGRESS.md`。这两份是**精简版**，只写「要做什么 /
做到哪了」；执行细节、review 记录、A/B 比对归档在 `docs/archive/`。

## Commit 规范

用 Conventional Commits 前缀：`feat` / `fix` / `perf` / `docs` / `chore`（merge commit 不加前缀）。
理由是我们自己的：跟完上游之后 `git log` 里两边的提交混在一起，上游恰好也用同一套前缀，
统一纯粹是为了自己翻历史时好读。

- 标题 **≤50 字符**，祈使语气，不加句号，前缀后小写开头（专有名词除外）
- 正文解释**为什么**这么改，不复述 diff。按显示宽度折行 **≤80 列**（中日韩字符算 2 列）
- 注明代码是谁写的：由执行模型按任务书生成的，写清依据哪本任务书、review 时额外改了什么
- 保留 `Co-Authored-By:` 尾注
- **不要写 `Claude-Session:` 或任何 `https://claude.ai/code/session_...` 链接**
- 一个 commit 只做一件事

## 跟上游的流程

```
git fetch upstream --tags
git checkout master && git merge --ff-only upstream/master   # master 只做快进，不在上面提交
git checkout <工作分支> && git merge master
```

`master` 是上游的纯镜像 —— **任何我们自己的改动都不许提交到 master**，否则以后没法快进。
合完要更新 `docs/PROGRESS.md` 里的基线 commit 和构建状态。

## 分工：任务书交给执行模型

代码由 **Codex** 按 `docs/tasks/*.md` 里的任务书写成，人工 review 后提交。
`docs/tasks/` 只放**在做和待验**的书，验收通过就挪进 `docs/archive/tasks/`（那边有索引）——
所以打开这个目录看到的永远是「现在该看哪几本」。
任务书必须复述以下硬性规则（现有的写在 `docs/tasks/_common*.md`）：

1. **只改任务书明确指定的文件。** 发现别处也有问题，写进报告，不要顺手改。
2. **不要 `git add`，不要 `commit`。** 改完留在工作区，由人 review 后统一提交。
3. **不要动 `Config.xcconfig`。** 它已改成本地签名并 `git update-index --skip-worktree`。
4. 风格与周围一致。这个仓库注释偏少，**不要加大段注释**，只在改动原因不明显时写一两行。
5. 改完自己跑一遍验收构建，确认 `BUILD SUCCEEDED`。

### 写任务书的规矩：给约束，不给实现

**代码块只用于两件事：引用现状和验收命令，不要贴函数体。** 篇幅以 50~70 行为准。

三条理由：**review 的信度**（实现是写任务书的人给的，review 就变成自己批自己，
双模型复核退化成单人干活）；**可观测性**（看不到执行模型的真实工程能力，
就无从判断下个任务该给多大）；**token 分摊**（实现写在任务书里，成本全压在贵的那一侧）。

判据是 2026-08-21 的 T5：任务书 226 行、33% 是代码块，产出的 55 行新增里 **43 行逐字来自任务书**，
执行模型实际写的逻辑代码是 0 行。对照 T1–T4（代码块 0 行、篇幅 48~73 行）同样顺利落地。

难的不是把实现写出来，是**把约束写准**：语义要求、不变量、明确点名那些「按字面实现会比现状更糟」
的失败模式并要求它在报告里论证自己没踩、验收命令。能让它自己 grep 出来的就别替它列 ——
找不到正是 review 该抓的。

**任务书写的约束本身也可能是错的。** 2026-08-28 的 T4 让「段头复刻 `DeckLens` 的边框色 `#141617`」，
而 `DeckLens` 的 `NSBox` 是 `.noBorder` + `borderWidth = 0`，那行 `borderColor` 根本不生效 ——
照做就多画了一条现状没有的线。列属性不如指路径：**写「照哪个函数的 frame 账复刻」**。

## 构建

```
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' build
```

**Xcode.app 由 launchd 拉起，既没有 homebrew 的 PATH，也没有 shell 里的代理变量**；命令行
`xcodebuild` 两样都继承，所以同一份代码在命令行能过、在 Xcode 里会挂。五个联网 phase 的开头
因此都注入了 PATH 和**条件代理**（`nc -z 127.0.0.1 7890` 探测到才设，没开代理时回落直连）。
**判断「构建能不能过」必须区分这两个环境**，要验证就用受限环境跑：

```
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' clean build
```

### bundle 装配（3.6.7）

`Resources` build phase 仍会把 `HSTracker/Resources/` 这个 folder reference 整目录拷到
`Contents/Resources/Resources/`，所以 **build phase 仍然不许改写源码目录 `HSTracker/Resources/`**。
但 3.6.7 已把两个运行时产物移出这个会被整目录替换的位置：

- 三份卡库 XML 按 `cards-version.txt` 缓存在 `downloaded-frameworks/cards/<version>/`，构建时只暂存到
  `BUILT_PRODUCTS_DIR`；`Compile CardDefs` 把它们编译为 `Contents/Resources/CardDefs.bin`。
- Mono BCL、BobsBuddy 和 HearthDb 统一装到 `Contents/Resources/Managed/`；源码 folder reference
  不再碰这个目录。

2026-08-29 实测：`clean build` 后强制更新 `HSTracker/Resources/` 目录时间，再跑增量 `build`，
`CardDefs.bin`、两架构各 168 个 BCL DLL 和根目录的 BobsBuddy / HearthDb 都仍在。
因此 **交包不再要求每次 `clean build`**；增量包不会再因 Resources 阶段重跑而丢卡库。

另一个独立情况仍要 clean：`HearthMirror-version.txt` 变化时，下载阶段会在同一次增量构建中替换
framework，已有预编译头可能报 “modified since the precompiled header was built”。这是明确的缓存失效，
执行一次 `clean build` 即可，不要误判成源码编译错误。

**改 build phase 时先想清楚 inputs / outputs 是否覆盖了它真正读写的东西。** 声明了 outputs 就等于
放弃「每次都跑」的自愈性，此后**只有 inputs 变化才会重跑**。3.6.7 给 `Embed Mono` 加了 6 个 outputs，
而它的 inputs 原本只有 `mono-version.txt` —— 但这个阶段同时负责把 `downloaded-frameworks/managed/`
的 BobsBuddy / HearthDb 拷进 bundle。于是只改 `BobsBuddy-version.txt` 跑增量时，下载阶段重跑、
`Embed Mono` 被判最新跳过，**包里留着旧的 BobsBuddy.dll**。修法是把那三个 DLL 补进 `Embed Mono`
的 inputPaths —— 它们正是下载阶段声明的 outputs，这样两个阶段之间才有一条真实的依赖边。

这类问题的共同症状是**看起来像代码 bug，实际是构建产物残缺**。2026-08-22 就踩过一次同构的：
包里缺 `CardDefs.xml` → `Cards.by(cardId:)` 全返回 nil → 记牌器只剩几个计数框、一根卡条都没有
（那几个框走 entity 计数和 Realm，不依赖卡库）。**排查渲染层之前先确认包是完整的。**

### 其余

- `Embed Mono` 拷 `net8.0` **整个目录**而非白名单：BobsBuddy 独立发布时可能新增 BCL 依赖，
  手写清单会静默漏项、且只在运行时报错。当前全量 168 个 DLL / arch。
- `BobsBuddy-version.txt` 现在是强校验：服务器仍只提供 latest 包，但下载后会读取程序集信息版本，
  与文件不一致就立即让构建失败；不再静默把“最新版”冒充成声明版本。
  **代价是这个 pin 会自己过期** —— HearthSim 一发新版，下一次构建就红。
  2026-08-30 就撞了一次（`expects 1.69.0, but the server published 1.69.1`，当天早些时候还是好的）。
  **正确反应是把版本文件改成服务器上的那个数，不是放宽校验。** 失败发生在下载阶段、
  一行 Swift 都没编译，所以看到这条报错不用怀疑代码；已缓存的旧 DLL 也不会被覆盖。
- 只有 **github.com 需要走代理**（直连超时），nuget / libs.hearthsim.net / api.hearthstonejson.com 直连均可。
  `CardDefs.xml` 约 100MB，按版本缓存在 `downloaded-frameworks/cards/`，`cards-version.txt` 变了才重下。
- `Embed Mono` 的 `NET_VERSION` 是 `net8.0`（上游 3.6.7 仍是 `net7.0`）。
  **除非任务明确要求，不要动 `project.pbxproj`。**

### 新加 `.swift` 必须手工登记进 `project.pbxproj`

`PBXBuildFile` + `PBXFileReference` + 所属 group + Sources build phase，共 4 处。工程虽然是
`objectVersion = 70`，但唯一的 `PBXFileSystemSynchronizedRootGroup` 只覆盖 `AnimalCompanionGenerator/`。

**漏登记不会报编译错误** —— 文件被静默忽略。上游就踩过：`EternalKnightCounter.swift` /
`AncestralAutomatonCounter.swift` 进了仓库却没进 pbxproj，CHANGELOG 宣传的两个战棋计数器
实际没被编译（到 3.6.7 仍未修）。加完新文件自查：

```
grep -c "你的新文件.swift" HSTracker.xcodeproj/project.pbxproj   # 应为 3~4，不是 0
```

## 本地化

简体中文（zh-Hans）已补到 99.2%，详见 `docs/PLAN.md` 的 Phase 3 小节。

- 译文只放在 **String Catalog（`.xcstrings`）** 里。各语言的 `.lproj/*.strings` 已在 `3f87e5cb`
  删除 —— 那些文件从来没参与过编译，**不要再新建**。
- 动过 `.xcstrings` 之后必须过校验器：

  ```
  python3 docs/tasks/tools/check_xcstrings.py --baseline <改动前的 git ref>
  ```

  它会挡住：格式偏离 Xcode 规范写法、增删 key、改动 zh-Hans 以外的语言、覆盖已有的 zh-Hans 译文、
  占位符（`%@` / `%1$@`）不匹配、`state` 不是 `translated`。

## 文档

`docs/` 下的文档用中文写。`docs/PROGRESS.md` 是「做到哪了 / 下一步是什么」的唯一入口，
**每完成一项就更新它**，不要让它落后于 `git log`。
