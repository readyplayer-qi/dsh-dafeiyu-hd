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
  openDshSite(url) {""", 1)
    open(p, "w").write(s)

# ---------------- main.js ----------------
p = os.path.join(H, "main.js"); s = open(p).read()
if "HIDDEN_FLAG" not in s:
    backup(p)
    s = s.replace("const { app, BrowserWindow, ipcMain, screen, shell, protocol } = electronApi;",
"const { app, BrowserWindow, ipcMain, screen, shell, protocol, Tray, Menu, nativeImage, globalShortcut } = electronApi;", 1)
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
let tray = null;
function petWindows() { return Array.from(windows.values()).filter((w) => !w.isDestroyed()); }
function petVisible() { return petWindows().some((w) => w.isVisible()); }
function togglePet() {
  const wins = petWindows();
  if (!wins.length) return;
  if (petVisible()) { wins.forEach((w) => w.hide()); setHiddenFlag(true); }
  else { setHiddenFlag(false); wins.forEach((w) => w.showInactive()); }
  refreshTrayMenu();
}
function refreshTrayMenu() {
  if (!tray) return;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: petVisible() ? '隐藏大肥鱼' : '显示大肥鱼', click: () => togglePet() },
    { type: 'separator' },
    { label: '退出桌宠', click: () => { setHiddenFlag(true); petWindows().forEach((w) => w.hide()); refreshTrayMenu(); } },
  ]));
  tray.setToolTip(petVisible() ? '大肥鱼（⌥⌘P 隐藏）' : '大肥鱼（⌥⌘P 叫回）');
}
function setupTray() {
  try {
    const iconPath = path.join(__dirname, '..', '..', 'assets', 'logo.png');
    let img = nativeImage.createFromPath(iconPath);
    if (!img.isEmpty()) { img = img.resize({ width: 18, height: 18 }); img.setTemplateImage(true); }
    tray = new Tray(img);
    if (img.isEmpty()) tray.setTitle('🐟');
    tray.on('click', () => togglePet());
    try { globalShortcut.register('CommandOrControl+Alt+P', () => togglePet()); } catch {}
    refreshTrayMenu();
    for (const w of petWindows()) { w.on('show', refreshTrayMenu); w.on('hide', refreshTrayMenu); }
  } catch (e) { console.error('[dsh-pet helper] tray setup failed:', e && e.message); }
}
app.whenReady().then(() => {""", 1)
    s = s.replace("  createPetWindows();", """  createPetWindows();
  // 防回弹：标记存在时，任何 show 都立刻藏回去
  for (const w of windows.values()) { w.on('show', () => { if (isHiddenFlag()) w.hide(); }); }
  setupTray();""", 1)
    s = s.replace("  ipcMain.on('pet:open-site', (event, payload) => {", """  ipcMain.on('pet:hide', () => { setHiddenFlag(true); petWindows().forEach((w) => w.hide()); refreshTrayMenu(); }); // 只藏形象，语音继续
  ipcMain.on('pet:show', () => { setHiddenFlag(false); petWindows().forEach((w) => w.showInactive()); refreshTrayMenu(); });
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
      petWindows().forEach((w) => w.hide());
      setTimeout(() => { try { app.quit(); } catch {} }, 2500);
    } catch (e) {
      console.error('[dsh-pet helper] quit failed:', e && e.message ? e.message : e);
      setHiddenFlag(true);
      petWindows().forEach((w) => w.hide());
      refreshTrayMenu();
    }
  });
  ipcMain.on('pet:open-site', (event, payload) => {""", 1)
    open(p, "w").write(s)
print("菜单补丁已应用")
PY

# ---------------- lib/client.js（设置页：下拉下方加粗提示） ----------------
P="$(dirname "$H")/../lib/client.js"
python3 - "$P" <<'PY2'
import sys, os, time
p = sys.argv[1]
if not os.path.exists(p): raise SystemExit(0)
s = open(p).read()
if "彻底关闭桌宠" in s: raise SystemExit(0)
b = p + ".bak-" + time.strftime("%H%M")
open(b, "w").write(s)
s = s.replace('"display.none": "都不显示"', '"display.none": "都不显示（关闭桌宠）"', 1)
old = '''								field(t("displayLabel"), h("select", {
									className: inputClass,
									value: cur.display,
									disabled: busy,
									onChange: (e) => updateSel({ display: e.target.value }),
									children: PET_DISPLAYS.map((d) => h("option", {
										key: d,
										value: d,
										children: t("display." + d)
									}))
								}), t("displayHint"), true)'''
new = '''								h("div", { className: "dsh-pet-cfg__field", children: [
									h("span", { key: "l", className: "dsh-pet-cfg__flabel", children: [t("displayLabel"), q(t("displayHint"), true)] }),
									h("select", {
										className: inputClass,
										value: cur.display,
										disabled: busy,
										onChange: (e) => updateSel({ display: e.target.value }),
										children: PET_DISPLAYS.map((d) => h("option", { key: d, value: d, children: t("display." + d) }))
									}),
									h("span", {
										key: "n",
										style: { position: "absolute", left: "0", bottom: "-13px", fontSize: "10px", fontWeight: "700", color: "#C9A96A", whiteSpace: "nowrap" },
										children: "「都不显示」= 关闭桌宠"
									})
								])'''
if old in s:
    s = s.replace(old, new, 1)
    open(p, "w").write(s)
    print("设置页提示已加")
else:
    print("设置页结构变了，跳过（需手动看）")
PY2
