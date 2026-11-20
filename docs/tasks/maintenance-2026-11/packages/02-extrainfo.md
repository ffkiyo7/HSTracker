# 包 2　修复 extraInfo 丢失（W3f）

> 总 spec：`../spec.md`。顺序第 2，不依赖其他包。包 6（组装牌悬浮）依赖本包。

## 问题

卡牌附加信息 `extraInfo`（`ICardExtraInfo`）是用来在卡条上区分「同一张卡的不同状态」的，例如伊辛迪奥斯的爆发计数，以及之后的组装结果。它在两个地方被丢掉了【核实】：

1. **`DynamicEntity`（`Player.swift:13` 起）**：
   - `init` 收了 `extraInfo` 参数，但从来没赋给 `self.extraInfo`；
   - `==`（L45-53）和 `hash`（L35-43）都不比较 `extraInfo`；
   - 结果：`Player.swift` L427 / L610 / L653 / L787 和 `Fork/PlayerCardZones.swift` L256 / L293 / L367 这些分组之后，`card.extraInfo` 恒为 nil；
   - 这个写法从 `e86b4407`（2024-12-18，引入 `ICardExtraInfo` 的那次提交）起就是这样。
2. **`Entity.copy()`（`Entity.swift:265`）**：写成了 `e.info.extraInfo = e.info.extraInfo`，自己赋给自己，复制出来的实体没有 `extraInfo`。

伊辛迪奥斯的计数（`Game.swift:2851` 写入 `IncindiusCounter`）因此到不了卡条，**疑似**就是「伊辛迪奥斯计数不显示」的原因【推断】。

## 要做的事

1. `DynamicEntity.init` 把 `extraInfo` 存下来。
2. `DynamicEntity` 的 `==` 加上 `extraInfo` 的比较：两边都是 nil 算相等；类型相同并且值相等也算相等。
   - `ICardExtraInfo` 继承了 `Equatable`，不能直接拿两个 `any ICardExtraInfo` 比较。在协议扩展里加一个 `isEqual(to:)`，内部用 `as? Self` 再比较。
3. `DynamicEntity.hash`：只把 `extraInfo` 的**类型**（`ObjectIdentifier(type(of:))`，nil 时用一个固定值）放进去。相等的对象哈希必然相等，这样就够了。
4. `Entity.swift:265` 改成复制原实体的 `info.extraInfo`，用 `copy()` 深拷贝。
5. 顺带修 `Array.swift:29` 的排序，原来写成了 `$0` 和 `$0` 比较，改成和 `$1` 比较。

## 影响

带 `extraInfo` 的同名卡会按 `extraInfo` 分成不同的卡条，这正是 HDT 原本的行为。卡条的身份（`TrackerCardRowID`、`RowKey`）已经包含伊辛迪奥斯的字段，本包不用改。

## 验收

- **单元测试**（新建测试文件的话，记得在 pbxproj 登记）：
  - 同一个 cardId 的两个实体，一个带 `IncindiusCounter`、一个不带，经过 `Player` 的列表分组后得到两张卡，带计数的那张 `extraInfo` 还在；
  - `Entity.copy()` 之后 `extraInfo` 保留，并且是独立的副本；
  - `DynamicEntity` 的相等和哈希，覆盖两边都 nil、类型相同值相等、类型相同值不同三种情况；
  - 排序：同费用、同名的卡，排出来的顺序稳定。
- 全套测试通过。
- 实机放在第一轮：遇到伊辛迪奥斯时，看它的卡条有没有出现爆发计数的后缀。如果合入后仍不显示，把 spec 里的 O3 改回未决，从 `Game.swift:2836` 往下查。

## 风险

低到中。`PlayerCardZones`（fork 的分区面板）也走同一套分组，要确认分区之后的行数符合预期。

## 记录

提交用 `fix:` 前缀；`docs/PLAN.md` 补一行。
