# REFORK S1：构建层

计划见 `docs/REFORK.md` S1；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`（相对主仓库根）。起点上游 `3.6.12`，本任务之前没有任何我们的提交。
- 所有改动只落在这个 worktree。主仓库（分支 `dev`）只读，用来查我们旧的实现：`git show dev:<path>`、`git log master..dev`。
- worktree 里没有 `AGENTS.md` / `docs/`，规则以主仓库 `dev` 上的为准。

## 目标

受限环境（`AGENTS.md`「构建」那条命令）下 `clean build` 通过。S0 基线：3.6.12 在受限环境下失败于「Download BobsBuddy and HearthDb」—— `PATH` 里没有 `wget`；普通环境能构建，测试 151 条 150 过，唯一失败是 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（ad-hoc 签名的自编译包，预期内）。

## 要落地的东西

dev 上做过、3.6.12 没有的构建层改动，逐条对着 3.6.12 现状判断：原样搬、改写后搬、还是已被上游取代（取代的写出依据，不搬）。

- `990af8ec` wget 阶段的 PATH
- `33a8b001` 卡牌下载走代理 + 缓存（只有 github.com 走代理，代理探到才设）
- `9648aabf` 包内文件在构建时丢失（3.6.12 的 Embed Mono 已改为写 `Contents/Resources/Managed`，重点看是否已被取代）
- `2a050460` / `5f517674` Embed Mono 的 mono 8.0.29 适配与输入依赖
- `2b8f2860` 部署目标 14.0：3.6.12 共 6 处 `MACOSX_DEPLOYMENT_TARGET = 10.15`，全部改 14.0
- `756e08a5` BobsBuddy / HearthDb 制品固定进仓库：`Vendor/Managed/*.zip` + `HSTracker/BobsBuddy-version.txt` + 新建 `HSTracker/HearthDb-version.txt`（上游没有此文件，要登记进 Resources 与 build phase inputs）+ 版本强校验 + `scripts/update-managed-deps.sh`

## 约束

- BobsBuddy 必须 ≥ 3.6.12 的 `BobsBuddy-version.txt`（1.76.3）；3.6.12 代码用到了 `BobsBuddySimulationFailure` 和 Deity 接口，旧的 1.71.1 不能用。制品只通过 `scripts/update-managed-deps.sh` 取（需要访问 libs.hearthsim.net），取到的实际版本写进报告。
- build phase 不改写 `HSTracker/Resources/`。`NET_VERSION` 上游已由 `mono-version.txt` 推出，结果须仍是 `net8.0`，不要另外写死。
- `project.pbxproj` 本任务允许改，只动构建设置与 build phase，不动 Sources 登记。
- 不改任何 Swift 源码、测试、`.xcstrings`。

## 验收

- 受限环境 `clean build` → `BUILD SUCCEEDED`。
- 受限环境 `test`：151 条，失败只能是上面那一条。
- 增量构建：只改 `BobsBuddy-version.txt`（改成与 zip 不符的值）时构建必须失败并报版本不符；改回后再构建，包里 `Contents/Resources/Managed/` 下的 BobsBuddy DLL 与 zip 内容一致。
- 报告里给出：每条 dev 提交的处理结论（搬 / 改写 / 已取代 + 依据）、BobsBuddy 与 HearthDb 的最终版本、`git diff 3.6.12 --stat`。

## 执行结果

（执行者追加）
