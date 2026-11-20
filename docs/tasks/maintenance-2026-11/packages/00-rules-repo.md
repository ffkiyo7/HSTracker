# 包 0　规则与仓库整理（W4、W5、W6）

> 总 spec：`../spec.md`（约束见第 2 节，证据见第 3 节）。本包不改 Swift 代码，什么时候做都可以，不依赖其他包。

## 目标

把仓库和项目规则调整成「上游已断供、独立维护」的状态。

## 要做的事

### 1. 修订本地化规则（D1）

`AGENTS.md`「本地化」一节，第一条改成如下大意（措辞可以调整，含义不变）：

> 译文只放 `.xcstrings`。只增改 zh-Hans，不删 key，不改已有的其他语言译文，不覆盖已有的 zh-Hans 译文。
> 炉石新内容带来的游戏内词条（新系列名、新机制名等）随功能**新增 key**：en 用官方英文名，zh-Hans 取国服客户端 `Strings/zhCN/GLOBAL.txt` 里的官方译名。校验时用 `--allow-new-key <KEY>` 逐个放行。

第二条（改了 `.xcstrings` 必须跑 `check_xcstrings.py --baseline`）保持不变。

### 2. 更新校验脚本说明

`docs/tasks/tools/check_xcstrings.py` 里 `--allow-new-key` 的 help 文字现在写的是「只给 T3 补的 Archive / Unarchive 用」，改成指向新规则。

逻辑不用改：E4 只比较新旧都有的 key，新增的 key 不会被 E4 拦下【核实，L201-207】。

### 3. 补 `BE` 系列名的 zh-Hans

- `Translations/macOS/Localizable.xcstrings` 里 `BE` 这个 key 现在只有 de / en。
- 补上 zh-Hans「黑暗帝国的统治」，来源是 `/Applications/Hearthstone/Strings/zhCN/GLOBAL.txt:165` 的 `GLOBAL_CARD_SET_BE`。
- 这属于补空缺，现行规则本来就允许。

### 4. 仓库整理（W4，D2）

- **git 配置**：`git config --unset remote.upstream.gh-resolved`，再执行 `gh repo set-default ffkiyo7/HSTracker`。`upstream` 这个 remote 本身保留，不改名。
- **`master` 快进**：只在本地快进到 tag `3.7.1`，不推送。
  - 不需要切换分支，用 `git push . '3.7.1^{commit}:refs/heads/master'`。它对非快进会拒绝，效果等同于 `--ff-only`。
  - 执行前先用 `git merge-base --is-ancestor master 3.7.1` 确认能快进。
- **交接记录**：在 `docs/upstream-merges.md` 记下：
  - 最后一次可对齐的上游基座是 `3.7.1`（`782c881c`）；
  - 10-28 上游仓库私有化，此后不再合并上游；
  - HDT 公开源码可以参考到 `2698623` 为止。

### 5. 新拓展包维护流程（W5）

在 `docs/upstream-merges.md` 新增一节「新拓展包维护流程」。内容如下，参照的是上游 37.0 的提交 `aa2ac1a9` / `06709ccc`：

1. **卡牌数据**：按包 1 的规则更新 `cards-version.txt`，以国服客户端 `Power.log` 里的 `BuildNumber=` 为准。
2. **系列枚举**：`CardSet.swift` 两处都要改：
   - 字符串枚举 `CardSet`：加 case，并加进 `deckManagerValidCardSets`；
   - 整数枚举 `CardSetInt`：加 ID。

   少改一处，新卡就会在 `Database.swift:224-233` 被丢弃，或者在牌组管理器里筛不出来。
3. **新机制**：`GameTag.swift` 按需加 tag；`Database.mechanics`（L12-73）按需加映射。
4. **系列名 key**：按第 1 条的新规则新增，zh-Hans 取 `GLOBAL.txt` 里的 `GLOBAL_CARD_SET_<缩写>`。
5. **新卡规则**：只补实际遇到的计数器和关联卡。卡牌 ID 补进 `HSTracker/Logging/CardIds/*.swift`；每个新 `.swift` 在 pbxproj 登记 4 处。

## 验收

- 跑 `python3 docs/tasks/tools/check_xcstrings.py --baseline <改动前 ref>`，必须通过（本包只是补空缺，不需要放行新 key）。
- 在本仓库运行 `gh repo view`，显示的是 `ffkiyo7/HSTracker`。
- `git rev-parse master` 等于 `782c881c…`，origin 上的 `master` 没有变。
- Debug 增量构建通过。打开牌组管理器，系列筛选里 37.0 显示为「黑暗帝国的统治」。

## 记录

- `docs/PLAN.md` 的提交记录补一行（`docs:` / `chore:` 提交）。
- git 配置和 `master` 是本地操作，不进提交，只在 PLAN 的项目细节里提一句。
