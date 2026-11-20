# 包 1　卡牌数据跟随国服客户端 build（W1）

> 总 spec：`../spec.md`。顺序第 1，不依赖其他包。

## 规则

`HSTracker/cards-version.txt` 应等于本机客户端在 `Power.log` 里 `GameState.DebugPrintGame() - BuildNumber=` 的值。hsdata 没有这个 tag 时保持原值，不要去追外服的最新 build。

## 现状

- 现在是 `255130`。全仓库只有这一个文件钉了这个版本；`docs/upstream-merges.md:107` 里的是历史记录，不要改。
- 本机国服客户端 11-17 的 `BuildNumber=255790`。hsdata 有这个 tag（"Update to patch 37.0.0.255790"，10-26），`CardDefs.xml`、`CardDefs.Bacon.xml`、`CardDefs.Lettuce.xml` 三个文件都在【核实】。

## 要做的事

把 `255130` 改成 `255790`，只改这一行。

## 设计要点

- pbxproj 里的「Download cards XML」阶段把 `cards-version.txt` 列为输入，所以**增量构建**就会重新下载，不需要 clean build。
- 下载结果缓存到 `downloaded-frameworks/cards/255790/`，之后由「Compile CardDefs」阶段编成 `CardDefs.bin`。
- 三个 XML 约 105 MB，从 github.com 下载要走代理。构建阶段会自己检测本地 7890 端口。

## 验收

- Debug 增量构建通过，`downloaded-frameworks/cards/255790/` 下三个文件齐全。
- `DatabaseTests` 通过。
- 实机放在第一轮（见 spec 第 4 节）：抽查几张卡的费用和文本，和国服客户端一致。

## 风险

低。万一下载失败，构建会直接报错，不会留下残缺文件（写入时先存为 `.partial`）。

## 记录

提交用 `chore:` 或 `fix:` 前缀；`docs/PLAN.md` 补提交记录和构建记录各一行。
