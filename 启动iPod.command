#!/bin/bash
# 双击启动离线 iPod Widget（独立小窗口，无地址栏/标签页）
cd "$(dirname "$0")"
PORT=8765
URL="http://localhost:$PORT/"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 服务没起就后台启动
if ! lsof -i :$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  python3 server.py $PORT >/dev/null 2>&1 &
fi
sleep 1

# Chrome app 模式：独立实例 + 无浏览器界面的小窗口，像桌面 Widget
if [ -x "$CHROME" ]; then
  "$CHROME" --user-data-dir="$HOME/.ipod-widget-profile" \
    --no-first-run --no-default-browser-check --lang=en-US \
    --disable-features=Translate \
    --app="$URL" --window-size=600,1000 >/dev/null 2>&1 &
else
  open "$URL"
fi
