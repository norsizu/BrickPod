#!/bin/bash
# 构建 BrickPod.app —— WKWebView 壳 + 内嵌本地 HTTP 服务器（server.py 的 Swift 等价物）
# 产物: mac-app/BrickPod.app（assets + includes 打包进 bundle，约 17MB）
# 曲库不进 bundle：在 App 里导入/管理（⌘O / ⌘L），存在 ~/Library/Application Support/BrickPod
set -euo pipefail
cd "$(dirname "$0")"
PROJ=".."
OUT="BrickPod.app"

echo "==> 编译 Swift..."
mkdir -p build
# 通用二进制（Apple 芯片 + Intel），最低 macOS 12（WKWebView.underPageBackgroundColor 需要 12）。
# 不写 -target 的话 swiftc 按本机系统版本编译，别的 Mac 系统低一点就打不开
MIN_MACOS=12.0
SRCS=(Sources/main.swift Sources/AppDelegate.swift Sources/HTTPServer.swift Sources/LibraryBuilder.swift Sources/LibraryWindow.swift)
for ARCH in arm64 x86_64; do
  swiftc -O -target "$ARCH-apple-macos$MIN_MACOS" -o "build/BrickPod-$ARCH" "${SRCS[@]}"
done
lipo -create -output build/BrickPod build/BrickPod-arm64 build/BrickPod-x86_64

echo "==> 组装 .app..."
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/webroot"
cp build/BrickPod "$OUT/Contents/MacOS/BrickPod"
cp Info.plist "$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_MACOS" "$OUT/Contents/Info.plist"

echo "==> 生成图标..."
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
# 优先用组件实拍合成的 AppIcon-source.png（scripts/make-icon.swift 生成）；
# 没有再退回官方 favicon（qlmanage 渲 svg 经常只有左上角一个小音符，效果差）
if [ -f "AppIcon-source.png" ]; then
  cp AppIcon-source.png build/AppIcon-1024.png
elif qlmanage -t -s 1024 -o build "$PROJ/assets/favicon/favicon.svg" >/dev/null 2>&1 \
   && [ -f build/favicon.svg.png ]; then
  mv build/favicon.svg.png build/AppIcon-1024.png
else
  sips -z 1024 1024 "$PROJ/assets/favicon/favicon-180.png" --out build/AppIcon-1024.png >/dev/null
fi
for s in 16 32 128 256 512; do
  sips -z $s $s build/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns -o "$OUT/Contents/Resources/AppIcon.icns" "$ICONSET"

echo "==> 拷贝网页资源 (assets/includes...)..."
# 曲库不进 bundle：音乐放 ~/Library/Application Support/BrickPod/music，
# 由 App 内导入（菜单 ⌘O / 拖拽），重建 App 不丢歌
rsync -a --delete \
  --exclude '.DS_Store' \
  --exclude 'mac-app/' \
  --exclude 'server.py' \
  --exclude 'make-library.py' \
  --exclude '*.command' \
  --exclude 'README.md' \
  --exclude '*.orig' \
  --exclude 'Music/' \
  --exclude 'music/' \
  --exclude 'includes/ipod/data/us/en-US.json' \
  "$PROJ/" "$OUT/Contents/Resources/webroot/"

echo "==> ad-hoc 签名..."
codesign --force --sign - "$OUT"

echo "==> 打包 zip（拷到别的 Mac 用）..."
# ditto 保留签名和扩展属性；普通 zip 工具可能弄坏 .app
rm -f BrickPod.zip
ditto -c -k --keepParent "$OUT" BrickPod.zip

echo "==> 完成: $(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
echo "    运行: open \"$(pwd)/$OUT\""
