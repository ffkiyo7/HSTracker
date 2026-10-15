#!/bin/bash
# 编红龙 mod：swift build -c release → 改 ModKit 引用、整理 rpath → ad hoc 签名 → .build/mod/RedDragon.dylib。
#   ./build.sh            只编
#   ./build.sh --install  编完拷进 ~/Library/Application Support/HSTracker/Mods/（重启 HSTracker 生效）
# 和 app 一样在受限环境里编（去掉代理变量、PATH 只留系统目录）。
set -euo pipefail
cd "$(dirname "$0")"

env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin swift build -c release

src=.build/release/libRedDragon.dylib
out=.build/mod/RedDragon.dylib
mkdir -p "$(dirname "$out")"
cp -f "$src" "$out"
chmod u+w "$out"

# mod 不得自带 ModKit：SwiftPM 编出的是 libModKit.dylib，HSTracker 里是 ModKit.framework（同一份源码、library evolution）
install_name_tool -id @rpath/RedDragon.dylib "$out"
install_name_tool -change @rpath/libModKit.dylib @rpath/ModKit.framework/Versions/A/ModKit "$out"
# 只留系统 Swift 运行库和 HSTracker 的 Frameworks：去掉 @loader_path（旁边放了 libModKit.dylib 就会加载第二份）和工具链目录
for rpath in $(otool -l "$out" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }'); do
    case "$rpath" in
        /usr/lib/swift) ;;
        *) install_name_tool -delete_rpath "$rpath" "$out" ;;
    esac
done
install_name_tool -add_rpath @executable_path/../Frameworks "$out"
codesign --force --sign - "$out"

if otool -L "$out" | grep -q libModKit; then
    echo "还引用着 libModKit.dylib，没改成功" >&2
    exit 1
fi
echo "编好：$out"

if [[ "${1:-}" == "--install" ]]; then
    mods="$HOME/Library/Application Support/HSTracker/Mods"
    mkdir -p "$mods"
    cp -f "$out" "$mods/RedDragon.dylib"
    echo "已装到：$mods/RedDragon.dylib（重启 HSTracker 生效）"
fi
