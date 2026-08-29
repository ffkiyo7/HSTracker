# Phase 3 / T2 —— 清掉从不参与编译的 `.lproj/*.strings`

先读 `docs/tasks/_common-phase3.md` 里的通用约束，再读本文件。

**前置依赖：T1 必须已完成。** 如果 `HSTracker/UIs/mul.lproj/MainMenu.xcstrings` 里
`1a9-Jp-R8O.title` 还没有 zh-Hans，说明 T1 没做完 —— 停下，在报告里说明，不要继续。

## 背景

仓库里有一整套 Xcode 15 之前格式的 per-language `.strings`：

```
HSTracker/{,UIs/,UIs/Preferences/,UIs/StatsManager/,UIs/DeckManager/,HSReplay/}<lang>.lproj/*.strings
```

覆盖 14 种语言（de / es / es-MX / fr / it / ja / ko / ko-KR / pl / pt-BR / ru / th-TH / zh-Hans / zh-Hant）
外加一个 `en.lproj`。

**它们全都没有被 `project.pbxproj` 引用**——已实测：

```
grep -c '\.strings' HSTracker.xcodeproj/project.pbxproj   # → 0
```

也就是说从不进 bundle、从不参与编译。里面有现成的中文翻译，从未上线过。
留着的唯一后果是：以后有人对着不生效的文件改翻译。

## 目标文件

- 只读：上述 `.lproj/*.strings`
- 可改：`Translations/macOS/Localizable.xcstrings`、`HSTracker/UIs/mul.lproj/MainMenu.xcstrings`
- 可删：上述整套 per-language `.lproj` 目录

## 要做的改动

### 第一步：先确认自己的判断，再删

跑一遍确认，把结果贴进报告：

1. `grep -c '\.strings' HSTracker.xcodeproj/project.pbxproj` 是否为 `0`
2. `grep -rn 'lproj' --include='*.swift' HSTracker/` —— 看有没有代码按路径去加载它们
3. 特别看 `HSTracker/Core/Extensions/String.swift` 的 `localizedString(_:comment:)`：
   它失败时会回退到 `Bundle.main.path(forResource: "Base", ofType: "lproj")`。
   确认这条回退路径**取的是 Base.lproj 而不是任何 per-language 目录**。

**任一条与预期不符 → 停下，写进报告，不要删任何东西。**

### 第二步：抢救 zh-Hans 里还有价值的译文（预期收获很小）

我已实测过：这批死文件里的中文，绝大部分在 T1 合并 gaenyong 之后已经不需要了
（`MainMenu.strings` 的 38 条被 gaenyong 的 41 条覆盖；5 个 `Localizable.strings` 里
只有 5 条能对上我们缺的 key，而且**全都是英文原样**，如 `"HSReplay" = "HSReplay";`，没有价值）。

所以这一步的正确预期是 **0 条或极少几条**。做法：

- 解析这 6 个 zh-Hans 文件的 key/value
- 找出「我们的 catalog 里仍缺 zh-Hans」且「这里有值」且「值不等于英文原文」的 key
- 有就补进对应 catalog，没有就明确写「0 条可补」

**冲突规则：T1 已经写进去的值优先，一条都不许覆盖。** 特别是
`MainMenu.xcstrings` 的 `1a9-Jp-R8O.title`：死文件里是「套牌」，T1 写的是「卡组」，
**必须保留「卡组」**（原因见 T1 任务书里那节坑）。

### 第三步：删除整套死目录

删掉全部 per-language `.lproj` 目录及其内容（14 种语言 + `en.lproj`），例如：

```
HSTracker/UIs/zh-Hans.lproj/
HSTracker/UIs/Preferences/de.lproj/
HSTracker/UIs/Preferences/en.lproj/
...
```

用 `git rm -r`（不要 `git commit`）或直接 `rm -r` 都行，保证 `git status` 能看见删除。

**必须保留 `Base.lproj` 和 `mul.lproj`：**
- `Base.lproj` 里有活的 `.xib`，是真在用的
- `mul.lproj` 里是 `.xcstrings`，就是本阶段的正主

### 第四步：报告一个你不要动的发现

`Base.lproj` 目录里也躺着 6 个 `Localizable.strings`（`HSTracker/Base.lproj/`、`HSTracker/UIs/Base.lproj/` 等）。
它们**同样没被 pbxproj 引用**，意味着 `String.localizedString` 那条 "Base.lproj 回退" 分支实际上永远取不到东西，
key 不存在时只会原样返回 key。

**这次不要删它们**（Base.lproj 是活目录，混着删风险大）。只把这个发现写进报告。

## 验收

1. `python3 docs/tasks/tools/check_xcstrings.py` 通过。仍缺数应为 **271**（若第二步补到了东西则更少，报告里说明补了哪几条）。
2. 构建通过 —— 这是本任务最关键的一条：**删了文件之后必须证明构建没坏**。
3. `git status` 里能看到被删的文件清单；报告里写明总共删了多少个文件、多少个目录。
4. 报告里写明第一步三项确认的实际输出。
