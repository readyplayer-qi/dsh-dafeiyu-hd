# 大肥鱼 · 安装语音挂钩（Windows / PowerShell）
# 用法：右键本文件 → 使用 PowerShell 运行
# 插件更新后需要重跑。
$ErrorActionPreference = "Stop"
$D = Split-Path -Parent $MyInvocation.MyCommand.Path
$P = Join-Path $env:USERPROFILE ".dsh\profiles\desktop\node_modules\dsh-pet"
$H = Join-Path $P "runtime\electron-helper"
$C = Join-Path $P "lib\client.js"
$stamp = Get-Date -Format "HHmm"

if (-not (Test-Path $H)) {
  Write-Host "找不到插件运行时目录：$H" -ForegroundColor Red
  Write-Host "先启动一次 DSH，或确认 dsh-pet 插件已安装。"
  exit 1
}

$src = Join-Path $D "pet-voice.js"
if (-not (Test-Path $src)) { $src = Join-Path $env:USERPROFILE ".dsh\pet-tts\pet-voice.js" }
if (-not (Test-Path $src)) { Write-Host "找不到 pet-voice.js" -ForegroundColor Red; exit 1 }

function Backup($p) {
  $b = "$p.bak-$stamp"
  if ((Test-Path $p) -and -not (Test-Path $b)) { Copy-Item $p $b }
}
function Read-Utf8($p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Write-Utf8($p, $s) { [System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding($false))) }

# 1) pet-voice.js
$dst = Join-Path $H "pet-voice.js"
if (-not (Test-Path $dst) -or ((Get-FileHash $src).Hash -ne (Get-FileHash $dst).Hash)) {
  Backup $dst; Copy-Item $src $dst -Force
  Write-Host "pet-voice.js 已安装/更新"
} else { Write-Host "pet-voice.js 已是最新" }

# 2) index.html 挂载
$idx = Join-Path $H "index.html"
if (Test-Path $idx) {
  $s = Read-Utf8 $idx
  if ($s -notmatch "pet-voice\.js") {
    $old = '    <script src="./renderer.js"></script>'
    if ($s.Contains($old)) {
      Backup $idx
      Write-Utf8 $idx ($s.Replace($old, $old + "`n    <script src=`"./pet-voice.js`"></script>"))
      Write-Host "index.html 已挂载 pet-voice.js"
    } else { Write-Host "警告：index.html 里没找到 renderer.js" -ForegroundColor Yellow }
  } else { Write-Host "index.html 已挂载过" }
}

# 3) 设置页提示
if (Test-Path $C) {
  $s = Read-Utf8 $C
  if ($s -notmatch "【语音】") {
    $m = [regex]::Match($s, 'petCardHint:\s*"([^"]*)"')
    if ($m.Success) {
      $repl = 'petCardHint: "' + $m.Groups[1].Value + '\n\n【语音】本包默认无声：先运行 tools/tts_server.py，或自备 18888 语音服务。"'
      $new = $s.Remove($m.Index, $m.Length).Insert($m.Index, $repl)
      Backup $C; Write-Utf8 $C $new
      Write-Host "设置页提示已加入"
    } else { Write-Host "警告：没找到 petCardHint" -ForegroundColor Yellow }
  } else { Write-Host "设置页提示已存在" }
}

Write-Host ""
Write-Host "完成。先启动语音服务（另开一个窗口）：" -ForegroundColor Green
Write-Host "  python tools\tts_server.py"
Write-Host "然后重启 DSH。"
