# 包 6　组装牌悬浮（W3e，按 D3）

> 总 spec：`../spec.md`。顺序第 6，依赖包 2（`extraInfo` 修好后才能按组装结果分行）。
> 参考 HDT `525e118`。**不移植** `980f635`（卡条名后加「(A + B)」），它和 D3 冲突。

## 规则（D3）

- **悬浮页面**：记牌器里组装牌的悬浮页面，**始终显示玩家组装后的卡牌**，也就是母牌的卡图，描述框里换成两半拼起来的文本。
- **卡条**：仍用母牌的名字和费用，不加后缀。
- **默认做法**（D3 补充，Claude 决定）：
  1. 我方、对手的记牌器和分区面板都按同一规则处理；
  2. 同一张母牌组装出不同结果时，分成多行；
  3. 某一半的文本取不到时，悬浮退回显示母牌原图；
  4. 文本底板用代码绘制，不新增图片资源。

## 现状【核实】

- 本地已经有组装的效果卡判断：`RelatedCardsManager.swift:70-112` 的 `getEffectCardId`、`getAssembleChoice`、`getAssembleChoiceEffectCardId`。用于选择阶段的关联卡。
- 本地**没有** `AssembledHalves`。`EntityInfo.extraInfo`（`EntityInfo.swift:51`）是普通存储属性，只有伊辛迪奥斯会写入。
- 卡条悬浮：`TrackerCardHoverHandler.swift:172` 的 `request(for:)` 只传 `cardId`；关联卡网格由 `setRelatedCardsTooltip`（L107）用 `card.id` 查询。
- `CardTooltipRequest.text`（`CardImageTooltip.swift:37`）是盖在卡图**顶部**的标题文字，由 `layOutCaption`（约 L516）绘制，不是描述框。
- 卡条身份：
  - `TrackerCardRowID` 和 `CardTileListView.RowKey` 只带伊辛迪奥斯的字段；
  - `TrackerCardRow ==` 和 `AnimatedCardList.swift:106` 比较的是 `cardNameSuffix`。
- 名字后缀拼接在 `CardTileView.swift:301`、`CardBar.swift:743`、`CardRowView.swift:381` 三处。
- 本地没有带组装的 Power.log 样本，没法做回放测试。
- **组装产物都是随从**：`cards/255130` 里正文带 Assemble 的可收藏卡共 13 张（7 随从、6 法术），文本全都是「组装一个随从」。
  - 其中 `BE_004` 组装后再变成被动英雄技能，不在卡条里；
  - 能当「半张」的卡（带 `CRAFTABLE_OUTPUT_POWER`）里虽然有 16 把武器、4 张法术、2 张英雄，但它们只提供文本，组装出来的仍是随从。
- HDT 只给随从显示组装文本，原因是排版：底板按 512×776 的随从卡图描述框定位（`525e118` 的 `Card.cs` 注释）。所以在 37.0，「只限随从」不会让任何组装牌少显示，和 D3 不冲突。

## 要做的事

### 1. 新增 `AssembledHalves`

新建 `HSTracker/Hearthstone/AssembledHalves.swift`，pbxproj 登记 4 处。对照 HDT `AssembledHalves.cs`：

- 实现 `ICardExtraInfo`：`cardNameSuffix` 返回 nil（D3：卡条不加后缀），实现 `NSCopying`、`Equatable`。按两半的 dbfId 比较。
- `fromEntity(_:)`：读 `CRAFTABLE_FIRST_HALF_DBID` / `CRAFTABLE_SECOND_HALF_DBID`。任一缺失，或者等于 1（选择阶段的占位值），就返回 nil。
- `effectCardId`：效果那一半的 cardId。
- `assembledText`：两半各自的卡牌文本按 `&` 切开，取对应的那一段，压缩空白后拼起来。规则照搬 HDT 的 `GetText`。任一半取不到时返回 nil。

### 2. `extraInfo` 从 tag 现取

`EntityInfo.extraInfo` 改成：存储值不为 nil 时返回存储值（伊辛迪奥斯），否则返回 `AssembledHalves.fromEntity(_entity)`。

- 每次都从实体当前的 tag 计算，组装完成后立刻就是最新结果，这就是 D3 说的「始终」。
- 写入仍写到存储值。

### 3. 卡条

- 名字和费用不变。母牌的费用直接取数据库，不读实体的 COST tag，和现在一样。
- 因为 `cardNameSuffix` 为 nil，三处后缀拼接不需要改。

### 4. 卡条身份和排序

- `TrackerCardRowID`、`RowKey` 加上两半的 dbfId，用可选值。
- `TrackerCardRow ==` 和 `AnimatedCardList.swift:106` 从比较后缀改成用包 2 的 `isEqual(to:)` 比较 `extraInfo`。否则两条只有组装结果不同的卡条会被当成同一条，悬浮内容不刷新。
- `Array.swift` 的 `.cost` 排序：包 2 已经把比较改成 `$0` 对 `$1`。本包在后缀相同时再按两半的 dbfId 排序，保证顺序稳定。

### 5. 悬浮

- `CardTooltipRequest` 新增 `assembledText: String?`。不要复用 `text`，那是顶部标题。
- `TrackerRowCardPreview.request(for:)`：卡的 `extraInfo` 是 `AssembledHalves` 并且类型是随从时，填入 `assembledText`。
  - 只限随从，和 HDT 一致，理由见「现状」。
  - 以后如果出现组装成非随从的卡，按 D3 补充第 3 条退回母牌原图，并在 PLAN 记一条。
- `CardTooltipPanel`：有 `assembledText` 时，在主卡图的描述框位置用代码画一块不透明底板，再把文本写上去。保留种族条。字号可以自动缩小，但不改变面板尺寸。
- `assembledText` 为 nil 时，按现在的方式显示母牌原图。

### 6. 关联卡网格

`setRelatedCardsTooltip` 查询关联卡时，如果卡是组装牌，改用 `effectCardId`。这对应 HDT `Card.cs` 里「关联卡来自效果那一半」的逻辑。

## 验收

- **单元测试**：
  - 移植 HDT 的 `AssembledEffectCardIdTests`，后缀那条改成断言为 nil；
  - `fromEntity` 覆盖：两半齐全、缺一半、值为 1 三种；
  - `assembledText` 覆盖：`&` 切分、空白压缩、某一半取不到时返回 nil；
  - 分组：同一张母牌组装成两种结果，得到两行；没组装的母牌单独一行；
  - `TrackerCardRow` 相等性：只有组装结果不同时，判定为不相等。
- 全套测试通过。
- **实机**放在第三轮：遇到组装牌时：
  - 卡条显示母牌的名字和费用；
  - 悬浮显示组装后的文本；
  - 关联卡网格对应效果那一半。
- 本包的实机条件不受控制。合入时只要求单元测试，实机结果补记到 PLAN 的测试记录里。

## 风险

- 中。悬浮绘制要对齐卡图上的描述框位置，不同语言、不同卡框可能有偏差。先只对随从卡框调好。
- `extraInfo` 改成计算属性后，`hash` / `==` 和分组会更频繁地调用它，要注意开销。只读两个 tag，问题不大。

## 记录

拆成 `feat:` 提交两到三个（数据和分组、悬浮绘制、关联卡）；`docs/PLAN.md` 逐行记。
