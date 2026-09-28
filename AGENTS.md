# AGENTS.md

本仓库所有 AI 助手的唯一规则文件，只写约束。HSTracker：macOS 炉石记牌器，Swift + AppKit / SwiftUI，
`HearthSim/HSTracker` 的个人自用 fork，不回流上游，本文件 > 上游 `CONTRIBUTING.md`。
工作分支 `dev0923`（基座上游 3.6.12，2026-09-23 换轨，见 `docs/REFORK.md`）；旧线 `dev`（基座 3.6.9）冻结作回滚点，不再动；
`master` 是上游纯镜像，只 `--ff-only`，不提交自己的改动。

## 写文件

- 改文件只用编辑工具，禁止 shell 写文件（`sed -i`、heredoc、`cat >`、脚本落盘）。读文件不限。
- zsh 不做单词分词：不写 `for a in $VAR`、`$CMD args`。

## Commit

- Conventional Commits 前缀（`feat` / `fix` / `perf` / `docs` / `chore` / `build` / `test`），merge commit 不加。
- 保留 `Co-Authored-By:`；不写 `Claude-Session:` 和 `claude.ai/code/session_...` 链接。

## 线程与时序

- `HearthWatcher/` 回调在各自队列。写 SwiftUI view model 必须先 `DispatchQueue.main.async`，同一份状态在同一个 main block 内提交，禁止 `main.sync`。
- 改 overlay / view model 时序前，列出写入到显示的每一跳 `main.async`。判断不了就加只在状态翻转时打的日志实跑一局，用完删。
- 读 `QueueEvents.isInQueue` 的代码不得在对局路径上。

## 构建

```
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' clean build
```

- 只认上面的受限环境；测试把 `clean build` 换成 `test`。`HearthMirror-version.txt` 变了才 `clean build`，其余增量。
- build phase：不改写 `HSTracker/Resources/`；`NET_VERSION` 保持 `net8.0`；BobsBuddy / HearthDb 只由 `Vendor/Managed/` + `*-version.txt` 提供，升级只走 `scripts/update-managed-deps.sh`；只有 github.com 走代理。
- `project.pbxproj` 任务没要求就不动；新 `.swift` 手工登记 4 处，漏了不报错。

## 本地化

- 译文只放 `.xcstrings`；只增改 zh-Hans，不增删 key、不改其他语言、不覆盖已有译文。
- 动过 `.xcstrings` 必须过 `python3 docs/tasks/tools/check_xcstrings.py --baseline <改动前 ref>`。

## 文档

`docs/` 用中文。四类文件，各管一件事：

| 文件 | 放什么 | 不放什么 |
|---|---|---|
| `docs/PLAN.md` | 唯一的计划 + 进度：阶段一行一状态 + 依据（commit / 日期）、🎮 待看、等用户定、未修问题、默认值差异、仍作数的决策 | 已完成阶段的分析、实测数据、排查经过 |
| `docs/REFORK.md` / `docs/upstream-merges.md` | 换轨步骤 / 合并手册 | — |
| `docs/tasks/*.md` | **在做和待验**的任务书，执行结果追加在书末 | 验收通过的（挪 `docs/archive/tasks/`） |
| `docs/archive/` | 归档原文，不改（事实错误除外） | — |

- 每完成一项就更新 `PLAN.md`，不落后于 `git log`；完成的条目改一行状态 + 依据，不保留过程。
- **归档看状态，不看行数**：✅ / ❌ 且依据已写进状态行的、已拍板的、已修的、结论已提炼成一行的数据和经过 —— 整段挪进 `docs/archive/`；🚧 / 🎮 / ⬜ / ⏸ 的一律留着。`PLAN.md` 超过 150 行只是提醒去清一遍，清完还超就让它超。
- 已完成的东西**归档而不是划线**：不手写 `~~`，不让做完的条目继续占位。
- 状态符号在最前：✅ 完成 / ❌ 取消 / 🚧 进行中 / 🎮 待实测 / 🖥️ 静态看 / ⏸ 暂缓 / ⬜ 未开始；清单用 `[ ]` / `[x]` / `[-]`。
- 决策理由、数字、路径、命令、未决问题只能挪位置，不能丢；删过期内容要在汇报里给依据。
- 战棋不作为验收手段，只做静态确认。
