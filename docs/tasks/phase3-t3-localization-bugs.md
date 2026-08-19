# Phase 3 / T3 —— 修两个「翻译了也不生效」的代码 bug

先读 `docs/tasks/_common-phase3.md` 里的通用约束，再读本文件。

**前置依赖：T1 必须已完成**（本任务要往 `Localizable.xcstrings` 补 key，得在合并之后做）。

## 目标文件

```
HSTracker/HSReplay/HSReplayPreferences.swift
HSTracker/UIs/DeckManager/DeckManager.swift
HSTracker/Core/Extensions/String.swift
Translations/macOS/Localizable.xcstrings
```

**本任务只允许修改这四个。** 注意本任务是本阶段唯一获准新增 key 的任务。

## 问题 1 —— 设置页标题是裸字符串

`HSTracker/HSReplay/HSReplayPreferences.swift:15`：

```swift
var preferencePaneTitle = "HSReplay"
```

其它 8 个设置面板的同名属性都走了 `String.localizedString`，只有这个是裸字符串 —— 翻译了也用不上。

**改法：** 包成 `String.localizedString("HSReplay", comment: "")`，与其它面板写法一致。
先去看另外几个 `*Preferences.swift` 里这一行是怎么写的，照抄那个形式。

> 注意 "HSReplay" 是品牌名，中文照样是 "HSReplay"（`Localizable.xcstrings` 里已有这个 key）。
> 这里修的是「机制不对」，不是「字面不对」—— 说清楚这一点，别把它当成无用改动删掉。

## 问题 2 —— `Archive` / `Unarchive` 两个 key 根本不存在

`HSTracker/UIs/DeckManager/DeckManager.swift:693-694`：

```swift
let labelName = currentDeck?.isActive == true ? "Archive" : "Unarchive"
self.archiveToolBarItem.label = String.localizedString(labelName, comment: "")
```

XIB 里那个工具栏项（`DeckManager.xcstrings` 的 `Fe5-be-5CS.label`）**已经译成「存档」**，
但运行时被上面这行覆写；而 `Localizable.xcstrings` 里**根本没有 `Archive` / `Unarchive` 这两个 key**
（只有 `Archived` → 「已归档」）。于是 `String.localizedString` 回退失败、**原样返回 key**，界面显示英文。

**改法：** 往 `Translations/macOS/Localizable.xcstrings` 补这两个 key。

- 结构照抄该文件里其它 key 的写法：`en` 的 `state` 是 `"new"`，`zh-Hans` 的是 `"translated"`；
  **只补 `en` 和 `zh-Hans` 两种语言**，别的语言留空（我们没有能力给 14 种语言编译译文）。
- 译法：`Archive` → **「归档」**，`Unarchive` → **「取消归档」**。
  与同文件已有的 `Archived` → 「已归档」保持词根一致。
- key 在 `strings` 对象里的位置：该文件的 key 按 Xcode 的排序规则排列，插到 `Archived` 附近，
  让 diff 看起来是局部插入而不是整文件重排。

> `DeckManager.xcstrings` 里那个 `Fe5-be-5CS.label` = 「存档」和这里的「归档」不一致，
> 但那条 XIB 译文在运行时会被上面这行代码覆写，实际不可见。
> **本任务不许动 `.xcstrings` 之外的 XIB 相关文件、也不许动 `DeckManager.xcstrings`** ——
> 把这个不一致写进报告即可。

## 问题 3 —— `String.localizedString` 的失败是静默的

`HSTracker/Core/Extensions/String.swift:81-93`：key 完全不存在时它返回 key 本身，
界面上看起来就是"没翻译"，不会有任何报错。问题 2 就是这么潜伏下来的。

**改法：** 在返回 key 的那条兜底路径上，加一句 **仅 DEBUG 生效** 的日志，把 key 打出来。

- 用仓库既有的日志设施（看 `Logger` / `logger` 在别处怎么用的，直接照抄），不要引新依赖
- 用 `#if DEBUG` 包起来，Release 构建里一行代码都不要多
- **不要用 `assert` / `fatalError`** —— 现在有几百个 key 缺译，断言会让 Debug 构建根本跑不起来
- 别的分支的行为一个字都不许改：函数的返回值语义必须与改动前完全一致

## 验收

1. 构建通过（本任务改了 `.swift`，构建是硬性的）。
2. `python3 docs/tasks/tools/check_xcstrings.py` —— **本任务会新增 2 个 key，
   所以校验器的 E3 一定会报两条 `Archive` / `Unarchive`**。这是预期内的，其余项必须全过。
   然后跑 `python3 docs/tasks/tools/check_xcstrings.py --allow-new-key Archive --allow-new-key Unarchive`，这一次必须完全通过。
   两次输出都贴进报告。
3. 报告里写明：三处改动各自的一句话说明，以及 `String.swift` 那处改动**没有**影响任何返回值。
