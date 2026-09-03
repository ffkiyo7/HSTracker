# Phase 4 / T1 — Dock 菜单选牌有反馈 + Trackers 设置页重做

先读 `docs/tasks/_common.md`，再读 `docs/PLAN.md` Phase 4 一节。
三件事按顺序做，每件独立可验；做不完的写进报告，不要为了凑齐而赶。

## 1. Dock 菜单「卡组」点了没反应（PLAN 4.1）

`AppDelegate.swift:574` 的 `playDeck(_:)` 三个静默出口一个日志都没有。**先跑起来定位是哪条**，再修：

- `:508` 菜单项 `representedObject` 存的是活的 Realm `Deck`，经 `copy()` 进 Dock 子菜单后可能丢失。
  改存 `deck.deckId` 字符串。顺带消掉的隐患：套牌被删后活对象抛异常，而 `Game.set(activeDeckId:)` 取不到时**静默清空** `currentDeck`。
- PLAN 里的第二条嫌疑（`currentGameType == .gt_unknown` 挡住显示）**已被 Bug T4 的场景门取代**：主菜单本来就不显示记牌器，
  所以从 Dock 选牌**注定零视觉反馈**。修法不是放宽门，是加反馈：选中项 `.state = .on`，并弹 Toast（`HSTracker/UIs/Toast/Toast.swift`）。
- **不许改 Bug T4 那张表（对局中双方 / 排队只我方 / 主菜单都不显示）。**

## 2. 菜单栏按标题找项（PLAN 4.2）

`AppDelegate.swift:442` / `:517-518` / `:556-557` / `:636-638` 用 `item(withTitle:)` 按本地化标题找菜单项，
任一 catalog 重译一次就静默失效。改为按 tag 或 IBOutlet 定位。菜单栏 `.xib` 本身不动，tag 已有的直接用；没有的在报告里列出来，不要为此改 XIB。

## 3. Trackers 设置页重做（PLAN 4.3，只做这一页）

`TrackersPreferences.xib` 20 个 checkbox 平铺、无分组无说明，`TrackersPreferences.swift:109-176` 一条 `if/else if` 链。
用 SwiftUI `Form` + `Section` 重建这一页，通过 `NSHostingController` 接进 `PreferencePane` 协议。目的是验证接法可行，其余页面**不动**。

要求：

- 分组和说明文字自己定，但每个开关的 **Settings key、默认值、生效方式不变**。
- 「不在对局时隐藏全部记牌器」（`Settings.hideAllTrackersWhenNotInGame`）自 Bug T5 起已无任何读者，**这一页不再提供它**。
  `Settings` 里的声明和 key 保留（老 defaults 可读），本地化字符串一并清理，不留孤立 key。
- 新增的界面文案必须有 zh-Hans 条目，保持 Phase 3 的 945 / 945 不退步。
- 分页标题与图标定义在控制器前几行，图标资源在 `Assets.xcassets/settings-*.imageset`，不动。
- SPM 包 `sindresorhus/Preferences` 保留，其余 8 页还靠它。

## 对 `_common.md` 的例外

- 第 3 件允许改 `TrackersPreferences.swift`、删 `Base.lproj/TrackersPreferences.xib`、改 `mul.lproj/TrackersPreferences.xcstrings`。**其它 `.xib` / `.xcstrings` 仍不许动。**
- 新增 `.swift` 与删 `.xib` 都要手工同步 `project.pbxproj`（登记方法见 `AGENTS.md`「构建」）；只允许这两类 pbxproj 改动。

## 允许修改的文件

- `HSTracker/AppDelegate.swift`
- `HSTracker/UIs/Preferences/TrackersPreferences.swift`、对应 `.xib` / `.xcstrings`
- `HSTracker/Core/Settings.swift`（仅限第 3 件需要时）
- 新增 `.swift`

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`（命令见 `docs/archive/tasks/bug-t5-tracker-visibility-consistency.md`「验收」）；测试 50 / 50 全绿。
2. 报告里写清：第 1 件定位到的是哪条出口、依据；第 2 件每处改成了什么定位方式；第 3 件每个开关新旧位置对照表。
3. 🎮 第 1 件：先不开炉石，看 Toast + 菜单项打勾；再进一局确认用的就是那副牌；切中文重复一遍。
   🖥️ 第 3 件：设置窗口中英文各看一遍。**两项都不排在本次，与 Phase 1 / T5 一起验。**

## 执行结果（2026-09-03）

- Dock 子菜单复制的是带活 Realm `Deck` 的主菜单项；现已改为保存 `deckId` 字符串，并在选中时重新按 ID 取卡组。选中项会打勾、Toast 显示卡组名；重建菜单时也按当前 active deck 恢复勾选。若 ID 或 CoreManager 异常，直接 assert，不再静默清空当前卡组。
- 菜单栏定位改为运行时 tag：卡组、回放、最近回放、窗口、锁定窗口分别为 `decks`、`replays`、`lastReplays`、`window`、`lockWindows`。XIB 原本没有可用 tag，因此启动时按固定菜单结构设置它们，之后不再按本地化标题查找。
- 设置页新旧对照：外观保留主题、尺寸、不透明度和四个卡牌高亮/移除开关；记牌器行为保留自动定位、全屏、后台隐藏、观战、计时器、奥秘、稀有度、悬停卡、经验和趣味文本；起手换牌保留五个原有开关。`hideAllTrackersWhenNotInGame` 的声明和 key 保留，但控件及旧 XIB 文案已移除。
- 新 SwiftUI 状态对象在每次写入 Settings 后发布刷新，Picker、Toggle 和透明度数值会即时重绘；新文案已移入默认 `Localizable` 表并有 zh-Hans 译文。
- 受限环境 Debug build：`BUILD SUCCEEDED`；测试：50 / 50 通过。Dock 与中英文设置页仍按任务书留待人工视觉验收。
