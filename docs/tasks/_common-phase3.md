# 通用约束（所有 Phase 3 任务共用）

项目：HSTracker，macOS 上的炉石传说记牌器，Swift + AppKit，仓库根目录 `/Users/wadorudi/Desktop/HSTracker`。
个人自用 fork，不需要考虑回合并 upstream。

本阶段目标：**把简体中文补全**。全项目 846 个可翻译 key，当前 410 个没有 zh-Hans（48%）。
完整计划见 `docs/PLAN.md` 的「Phase 3」小节，动手前先读它。

## 硬性规则

1. **只修改本任务书明确指定的文件。** 发现别处也有问题，写进最后的报告，不要顺手改。
2. **不要 commit，不要 `git add`。** 改完留在工作区，由人 review 后统一提交。
3. **不要动 `Config.xcconfig`**（已设为本地签名并 `skip-worktree`），**不要动 `HSTracker.xcodeproj/project.pbxproj`**，
   除非任务书明确要求。
4. **不要动任何 `.xib`。** Phase 4 要用 SwiftUI 重做设置页，现在碰 XIB 是纯风险。
5. **只动 `zh-Hans`。** 其它 14 种语言的译文一个字都不许改。
6. **不许增删 key。** String Catalog 的 key 由 Xcode 从代码/XIB 抽取，手工加 key 只会在下次抽取时被清掉。
   唯一例外是 T3，它明确要求补两个 key。
7. 注释按仓库既有密度来（这个仓库注释偏少）；只在改动原因不明显时写一两行说明**为什么**。

## `.xcstrings` 的写法（重要）

`.xcstrings` 是 JSON。**用脚本改，不要手写**，并且必须保持 Xcode 的规范格式，否则 diff 会变成整文件重写、没法 review。

规范格式 = 保序 + 2 空格缩进 + `" : "` 分隔 + 不转义非 ASCII + **无尾换行**：

```python
import collections, json

with open(path, encoding='utf-8') as fh:
    data = json.load(fh, object_pairs_hook=collections.OrderedDict)

# ... 修改 data ...

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(json.dumps(data, indent=2, ensure_ascii=False, separators=(',', ' : ')))
```

已实测：23 个 `.xcstrings` 里 22 个用这个配方能字节级还原。唯一例外是
`Translations/macOS/Localizable.xcstrings` 里有个空 key `""` 对应空对象 `{\n\n    }`，
Python 会写成 `{}` —— 校验器已对该文件豁免 E2，不用管。

补一条 zh-Hans 的结构长这样（`state` 必须是 `"translated"`）：

```json
"zh-Hans" : {
  "stringUnit" : {
    "state" : "translated",
    "value" : "显示经验进度"
  }
}
```

`localizations` 里的语言按字母序排列，插入时保持这个顺序（`zh-Hans` 排在 `th-TH` 之后、`zh-Hant` 之前）。

## 校验器

仓库里有 `docs/tasks/tools/check_xcstrings.py`。**每个任务收尾前必须跑它，且必须通过：**

```
cd /Users/wadorudi/Desktop/HSTracker
python3 docs/tasks/tools/check_xcstrings.py
```

它会拦住：JSON 坏了、格式跑偏、增删 key、动了别的语言、覆盖了已有 zh-Hans 译文、
占位符（`%@` / `%d` / `%1$@`）与英文原文对不上、`state` 不是 `translated`。
把它的完整输出贴进报告。

需要**修改**既有 zh-Hans 译文的任务（只有 T6 的一小段）加 `--allow-zh-edit`；
T3 之后的任务要加 `--allow-new-key Archive --allow-new-key Unarchive` 放行 T3 有意新增的两个 key。
每个任务书的「验收」小节写明了该跑哪条命令，照那个来。

## 翻译规范

**术语表（炉石国服官方译名，必须照用）：**

| English | 简体中文 | | English | 简体中文 |
|---|---|---|---|---|
| Battlegrounds | 酒馆战棋 | | Mercenaries | 佣兵战纪 |
| Arena | 竞技场 | | Tavern Brawl | 乱斗模式 |
| Standard | 标准模式 | | Wild | 狂野模式 |
| Twist | 幻变模式 | | Classic | 经典模式 |
| Duels | 对决模式 | | Practice | 练习模式 |
| Friendly | 好友对战 | | Ranked | 排名模式 |
| Mulligan | 起手留牌 | | Hero Power | 英雄技能 |
| Minion | 随从 | | Spell | 法术 |
| Weapon | 武器 | | Secret | 奥秘 |
| Quest | 任务 | | Sideboard | 备牌 |
| Trinket | 饰品 | | Hero | 英雄 |
| Class | 职业 | | Card | 卡牌 |
| Deck | 卡组 | | Hand | 手牌 |
| Graveyard | 坟场 | | Fatigue | 疲劳 |
| Turn | 回合 | | The Coin | 幸运币 |
| Mana | 法力值 | | Attack | 攻击力 |
| Health | 生命值 | | Armor | 护甲值 |
| Rank / Ladder | 段位 / 天梯 | | Legend | 传说 |
| Replay | 回放 | | Winrate | 胜率 |
| Murloc / Beast | 鱼人 / 野兽 | | Demon / Dragon | 恶魔 / 龙 |
| Elemental / Mech | 元素 / 机械 | | Naga / Pirate | 纳迦 / 海盗 |
| Quilboar / Undead | 野猪人 / 亡灵 | | Tier | 等级 |

**HSTracker 自己的说法：**

| English | 简体中文 |
|---|---|
| Tracker | 记牌器 |
| Overlay | 悬浮窗 |
| Card counter | 卡牌计数器 |
| Draw chance | 抽到概率 |
| Deck code | 卡组代码 |
| Import / Export | 导入 / 导出 |
| Preferences / Settings | 偏好设置 |

**保持英文原样的品牌名：** HSTracker、HSReplay、Hearthstone（可译「炉石传说」，但产品名场合保留英文）、
Bob's Buddy、Twitch、Firestone、MMR、Blizzard、Battle.net、Discord。

**其它规则：**

1. **格式化占位符原样保留。** `%@` `%d` `%1$@` `%%` 一个都不能少、不能改类型。
   位置可以按中文语序调整，但那时必须整条都用位置化写法（`%1$@` / `%2$@`），不能混用。
2. **`&` 后面的助记键、`\n`、前后空格照抄。** 菜单项里的 `…`（U+2026）不要换成三个点。
3. 中英文之间**不加空格**（Apple 中文本地化风格）。
4. 句末标点用中文全角（`。` `，` `：`），但**按钮和菜单项标题不加句号**。
5. 界面标签求短。checkbox 的 title 尽量控制在 12 个汉字内，说明性长句（tooltip、footer）可以长。
6. 拿不准的、或英文本身有歧义的，**照直译一版，然后在报告里单列出来**说明你的疑虑 —— 不要自己发挥。
7. 译之前先看该 catalog 里**已有的 zh-Hans 译文**，跟它们保持用词一致；同一个英文词在同一个 catalog 里
   必须译成同一个中文词。

## 验收构建

改了 `.swift` 的任务必须跑构建；只改 `.xcstrings` 的任务也建议跑一次（Xcode 会编译 String Catalog，
JSON 坏了会直接构建失败）：

```
cd /Users/wadorudi/Desktop/HSTracker
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' build
```

日志很长，只需确认最后是 `BUILD SUCCEEDED`。失败就读错误自行修复后重跑，直到通过。
SwiftLint **故意没装**，build phase 里未安装只告警、不阻塞 —— 不要去装它。

## 最后请输出

- 改了哪些文件、每个文件补了多少条
- `check_xcstrings.py` 的完整输出
- 构建结果
- 你拿不准的译法（逐条列出：key、英文、你给的中文、疑虑是什么）
- 任何你认为有风险、或发现但按规则没有动的问题

## 工作区已有的改动（不是你造成的，不要还原、不要"顺手修复"）

1. `Config.xcconfig` —— 已改为本地签名，并已 `git update-index --skip-worktree`，`git status` 里看不到它。
2. `HSTracker.xcodeproj/project.pbxproj` —— "Embed Mono" build phase 的 `NET_VERSION` 已由 `net7.0` 改为 `net8.0`，
   这是修 upstream 的真实 bug（commit `1ff31cb1`）。**不要动这个文件。**
3. `.refs/` —— 我预先下载的参考资料（gaenyong fork 的 16 个 `.xcstrings`），已加进 `.git/info/exclude`，
   `git status` 里看不到。**只读，不要修改、不要删除、不要把它当成产物。**
