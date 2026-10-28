#!/bin/bash
# 大肥鱼右键菜单补丁（dsh-pet 插件更新后运行一次）
#   隐藏大肥鱼（⌥⌘P / 托盘叫回）· 退出桌宠（不重启回弹）· 菜单最下方
set -e
H="$HOME/.dsh/profiles/desktop/node_modules/dsh-pet/runtime/electron-helper"
python3 - "$H" <<'PY'
import sys, os, time
H = sys.argv[1]
def backup(p):
    b = p + ".bak-" + time.strftime("%H%M")
    if not os.path.exists(b): open(b, "w").write(open(p).read())

# ---------------- sprite.js ----------------
p = os.path.join(H, "sprite.js"); s = open(p).read()
if "hide-pet" not in s:
    backup(p)
    s = s.replace("    const tree = tools.concat(S.buildMenuTree(this.animations));",
"""    const tree = tools.concat(S.buildMenuTree(this.animations), [
      // 隐藏到菜单栏，⌥⌘P 或托盘叫回
      { label: '隐藏大肥鱼', action: 'hide-pet' },
      // 退出：落标记后隐藏，不会被守护重启回弹
      { label: '退出桌宠', action: 'quit-pet' },
    ]);""", 1)
    anchor = "    if (leaf.anim) return;"
    s = s.replace(anchor, """    if (leaf.action === 'hide-pet') {
      if (window.petBridge && window.petBridge.hidePet) window.petBridge.hidePet();
      return;
    }
    if (leaf.action === 'quit-pet') {
      if (window.petBridge && window.petBridge.quitPet) window.petBridge.quitPet();
      return;
    }
""" + anchor, 1)
    open(p, "w").write(s)

# ---------------- preload.js ----------------
p = os.path.join(H, "preload.js"); s = open(p).read()
if "hidePet" not in s:
    backup(p)
    s = s.replace("  openDshSite(url) {",
"""  // 隐藏 / 退出（都只动 Helper，不动 DSH）
  hidePet() { ipcRenderer.send('pet:hide'); },
  quitPet() { ipcRenderer.send('pet:quit'); },
  // 主进程通知静音/恢复（退出时用）
  onPetMuted(cb) { ipcRenderer.on('pet-muted', (_e, v) => cb(!!v)); },
  openDshSite(url) {""", 1)
    open(p, "w").write(s)

# ---------------- main.js ----------------
p = os.path.join(H, "main.js"); s = open(p).read()
if "HIDDEN_FLAG" not in s:
    backup(p)
    s = s.replace("const { app, BrowserWindow, ipcMain, screen, shell, protocol } = electronApi;",
"const { app, BrowserWindow, ipcMain, screen, shell, protocol, globalShortcut } = electronApi;", 1)
    s = s.replace("app.whenReady().then(() => {", """
/* ---------- 隐藏标记（跨 Helper 重启记住） ---------- */
const HIDDEN_FLAG = path.join(app.getPath('userData'), 'pet-hidden.flag');
function isHiddenFlag() { try { return require('node:fs').existsSync(HIDDEN_FLAG); } catch { return false; } }
function setHiddenFlag(v) {
  try {
    if (v) require('node:fs').writeFileSync(HIDDEN_FLAG, String(Date.now()));
    else require('node:fs').rmSync(HIDDEN_FLAG, { force: true });
  } catch {}
}
/* ---------- 托盘：真·退出 + 叫回 ---------- */
function petWindows() { return Array.from(windows.values()).filter((w) => !w.isDestroyed()); }
function petVisible() { return petWindows().some((w) => w.isVisible()); }
function togglePet() {
  const wins = petWindows();
  if (!wins.length) return;
  if (petVisible()) { wins.forEach((w) => w.hide()); setHiddenFlag(true); }
  else { setHiddenFlag(false); wins.forEach((w) => w.showInactive()); }
}
function setupShortcut() {
  // 不建菜单栏图标；只注册快捷键（Option+Cmd+P / Ctrl+Alt+P）
  try { globalShortcut.register('CommandOrControl+Alt+P', () => togglePet()); } catch {}
}
app.whenReady().then(() => {""", 1)
    s = s.replace("  createPetWindows();", """  createPetWindows();
  // 防回弹：标记存在时，任何 show 都立刻藏回去
  for (const w of windows.values()) { w.on('show', () => { if (isHiddenFlag()) w.hide(); }); }
  setupShortcut();""", 1)
    s = s.replace("  ipcMain.on('pet:open-site', (event, payload) => {", """  ipcMain.on('pet:hide', () => { setHiddenFlag(true); petWindows().forEach((w) => w.hide()); }); // 只藏形象，语音继续
  ipcMain.on('pet:show', () => { setHiddenFlag(false); petWindows().forEach((w) => w.showInactive()); });
  // 退出：真退出——把 display 改成 none，宿主不再拉起 Helper（回来：设置→显示位置→仅桌面）
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
  ipcMain.on('pet:open-site', (event, payload) => {""", 1)
    open(p, "w").write(s)
print("菜单补丁已应用")
PY
