# Hearthline

Hearthline is a Hearthstone deck tracker for macOS. It is a personal fork of
[HSTracker](https://github.com/HearthSim/HSTracker) by HearthSim, tuned for
Standard and Wild play on Apple Silicon Macs, with a reworked deck tracker and a
complete Simplified Chinese translation.

> Hearthline is not made or supported by HearthSim or Blizzard. Please don't send
> HearthSim support requests about it; open an issue here instead.

[中文说明](#中文说明)

## What's different from HSTracker

- **Sectioned deck tracker.** Your deck, your hand and the cards you've played are
  shown as separate sections instead of one long list of 30 cards. Icons mark
  cards from outside your deck, cards in the graveyard, and cards that were
  burned or discarded.
- **Smoother overlay.** The trackers are drawn with SwiftUI, overlay refreshes are
  batched, and work that used to run on every frame has been moved off the main
  thread.
- **Your deck while you queue.** The tracker shows the deck you picked while you
  wait for a match.
- **Session recap.** When Hearthstone closes, a window sums up the games you just
  played.
- **Red Dragon combo helper** for Rogue: finds lethal lines with the cards you
  hold and walks you through them step by step.
- **Graveyard that shows what died.** The skull marks only minions that actually
  died, recorded as they were at the moment they died.
- **Simplified Chinese**: every string in the app is translated.
- Dock menu and menu bar fixes.

Hearthline keeps up with HSTracker for game patches (it is currently based on
HSTracker 3.6.13) but does not send changes back.

## Requirements

- A Mac with Apple Silicon (M1 or later)
- macOS 14 Sonoma or later
- Hearthstone (Battle.net version)

## Install

1. Download `Hearthline.zip` from the [latest release](../../releases/latest)
   and unzip it.
2. Move `Hearthline.app` to your Applications folder.
3. Open it once. macOS will say it can't check the app for malicious software,
   because Hearthline is not signed with a paid Apple Developer ID. Open
   **System Settings › Privacy & Security**, scroll down and click
   **Open Anyway**. You only need to do this once per version.
4. Start Hearthline before Hearthstone.

Hearthline has its own settings and does not touch an existing HSTracker
install, so both can sit in Applications. Run only one of them at a time.

Hearthline does not update itself. Watch this repository's releases (the
**Watch › Custom › Releases** button on GitHub) to hear about new versions.

## Build from source

You need Xcode 16 or later. Open `HSTracker.xcodeproj`, choose your own signing
team in **Signing & Capabilities** (a free Apple ID works), and build the
`HSTracker` scheme in the Release configuration. The build downloads the
HearthMirror framework and the Mono runtime from HearthSim's servers.

Contributor rules (in Chinese) are in [AGENTS.md](AGENTS.md); the project plan
is in [docs/PLAN.md](docs/PLAN.md).

## Credits and license

Hearthline is built on [HSTracker](https://github.com/HearthSim/HSTracker),
created by Benjamin Michotte and maintained by [HearthSim](https://hearthsim.info)
and its contributors. Both are released under the [MIT license](LICENSE); the
original copyright notices are kept there.

The HearthMirror, Bob's Buddy and HearthDb components come from HearthSim.
HSReplay.net uploads, if you turn them on, go to HearthSim's service.

Hearthstone and all Hearthstone assets are trademarks or copyright of Blizzard
Entertainment. This project is not affiliated with or endorsed by Blizzard.

## 中文说明

Hearthline 是一款 macOS 上的炉石传说记牌器，基于 HearthSim 的
[HSTracker](https://github.com/HearthSim/HSTracker) 个人修改版，非 HearthSim 或暴雪官方出品，有问题请在本仓库提 issue。

和原版的主要区别：

- 记牌器按牌库 / 手牌 / 已打出分段显示，带状态图标
- overlay 改用 SwiftUI 绘制，刷新更平稳
- 排队时显示所选卡组；关闭炉石后弹出本次对局小结
- 潜行者红龙斩杀提示
- 坟场骷髅只标真正死亡的随从
- 简体中文全部翻译完成

**安装**：需要 Apple 芯片 Mac、macOS 14 及以上。从 [最新发布](../../releases/latest) 下载解压，把
`Hearthline.app` 拖进「应用程序」。第一次打开时系统会拦截（本应用没有付费的 Apple 开发者签名），到
「系统设置 › 隐私与安全性」底部点「仍要打开」即可，每个版本只需一次。先开 Hearthline 再开炉石。
本应用不会自动更新，可在 GitHub 上 Watch 本仓库的 Releases 获取新版本通知。

开发文档（中文）：[AGENTS.md](AGENTS.md)、[docs/PLAN.md](docs/PLAN.md)。

本项目按 [MIT 许可证](LICENSE) 发布，保留 HearthSim 及原作者的版权声明。炉石传说及其素材版权归暴雪娱乐所有。
