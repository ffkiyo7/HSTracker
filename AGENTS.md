# AGENTS.md

本仓库所有 AI 助手的唯一规则文件，只写约束。HSTracker：macOS 炉石记牌器，Swift + AppKit / SwiftUI，
`HearthSim/HSTracker` 的个人自用 fork，不回流上游，本文件 > 上游 `CONTRIBUTING.md`。
工作分支 `dev0923`（基座上游 3.6.13）；旧线 `dev` 冻结作回滚点，不再动；`master` 是上游纯镜像，只 `--ff-only`，不提交自己的改动。

## Commit 与 PR

- Conventional Commits 前缀（`feat` / `fix` / `perf` / `docs` / `chore` / `build` / `test`），merge commit 不加。
- 保留 `Co-Authored-By:`。commit message、PR 标题和描述、PR / issue 评论里不写 `Claude-Session:`、任何 `claude.ai` 会话 / 项目 / 线程链接（含「Requested by … · project thread」）和「Generated with / by Claude Code」行；工具自动加上的，发完立刻删掉。

## 线程与时序

- `HearthWatcher/` 回调在各自队列。写 SwiftUI view model 必须先 `DispatchQueue.main.async`，同一份状态在同一个 main block 内提交，禁止 `main.sync`。
- 改 overlay / view model 时序前，列出写入到显示的每一跳 `main.async`。
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

`docs/` 用中文。`docs/PLAN.md` 只记提交记录、构建 / 测试记录和项目细节，做完一项补一行；
`docs/upstream-merges.md` 是合并手册；`docs/archive/` 是归档原文，不改。
