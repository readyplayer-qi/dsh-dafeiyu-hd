#!/bin/bash
# 大肥鱼 · 安装语音挂钩（桌面模式）
# 作用：把 pet-voice.js 装进 electron-helper，并在「桌宠配置」设置页加一行语音提示。
# 用法：bash tools/patch-pet-voice.sh
# 插件更新后需要重跑。
set -euo pipefail

D="$(cd "$(dirname "$0")" && pwd)"
P="$HOME/.dsh/profiles/desktop/node_modules/dsh-pet"
H="$P/runtime/electron-helper"
C="$P/lib/client.js"
STAMP="$(date +%H%M)"

if [ ! -d "$H" ]; then
  echo "找不到插件运行时目录：$H" >&2
  echo "先启动一次 DSH，或确认 dsh-pet 插件已安装。" >&2
  exit 1
fi

SRC="$D/pet-voice.js"
[ -f "$SRC" ] || SRC="$HOME/.dsh/pet-tts/pet-voice.js"
if [ ! -f "$SRC" ]; then
  echo "找不到 pet-voice.js（tools/ 和 ~/.dsh/pet-tts/ 都没有）。" >&2
  exit 1
fi

backup() {
  [ -f "$1" ] && [ ! -f "$1.bak-$STAMP" ] && cp "$1" "$1.bak-$STAMP" || true
}

# 1) pet-voice.js
if [ ! -f "$H/pet-voice.js" ] || ! cmp -s "$SRC" "$H/pet-voice.js"; then
  backup "$H/pet-voice.js"
  cp "$SRC" "$H/pet-voice.js"
  echo "pet-voice.js 已安装/更新"
else
  echo "pet-voice.js 已是最新"
fi

# 2) index.html 挂载
if ! grep -q "pet-voice.js" "$H/index.html" 2>/dev/null; then
  backup "$H/index.html"
  python3 - "$H/index.html" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '    <script src="./renderer.js"></script>'
new = old + '\n    <script src="./pet-voice.js"></script>'
if old not in s:
    print("警告：index.html 里没找到 renderer.js，未挂载 pet-voice.js")
else:
    open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
    print("index.html 已挂载 pet-voice.js")
PY
else
  echo "index.html 已挂载过"
fi

# 3) 浏览器模式补丁（本包不提供 patch.js；有就追加）
if [ -f "$HOME/.dsh/pet-tts/patch.js" ] && [ -f "$C" ]; then
  if ! grep -q "__petTTS" "$C"; then
    backup "$C"
    cat "$HOME/.dsh/pet-tts/patch.js" >> "$C"
    echo "client.js 浏览器补丁已追加"
  else
    echo "client.js 浏览器补丁已存在"
  fi
else
  echo "跳过浏览器模式（没有 patch.js；桌面模式不受影响）"
fi

# 4) 设置页提示
if [ -f "$C" ]; then
  if grep -q "【语音】" "$C"; then
    echo "设置页提示已存在"
  else
    backup "$C"
    python3 - "$C" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
new, n = re.subn(
    r'petCardHint:\s*"([^"]*)"',
    lambda m: 'petCardHint: "' + m.group(1) +
              '\\n\\n【语音】本包默认无声：先运行 tools/tts_server.py，或自备 18888 语音服务。"',
    s, count=1)
if n == 0:
    print("警告：没找到 petCardHint，设置页提示未加")
else:
    open(p, "w", encoding="utf-8").write(new)
    print("设置页提示已加入「桌宠配置」卡片")
PY
  fi
fi

echo ""
echo "完成。启动语音服务（另开一个终端）："
echo "  python3 tools/tts_server.py"
echo "然后重启 DSH。"
