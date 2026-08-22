# AGENTS.md

写给在这个仓库里干活的 AI 助手（Claude Code / 本机 grok-4.6 / Codex 等）。人也可以看。

优先级：**本文件 > 上游 `CONTRIBUTING.md`**。理由见下一节。

## 这是什么仓库

HSTracker —— macOS 上的炉石传说记牌器，Swift + AppKit。

- 本仓库是 `HearthSim/HSTracker` 的**个人自用 fork**（`ffkiyo7/HSTracker`）。
- **不打算把改动回流上游**。因此上游的 `CONTRIBUTING.md` 只当参考，不是我们的规矩。
- 但**会持续从上游 merge**，每个 release 跟一次。下面好几条约定是由这一条推出来的。

改造计划见 `docs/PLAN.md`，当前进度见 `docs/PROGRESS.md`。

## Commit 规范

用 Conventional Commits 前缀：`feat` / `fix` / `perf` / `docs` / `chore`（merge commit 不加前缀）。

**理由是我们自己的**，不是照抄上游：跟完上游之后 `git log` 里两边的提交是混在一起的，
上游恰好也在用同一套前缀，统一纯粹是为了我们自己翻历史时好读。哪天不再跟上游了，这条可以推翻。

- 标题：**≤50 字符**，祈使语气，不加句号。前缀后面小写开头（专有名词除外）。
- 正文：解释**为什么**这么改，而不是复述 diff 改了什么。按**显示宽度**折行，
  **≤80 列**（中日韩字符算 2 列）。
- 正文里注明代码是谁写的：如果由 grok-4.6 按任务书生成，写明依据哪本任务书、
  以及 review 时额外改了什么。
- 结尾保留 `Co-Authored-By:` 尾注。
- **不要写 `Claude-Session:` 或任何 `https://claude.ai/code/session_...` 链接。**
- 一个 commit 只做一件事。

## 跟上游的流程

```
git fetch upstream --tags
git checkout master && git merge --ff-only upstream/master   # master 只做快进，不在上面提交
git checkout <工作分支> && git merge master
```

`master` 是上游的纯镜像 —— **任何我们自己的改动都不许提交到 master**，否则以后没法快进。
合完之后要更新 `docs/PROGRESS.md` 里的基线 commit 和构建状态。

## 分工：任务书交给本地模型

Phase 0 / Phase 3 的代码由本机 grok-4.6 按 `docs/tasks/*.md` 里的任务书写成，人工 review 后提交。
给这类模型下任务时，任务书必须复述以下硬性规则（现有的写在 `docs/tasks/_common*.md`）：

1. **只改任务书明确指定的文件。** 发现别处也有问题，写进报告，不要顺手改。
2. **不要 `git add`，不要 `commit`。** 改完留在工作区，由人 review 后统一提交。
3. **不要动 `Config.xcconfig`。** 它已改成本地签名并 `git update-index --skip-worktree`。
4. 保持与周围代码一致的风格。这个仓库注释偏少，**不要加大段注释**；
   只在改动原因不明显时写一两行说明为什么。
5. 改完自己跑一遍验收构建，确认 `BUILD SUCCEEDED`。

### 写任务书的规矩：给约束，不给实现

**代码块只用于两件事：引用现状（要改的那段现在长什么样）和验收命令。不要贴函数体。**
篇幅以 T1–T4 的 50~70 行为准 —— concise 且准确。

三条理由：

1. **review 的信度。** 实现是写任务书的人给的，review 就变成自己批自己，
   双模型复核退化成单人干活 —— 而这套分工的全部价值就在于两边各出一次力。
2. **可观测性。** 看不到本地模型的真实工程能力，就无从判断下一个任务该给它多大。
3. **token 分摊。** 实现写在任务书里，成本全压在写任务书的那一侧，方向正好反了。

判据是 2026-08-21 的 T5：任务书 226 行、33% 是代码块，产出的 55 行新增里 **43 行逐字来自任务书**，
grok 实际写的逻辑代码是 0 行。对照 T1–T4 —— 代码块 0 行、篇幅 48~73 行 —— 同样顺利落地。

难的从来不是把实现写出来，是**把约束写准**：语义要求、不变量、明确点名那些
「按字面实现会比现状更糟」的失败模式并要求它在报告里论证自己为什么不踩、验收命令。
T5 那两个坑（trailing-edge 防抖会饿死 overlay、16ms 窗口撞上渲染 p95 会堆积）
三句话就能说清，不需要给代码。

能让它自己查出来的就别替它列 —— 比如「所有绕过 `updateTrackers()` 直接置位的地方」，
让它 grep，找不到正是 review 该抓的。

## 构建

```
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' build
```

**Xcode.app 由 launchd 拉起，既没有 homebrew 的 PATH，也没有 shell 里的代理变量**；命令行 `xcodebuild`
两样都继承，所以同一份代码在命令行能过、在 Xcode 里会挂。五个联网 phase 的开头因此都注入了 PATH 和
**条件代理**（`nc -z 127.0.0.1 7890` 探测到才设，没开代理时回落直连）。

**判断「构建能不能过」时必须区分这两个环境** —— 在 shell 里 `command -v wget` 有结果、`curl` 能通，
都不代表 Xcode 里点 Build 能过。要验证就用受限环境跑：

```
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' clean build
```

`Contents/Resources/Resources/` 在 bundle 里有**两个写入者**：`Resources` build phase 会把
`HSTracker/Resources/` 这个 folder reference 整目录拷过去，而 `Download cards XML` 和 `Embed Mono`
往同一个目录里写 `Cards/` 和 `Managed/<arch>/`。**任何 build phase 都不许改写 `HSTracker/Resources/`** ——
一改就会重新触发那个整目录拷贝，它可能落在脚本阶段之后，把 `Cards/` 和 `Managed/arm64` 冲掉，
表现为 mono 找不到 corlib 而 `abort()`（在 Xcode 里看是「应用程序没有响应」）。下载产物一律放
`downloaded-frameworks/`，再由 `Embed Mono`（排在 `Resources` 之后）拷进 bundle。

**不需要有人改写 `HSTracker/Resources/` 也会踩到 —— 增量 `build` 里那个整目录拷贝自己重跑就够了。**
两个脚本阶段的自愈能力不对称：`Embed Mono` 没声明 outputs，每次构建都跑，所以 `Managed/` 总能补回来；
`Download cards XML` 声明了 outputs，被依赖分析判为最新就跳过，`Cards/` **不会**补回来。
2026-08-22 实际踩了一次：包里没有 `Cards/CardDefs.xml`，`Database.swift:252` 读不到卡库，
`Cards.by(cardId:)` 对每张卡都返回 nil，于是**记牌器只剩计数 / 抽牌概率 / 胜率那几个框，一根卡条都没有**
（那几个框走 entity 计数和 Realm，不依赖卡库）。症状很像渲染层的 bug，实际是构建产物残缺。

所以：**要交给人做实测的包必须 `clean build`**，或者构建完自查一行：

```
ls "$(...)/HSTracker.app/Contents/Resources/Resources/Cards/CardDefs.xml"
```

`Embed Mono` 拷 `net8.0` **整个目录**而不是白名单：BobsBuddy 下载的永远是最新版，它每新增一个 BCL
依赖，手写清单就会静默漏掉一个，且只在运行时报错。全量 17MB/arch。

只有 **github.com 需要走代理**（直连超时），nuget / libs.hearthsim.net / api.hearthstonejson.com 直连均可。
`CardDefs.xml` 约 100MB，按版本缓存在 `downloaded-frameworks/cards/`，只有 `cards-version.txt` 变了才重新下载。

注意 `HSTracker.xcodeproj/project.pbxproj` 里 "Embed Mono" build phase 的 `NET_VERSION` 是 `net8.0`
（上游 `d70efe05` 升级 mono 到 8.0.29 时漏改，我们在 `2a050460` 修了）。**除非任务明确要求，不要动这个文件。**

**新加的 `.swift` 文件必须手工登记进 `project.pbxproj`**（`PBXBuildFile` + `PBXFileReference` +
所属 group + Sources build phase，共 4 处）。工程虽然是 `objectVersion = 70`，但唯一的
`PBXFileSystemSynchronizedRootGroup` 只覆盖 `AnimalCompanionGenerator/`，`HSTracker/` 不在其中。

漏登记**不会报编译错误** —— 文件被静默忽略，只有当别处按名字引用它时才会暴露。上游 3.6.5 就踩了这个坑：
`EternalKnightCounter.swift` / `AncestralAutomatonCounter.swift` 两个文件加进了仓库却没进 pbxproj，
CHANGELOG 宣传的两个战棋计数器实际没有被编译。加完新文件后请自查：

```
grep -c "你的新文件.swift" HSTracker.xcodeproj/project.pbxproj   # 应为 3~4，不是 0
```

## 本地化

简体中文（zh-Hans）已补到 99.2%，详见 `docs/PROGRESS.md` 的 Phase 3 小节。

- 译文只放在 **String Catalog（`.xcstrings`）** 里。
  各语言的 `.lproj/*.strings` 已在 `3f87e5cb` 删除 —— 那些文件从来没参与过编译，
  **不要再新建**。
- 动过 `.xcstrings` 之后必须过校验器：

  ```
  python3 docs/tasks/tools/check_xcstrings.py --baseline <改动前的 git ref>
  ```

  它会挡住：格式偏离 Xcode 规范写法、增删 key、改动 zh-Hans 以外的语言、
  覆盖已有的 zh-Hans 译文、占位符（`%@` / `%1$@`）不匹配、`state` 不是 `translated`。

## 文档

`docs/` 下的文档用中文写。`docs/PROGRESS.md` 是「做到哪了 / 下一步是什么」的唯一入口，
**每完成一项就更新它**，不要让它落后于 `git log`。
