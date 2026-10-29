# 大肥鱼右键菜单补丁（Windows / PowerShell）
# 用法：右键本文件 → 使用 PowerShell 运行
# 作用：隐藏大肥鱼（Ctrl+Alt+P 叫回）· 退出桌宠（真退出）· 无菜单栏图标
# 可重复执行，只补缺失项；锚点对不上会明确提示，不会假装成功。
$ErrorActionPreference = "Stop"
$H = Join-Path $env:USERPROFILE ".dsh\profiles\desktop\node_modules\dsh-pet\runtime\electron-helper"
if (-not (Test-Path $H)) { Write-Host "找不到插件目录：$H" -ForegroundColor Red; exit 1 }

$problems = @()

function Read-Utf8($p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Write-Utf8($p, $s) { [System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding($false))) }
function Backup($p) {
  $b = $p + ".bak-" + (Get-Date -Format "HHmm")
  if (-not (Test-Path $b)) { Copy-Item $p $b }
}

# ---------------- sprite.js ----------------
$p = Join-Path $H "sprite.js"
$s = Read-Utf8 $p
if (-not $s.Contains("hide-pet")) {
  $old = "    const tree = tools.concat(S.buildMenuTree(this.animations));"
  if (-not $s.Contains($old)) {
    $problems += "sprite.js：找不到菜单构建那一行"
  } else {
    Backup $p
    $new = @"
    const tree = tools.concat(S.buildMenuTree(this.animations), [
      // 隐藏：只藏形象，语音继续；Ctrl+Alt+P 叫回（不建菜单栏图标）
      { label: '隐藏大肥鱼', action: 'hide-pet' },
      // 退出：真退出（配置 display=none），不会被守护重启回弹
      { label: '退出桌宠', action: 'quit-pet' },
    ]);
"@
    $s = $s.Replace($old, $new)
    Write-Utf8 $p $s
    Write-Host "sprite.js 菜单已打补丁"
  }
}

$s = Read-Utf8 $p
$anchor = "    if (!leaf.anim) return;"
if (-not $s.Contains($anchor)) {
  $problems += "sprite.js：找不到 if (!leaf.anim) return; 锚点"
} else {
  if (-not $s.Contains("leaf.action === 'hide-pet'")) {
    Backup $p
    $insert = @"
    if (leaf.action === 'hide-pet') {
      if (window.petBridge && window.petBridge.hidePet) window.petBridge.hidePet();
      return;
    }
"@
    $s = $s.Replace($anchor, $insert + $anchor)
    Write-Utf8 $p $s
    Write-Host "sprite.js 隐藏已打补丁"
  }
  if (-not $s.Contains("leaf.action === 'quit-pet'")) {
    Backup $p
    $insert = @"
    if (leaf.action === 'quit-pet') {
      if (window.petBridge && window.petBridge.quitPet) window.petBridge.quitPet();
      return;
    }
"@
    $s = $s.Replace($anchor, $insert + $anchor)
    Write-Utf8 $p $s
    Write-Host "sprite.js 退出已打补丁"
  }
}

# ---------------- preload.js ----------------
$p = Join-Path $H "preload.js"
$s = Read-Utf8 $p
$anchor = "  openDshSite(url) {"
if (-not $s.Contains($anchor)) {
  $problems += "preload.js：找不到 openDshSite 锚点"
} else {
  if (-not $s.Contains("hidePet")) {
    Backup $p
    $s = $s.Replace($anchor, @"
  // 隐藏 / 退出（都只动 Helper，不动 DSH）
  hidePet() { ipcRenderer.send('pet:hide'); },
  quitPet() { ipcRenderer.send('pet:quit'); },
  openDshSite(url) {
"@)
    Write-Utf8 $p $s
    Write-Host "preload.js 隐藏/退出桥已打补丁"
  }
  if (-not $s.Contains("onPetMuted")) {
    Backup $p
    $s = $s.Replace($anchor, @"
  // 主进程通知静音/恢复（退出时用）
  onPetMuted(cb) { ipcRenderer.on('pet-muted', (_e, v) => cb(!!v)); },
  openDshSite(url) {
"@)
    Write-Utf8 $p $s
    Write-Host "preload.js 静音桥已打补丁"
  }
}

# ---------------- main.js ----------------
$p = Join-Path $H "main.js"
$s = Read-Utf8 $p
if ($s.Contains("HIDDEN_FLAG")) {
  Write-Host "main.js 之前已打补丁，跳过"
} else {
  Backup $p
  $oldImp = "const { app, BrowserWindow, ipcMain, screen, shell, protocol } = electronApi;"
  if (-not $s.Contains($oldImp)) {
    $problems += "main.js：没认出 electronApi 解构行"
  } else {
    $s = $s.Replace($oldImp, "const { app, BrowserWindow, ipcMain, screen, shell, protocol, globalShortcut } = electronApi;")
  }

  $block = @"
/* ---------- 隐藏标记（跨 Helper 重启记住） ---------- */
const HIDDEN_FLAG = path.join(app.getPath('userData'), 'pet-hidden.flag');
function isHiddenFlag() { try { return require('node:fs').existsSync(HIDDEN_FLAG); } catch { return false; } }
function setHiddenFlag(v) {
  try {
    if (v) require('node:fs').writeFileSync(HIDDEN_FLAG, String(Date.now()));
    else require('node:fs').rmSync(HIDDEN_FLAG, { force: true });
  } catch {}
}
/* ---------- 叫回：只注册快捷键，不建菜单栏图标 ---------- */
function petWindows() { return Array.from(windows.values()).filter((w) => !w.isDestroyed()); }
function petVisible() { return petWindows().some((w) => w.isVisible()); }
function togglePet() {
  const wins = petWindows();
  if (!wins.length) return;
  if (petVisible()) { wins.forEach((w) => w.hide()); setHiddenFlag(true); }
  else { setHiddenFlag(false); wins.forEach((w) => w.showInactive()); }
}
function setupShortcut() {
  // 不建菜单栏图标；只注册快捷键（Ctrl+Alt+P）
  try { globalShortcut.register('CommandOrControl+Alt+P', () => togglePet()); } catch {}
}
app.whenReady().then(() => {
"@
  $s = $s.Replace("app.whenReady().then(() => {", $block)

  $call = "  createPetWindows();"
  if (-not $s.Contains($call)) {
    $problems += "main.js：找不到 createPetWindows() 调用"
  } else {
    $s = $s.Replace($call, @"
  createPetWindows();
  // 防回弹：标记存在时，任何 show 都立刻藏回去
  for (const w of windows.values()) { w.on('show', () => { if (isHiddenFlag()) w.hide(); }); }
  setupShortcut();
"@)
  }

  $ipcAnchor = "  ipcMain.on('pet:open-site', (event, payload) => {"
  if (-not $s.Contains($ipcAnchor)) {
    $problems += "main.js：找不到 pet:open-site 锚点"
  } else {
    $s = $s.Replace($ipcAnchor, @"
  ipcMain.on('pet:hide', () => { setHiddenFlag(true); petWindows().forEach((w) => w.hide()); });
  ipcMain.on('pet:show', () => { setHiddenFlag(false); petWindows().forEach((w) => w.showInactive()); });
  ipcMain.on('pet:quit', async () => {
    try {
      const got = await bridgeRequest('GET', '/dsh-pet-7340/config');
      const cfg = JSON.parse(got && got.body ? got.body : '{}');
      const pets = (cfg.main && Array.isArray(cfg.main.pets)) ? cfg.main.pets
                 : (Array.isArray(cfg.pets) ? cfg.pets : []);
      if (!pets.length) throw new Error('no pets in config');
      for (const pet of pets) pet.display = 'none';
      const put = await bridgeRequest('PUT', '/dsh-pet-7340/config', JSON.stringify({ pets }));
      if (!put || put.status !== 200) throw new Error('config save status ' + (put && put.status));
      setHiddenFlag(false);
      petWindows().forEach((w) => { try { w.webContents.send('pet-muted', true); } catch {} w.hide(); });
      setTimeout(() => { try { app.quit(); } catch {} }, 2500);
    } catch (e) {
      console.error('[dsh-pet helper] quit failed:', e && e.message ? e.message : e);
      setHiddenFlag(true);
      petWindows().forEach((w) => w.hide());
    }
  });
  ipcMain.on('pet:open-site', (event, payload) => {
"@)
  }

  Write-Utf8 $p $s
  Write-Host "main.js 已打补丁"
}

# ---------------- 收尾自检 ----------------
$checks = @(
  @{ File = "sprite.js"; Marker = "hide-pet" },
  @{ File = "sprite.js"; Marker = "leaf.action === 'hide-pet'" },
  @{ File = "sprite.js"; Marker = "leaf.action === 'quit-pet'" },
  @{ File = "preload.js"; Marker = "hidePet" },
  @{ File = "preload.js"; Marker = "onPetMuted" },
  @{ File = "main.js"; Marker = "HIDDEN_FLAG" },
  @{ File = "main.js"; Marker = "pet:quit" }
)
foreach ($c in $checks) {
  $text = Read-Utf8 (Join-Path $H $c.File)
  if (-not $text.Contains($c.Marker)) { $problems += "$($c.File)：缺少 $($c.Marker)" }
}

if ($problems.Count -gt 0) {
  Write-Host ""
  Write-Host "有问题，没完全打好：" -ForegroundColor Yellow
  $problems | ForEach-Object { Write-Host "  - $_" }
  Write-Host ""
  Write-Host "可把上面的报错连同插件版本号发到 Issues；原文件已备份为 *.bak-HHMM。"
  exit 1
}

Write-Host "补丁完成，重启 DSH 生效。" -ForegroundColor Green
