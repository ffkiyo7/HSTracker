# AGENTS.md

本仓库所有 AI 助手（Claude Code / Codex 等）的唯一规则文件。只写约束，不写理由和经过。

HSTracker：macOS 炉石记牌器，Swift + AppKit / SwiftUI。`HearthSim/HSTracker` 的个人自用 fork
（`ffkiyo7/HSTracker`），不回流上游，本文件 > 上游 `CONTRIBUTING.md`。
计划 `docs/PLAN.md`，进度 `docs/PROGRESS.md`，过程记录 `docs/archive/`。

## 写文件

- 改文件一律用编辑工具（Claude Code：Write / Edit）。禁止用 shell 写文件：`sed -i`、heredoc、`cat >`、脚本落盘都不行。
- 读文件不限，`grep` / `sed -n` / `head` 随意。
- zsh 不做单词分词：不写 `for a in $VAR`、`$CMD args`。

## Commit

- Conventional Commits 前缀：`feat` / `fix` / `perf` / `docs` / `chore` / `build` / `test`；merge commit 不加。
- 标题 ≤50 字符，祈使语气，无句号，前缀后小写开头（专有名词除外）。
- 正文写为什么，不复述 diff；≤80 列折行（中日韩字符算 2 列）。
- 执行模型写的代码注明依据哪本任务书、review 额外改了什么。
- 保留 `Co-Authored-By:`；不写 `Claude-Session:` 和任何 `claude.ai/code/session_...` 链接。
- 一个 commit 只做一件事。

## 跟上游

- `master` 是上游纯镜像，只允许 `git merge --ff-only upstream/master`，不提交任何自己的改动。
- 工作分支 `dev`。合上游按 `docs/upstream-merges.md` 走，合完在那里追加一节，并更新 PROGRESS 的基线 commit 和构建状态。

## 任务书与执行模型

代码由执行模型按 `docs/tasks/*.md` 写，人工 review 后提交。`docs/tasks/` 只放在做和待验的，验收后挪进 `docs/archive/tasks/`。

执行侧硬规则（任务书必须复述，现有版本在 `docs/tasks/_common*.md`）：

1. 只改任务书指定的文件；别处的问题写进报告。
2. 不 `git add`，不 `commit`。
3. 不动 `Config.xcconfig`（已 `skip-worktree`）。
4. 风格与周围一致，不加大段注释。
5. 改完跑受限环境构建，确认 `BUILD SUCCEEDED`。
6. 改完跑测试。全绿是基线，红了就是回归；不为变绿改被测代码，旧预期确实过期才改测试并在报告里给依据。

写任务书：

- 给约束，不给实现：语义要求、不变量、要它论证没踩的失败模式、验收命令。
- 代码块只用于引用现状和验收命令，不贴函数体。篇幅 50~70 行。
- 指路径不列属性：写「照哪个函数的账复刻」，不抄具体数值。
- 排查类任务只给症状、证据、硬约束、验收标准；不给候选清单，不给「已排除」结论。
- review 侧的读法要标明「可能读错，请独立复核」。

## 线程与时序

- `HearthWatcher/` 回调跑在各自的 `DispatchQueue`。从回调直接或间接写 SwiftUI view model 的路径必须先 `DispatchQueue.main.async`；同一份状态在同一个 main block 内提交；禁止 `DispatchQueue.main.sync`。
- 改 overlay / view model 时序前，列出从写入到显示的每一跳 `main.async`，不假设回调同步。
- 读代码判断不了时，加一行只在状态翻转时打的日志实跑一局，用完删除。
- 读 `QueueEvents.isInQueue` 的代码不得位于对局路径上。

## 构建

```
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' clean build
```

- 验证「构建能不能过」只认上面的受限环境。测试：同一命令把 `clean build` 换成 `test`。
- 沙箱里首次测试因无权写 `~/Library/Caches/org.swift.swiftpm` 失败 → 本机权限重跑。
- `DatabaseTests` 断言英文用 `card.enText`，不用 `card.text`。
- Release 包不往 stdout 打日志，只看 `~/Library/Logs/HSTracker/hstracker.log`。
- 首次从 `Build/Products/Release` 启动会被 AppMover 模态框阻塞：点 Don't Move；判断是否起来看 `pgrep -lx HSTracker` 加 log mtime。
- 排查渲染问题前先确认包完整：`Contents/Resources/CardDefs.bin`、`Contents/Resources/Managed/`。
- `HearthMirror-version.txt` 变了必须 `clean build`；其余情况增量构建即可。

build phase：

- 不许改写源码目录 `HSTracker/Resources/`。
- 声明 outputs 时，inputs 必须覆盖该 phase 真正读的所有东西。
- `Embed Mono` 拷 `net8.0` 整个目录，不用白名单；`NET_VERSION` 保持 `net8.0`。
- BobsBuddy / HearthDb 的 zip 固定在 `Vendor/Managed/`，版本只由 `BobsBuddy-version.txt` / `HearthDb-version.txt` 声明。
- `Install vendored BobsBuddy and HearthDb` 必须保留 staging → 校验 → `cp`，不直接 unzip 到 outputs，不放宽版本校验。
- 升级依赖只走 `scripts/update-managed-deps.sh`（先无参看版本，再 `--apply <BobsBuddy版本> <HearthDb版本>`），之后必须构建。
- 只有 github.com 走代理（`127.0.0.1:7890` 探到才设），其余直连。

`project.pbxproj`：

- 除非任务明确要求，不动。
- 新 `.swift` 手工登记 4 处：`PBXBuildFile`、`PBXFileReference`、group、Sources phase。漏登记不报错、文件被静默忽略。
- 自查：`grep -c "新文件.swift" HSTracker.xcodeproj/project.pbxproj` 应为 3~4。

## 本地化

- 译文只放 `.xcstrings`，不新建 `.lproj/*.strings`。
- 只增改 zh-Hans；不增删 key，不改其他语言，不覆盖已有 zh-Hans 译文。
- 动过 `.xcstrings` 必须过：`python3 docs/tasks/tools/check_xcstrings.py --baseline <改动前的 git ref>`

## 文档

- `docs/` 用中文。进度文档一项一行，只写「做到哪 / 下一步 / 依据（commit 或日期）」；决策过程和排查经过不进进度文档。
- `docs/PROGRESS.md` 每完成一项就更新，不落后于 `git log`。
- 状态符号：清单 `[ ]` / `[x]` / `[-]`；表格用 ✅ 完成 / ❌ 取消 / 🚧 进行中 / 🎮 待实测 / ⬜ 未开始，符号在最前。
- 删除线由 `strike-done` 脚本加，不手写 `~~`。
- 战棋不作为验收手段（用户不玩），只做静态确认。
