# Build T1：固定 BobsBuddy 与 HearthDb 制品

## 背景

`libs.hearthsim.net/hdt/BobsBuddy.zip` 与 `HearthDb.zip` 都只有会变化的 `latest` 内容，
没有可按版本重新下载的 URL。现有 build phase 每次联网下载：BobsBuddy 会因服务器发版与
`BobsBuddy-version.txt` 不一致而让本地构建突然失败；HearthDb 则没有版本声明或校验，
会在构建时无记录地换掉构筑功能依赖的程序集。

当前 phase 还把 `BobsBuddy-version.txt` 作为 input、解压后保留归档时间的 DLL 作为 output。
归档内的 `HearthDb.dll` 比 input 旧，Xcode 因而每次都判定 phase 过期。

## 允许修改

- `HSTracker.xcodeproj/project.pbxproj`
- `HSTracker/BobsBuddy-version.txt`
- 新增 `HSTracker/HearthDb-version.txt`
- `HSTracker/Mono/MonoHelper.swift`（只同步过时注释）
- 新增 `Vendor/Managed/BobsBuddy.zip` 与 `Vendor/Managed/HearthDb.zip`
- 新增 `scripts/update-managed-deps.sh`
- 删除 `downloaded-frameworks/BobsBuddy.zip` 与 `downloaded-frameworks/HearthDb.zip`
- `AGENTS.md`
- `docs/PROGRESS.md`
- 本任务书

不要修改上述范围外的文件，不要 `git add` 或 commit，不要动 `Config.xcconfig`。

## 要求

1. 两份当前已验证的官方 zip 固定进仓库；普通构建不得访问这两个 `latest` URL。
2. 制品路径不要包含版本号。BobsBuddy 版本只由现有 `BobsBuddy-version.txt` 声明，
   禁止在路径、脚本常量或第二份清单中再维护一遍版本。
3. HearthDb 新增一个可读的版本声明，并从程序集读取版本核对，避免将错误 zip 当成正确依赖。
4. 两份 zip 都先解压到临时 staging；确认规定文件齐全、程序集版本匹配后，再 `cp` 到
   `downloaded-frameworks/managed/`。**禁止 unzip 直接写 outputPaths。**
5. `cp` 必须发生在校验之后，使输出文件的修改时间晚于所有 inputs；这是修复当前 phase
   永远过期的硬约束，不能依赖 zip 内保存的归档时间。
6. staging 必须建在 `DERIVED_FILE_DIR`，并在成功和失败时都清理；硬杀残留应能随 clean 消失。
   校验失败不得覆盖旧的已验证 DLL。
7. BobsBuddy 必须同时安装 `BobsBuddy.dll` 与 `BobsBuddy.Common.dll`；HearthDb 必须同时安装
   `HearthDb.dll` 与 `HearthDb.xml`。四项都要同时记为安装阶段的 outputs、`Embed Mono` 的
   inputs 与 bundle outputs，不能让包内缺文件时仍被判为最新。
8. 两份版本文件都登记进 Xcode 导航器，但都不复制进 app；删除 BobsBuddy 原有的无读者资源项。
9. 新增显式升级脚本：下载两个 latest、校验文件、读取并展示实际版本；只有传 `--apply` 和刚确认的
   两个版本才替换制品与版本文件，latest 在两次调用间变化必须失败。HearthDb 提取歧义也必须失败。
10. 不新增 SHA-256 清单。制品已由 Git 保证内容完整，程序集版本校验负责发现放错包。
11. 错误必须明确说明缺少哪个文件或期望/实际版本；构建阶段不得吞错、降为 warning 或自动改版本。
12. 同步更新现有构建文档，删掉“构建时下载 latest / pin 会自动过期”的旧事实。

## 验收

先删除本任务生成的四个 `downloaded-frameworks/managed/` 产物，运行受限环境 Debug build：

```sh
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' build
```

必须确认：

- 日志中没有访问两个 `libs.hearthsim.net/hdt/*.zip` URL，且最终 `BUILD SUCCEEDED`；
- 四个安装产物均存在，并且修改时间晚于版本文件与 vendored zip；
- 不改任何 input 再跑一次增量 build，安装 phase 被 Xcode 判定为最新而跳过；
- 包内 `Contents/Resources/Managed/` 的四个文件都存在；
- BobsBuddy 与 HearthDb 的程序集版本分别匹配两份版本文件。
- 升级脚本默认只打印 latest；带两个确认版本的 `--apply` 才改 zip 和版本文件。

最后检查完整 diff，确认没有保留旧下载逻辑、重复版本声明或未登记的产物。
