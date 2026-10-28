# 大肥鱼右键菜单补丁（Windows / PowerShell）
# 用法：右键本文件 → 使用 PowerShell 运行
# 作用：隐藏大肥鱼（Ctrl+Alt+P 叫回）· 退出桌宠（真退出）· 系统托盘图标
$ErrorActionPreference = "Stop"
$H = Join-Path $env:USERPROFILE ".dsh\profiles\desktop\node_modules\dsh-pet\runtime\electron-helper"
if (-not (Test-Path $H)) { Write-Host "找不到插件目录：$H" -ForegroundColor Red; exit 1 }

function Read-Utf8($p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Write-Utf8($p, $s) { [System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding($false))) }
function Backup($p) {
  $b = "$p.bak-" + (Get-Date -Format "HHmm")
  if (-not (Test-Path $b)) { Copy-Item $p $b }
}

# ---------------- sprite.js ----------------
$p = Join-Path $H "sprite.js"
$s = Read-Utf8 $p
if ($s -notmatch "hide-pet") {
  Backup $p
  $old = "    const tree = tools.concat(S.buildMenuTree(this.animations));"
  $new = @"
    const tree = tools.concat(S.buildMenuTree(this.animations), [
      // 隐藏到菜单栏，Ctrl+Alt+P 或托盘叫回
      { label: '隐藏大肥鱼', action: 'hide-pet' },
      // 退出：真退出（配置 display=none），不会被守护重启回弹
      { label: '退出桌宠', action: 'quit-pet' },
    ]);
"@
  $s = $s.Replace($old, $new)
  $anchor = "    if (leaf.anim) return;"
  $insert = @"
    if (leaf.action === 'hide-pet') {
      if (window.petBridge && window.petBridge.hidePet) window.petBridge.hidePet();
      return;
    }
    if (leaf.action === 'quit-pet') {
      if (window.petBridge && window.petBridge.quitPet) window.petBridge.quitPet();
      return;
    }
"@
  $s = $s.Replace($anchor, $insert + $anchor)
  Write-Utf8 $p $s
  Write-Host "sprite.js 已打补丁"
}

# ---------------- preload.js ----------------
$p = Join-Path $H "preload.js"
$s = Read-Utf8 $p
if ($s -notmatch "hidePet") {
  Backup $p
  $s = $s.Replace("  openDshSite(url) {", @"
  // 隐藏 / 退出（都只动 Helper，不动 DSH）
  hidePet() { ipcRenderer.send('pet:hide'); },
  quitPet() { ipcRenderer.send('pet:quit'); },
  onPetMuted(cb) { ipcRenderer.on('pet-muted', (_e, v) => cb(!!v)); },
  openDshSite(url) {
"@)
  Write-Utf8 $p $s
  Write-Host "preload.js 已打补丁"
}

# ---------------- main.js ----------------
$p = Join-Path $H "main.js"
$s = Read-Utf8 $p
if ($s -notmatch "HIDDEN_FLAG") {
  Backup $p
  $s = $s.Replace(
    "const { app, BrowserWindow, ipcMain, screen, shell, protocol } = electronApi;",
    "const { app, BrowserWindow, ipcMain, screen, shell, protocol, globalShortcut } = electronApi;")

  $block = @"
/* ---------- 隐藏标记（跨 Helper 重启记住） ---------- */
const nodeFs = require('node:fs');
const HIDDEN_FLAG = path.join(app.getPath('userData'), 'pet-hidden.flag');
function isHiddenFlag() { try { return nodeFs.existsSync(HIDDEN_FLAG); } catch { return false; } }
function setHiddenFlag(v) {
  try {
    if (v) nodeFs.writeFileSync(HIDDEN_FLAG, String(Date.now()));
    else nodeFs.rmSync(HIDDEN_FLAG, { force: true });
  } catch {}
}
let tray = null;
function petWindows() { return Array.from(windows.values()).filter((w) => !w.isDestroyed()); }
function petVisible() { return petWindows().some((w) => w.isVisible()); }
function togglePet() {
  const wins = petWindows();
  if (!wins.length) return;
  if (petVisible()) { wins.forEach((w) => w.hide()); setHiddenFlag(true); }
  else { setHiddenFlag(false); wins.forEach((w) => w.showInactive()); }
}
function setupTray() {
  // 不建菜单栏图标；只注册快捷键（Ctrl+Alt+P）
  try { globalShortcut.register('CommandOrControl+Alt+P', () => togglePet()); } catch {}
}

app.whenReady().then(() => {
"@
  $s = $s.Replace("app.whenReady().then(() => {", $block)

  $s = $s.Replace(@"
  createPetWindows();
"@, @"
  createPetWindows();
  for (const w of windows.values()) { w.on('show', () => { if (isHiddenFlag()) w.hide(); }); }
  setupTray();
  if (isHiddenFlag()) petWindows().forEach((w) => w.hide());
"@)

  $s = $s.Replace("  ipcMain.on('pet:open-site', (event, payload) => {", @"
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
  Write-Utf8 $p $s
  Write-Host "main.js 已打补丁"
}

Write-Host "完成。请重启 DSH。" -ForegroundColor Green
