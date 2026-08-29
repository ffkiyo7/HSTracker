# Phase 3 / T5 —— 翻译设置窗口的 6 个 catalog（55 条）

先读 `docs/tasks/_common-phase3.md` 里的通用约束（尤其是**术语表**和 `.xcstrings` 写法），再读本文件。

**前置依赖：T1 必须已完成**（`TrackersPreferences.xcstrings` 应已被补上 4 条）。

## 目标文件（只有这 6 个）

| 文件 | 待译 |
|---|---|
| `HSTracker/UIs/Preferences/mul.lproj/BattlegroundsPreferences.xcstrings` | 23 |
| `HSTracker/UIs/Preferences/mul.lproj/ImportingPreferences.xcstrings` | 16 |
| `HSTracker/HSReplay/mul.lproj/HSReplayPreferences.xcstrings` | 9 |
| `HSTracker/UIs/Preferences/mul.lproj/MercenariesPreferences.xcstrings` | 5 |
| `HSTracker/UIs/Preferences/mul.lproj/TrackersPreferences.xcstrings` | 1 |
| `HSTracker/UIs/Preferences/mul.lproj/GeneralPreferences.xcstrings` | 1 |
| **合计** | **55** |

`ImportingPreferences` 和 `MercenariesPreferences` 目前是 **0% 中文**（整页全英文），
就是用户截图里那个 "Importing" 页。

## 这批字符串的特点

全部来自 XIB，key 形如 `3i1-BX-ZbC.title`。常见后缀的含义：

| 后缀 | 是什么 | 长度要求 |
|---|---|---|
| `.title` | 控件标题（checkbox / 按钮 / 标签） | 短，≤12 汉字 |
| `.label` / `.paletteLabel` | 工具栏项标题 | 很短 |
| `.ibShadowedToolTip` | 鼠标悬停提示 | 可以是完整句子 |
| `.placeholderString` | 输入框占位符 | 短 |
| `.headerCell.title` | 表格列头 | 很短 |

每个 key 的 `comment` 字段里有 `Class = "NSButtonCell"` 之类的信息，能看出是什么控件 —— 先读它。

## 翻译要求

1. **同一个 catalog 内用词必须自洽。** 先把该文件里**已有的 zh-Hans** 通读一遍，
   新译的部分沿用它们的用词和句式。例如 `TrackersPreferences` 里已有「显示经验进度」
   这种「显示 XXX」句式，同文件其它 checkbox 就该是「显示 XXX」，不要改成「XXX 显示」。

2. **checkbox 标题用陈述式，不用祈使式。** `Show experience counter` → 「显示经验进度」，
   不要译成「请显示经验进度」或「是否显示经验进度」。

3. **`ImportingPreferences` 里的导入源是专有名词**：HearthArena、Hearthstone Top Decks、
   HSReplay、Tempo Storm 等一律**保留英文**，只翻它们周围的说明文字。

4. **`HSReplayPreferences` 里的账号/订阅词汇**与 T4 的 `Options_HSReplay_Account_*` 保持一致：
   `Premium` → 「高级会员」，`Subscription` → 「订阅」，`Tier7` 保留英文。

5. **`BattlegroundsPreferences` 全部走酒馆战棋官方译名**（术语表里那批随从类型、
   `Tier` → 「等级」、`Lobby` → 「大厅」、`Session` → 「场次」）。

6. **`MercenariesPreferences`** —— 佣兵战纪是已下线的模式，措辞照直译即可，不用纠结。

7. 占位符 `%@` / `%d` 原样保留，校验器会查。

## 验收

1. `python3 docs/tasks/tools/check_xcstrings.py --allow-new-key Archive --allow-new-key Unarchive` 通过。
2. 上表 6 个文件的缺失数应**全部变成 0**。全局仍缺应为 **92**
   （= T4 之后的 147 − 55；其中含 `Localizable.xcstrings` 那 7 个不该翻的符号 key）。
3. 构建通过。
4. 报告里逐文件写明补了多少条，外加「拿不准的译法」清单。
