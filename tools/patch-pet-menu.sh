#!/bin/bash
# 大肥鱼右键菜单补丁（dsh-pet 插件更新后运行一次；可重复执行）
#   隐藏大肥鱼（⌥⌘P / Ctrl+Alt+P 叫回）· 退出桌宠（真退出，不重启回弹）· 无菜单栏图标
#   重复执行只补缺失项；锚点对不上会报错，不会假装成功。
set -euo pipefail

H="$HOME/.dsh/profiles/desktop/node_modules/dsh-pet/runtime/electron-helper"
if [ ! -d "$H" ]; then
  echo "找不到插件运行时目录：$H" >&2
  echo "先启动一次 DSH，或确认 dsh-pet 插件已装好。" >&2
  exit 1
fi

python3 - "$H" <<'PY'
import os, sys, time

H = sys.argv[1]
applied, skipped, problems, notes = [], [], [], []


def read(name):
    with open(os.path.join(H, name), encoding="utf-8") as f:
        return f.read()


def write(name, s):
    with open(os.path.join(H, name), "w", encoding="utf-8") as f:
        f.write(s)


def backup(name):
    p = os.path.join(H, name)
    b = p + ".bak-" + time.strftime("%H%M")
    if not os.path.exists(b):
        with open(p, encoding="utf-8") as f:
            open(b, "w", encoding="utf-8").write(f.read())


def ensure(name, marker, old, new, label):
    """marker 已在 → 跳过；锚点不在 → 记为问题；否则替换并记一笔。"""
    s = read(name)
    if marker in s:
        skipped.append(label)
        return
    if old not in s:
        problems.append("%s：锚点没找到，未应用「%s」" % (name, label))
        return
    backup(name)
    write(name, s.replace(old, new, 1))
    applied.append(label)


# ---------------- sprite.js ----------------
ensure("sprite.js", "hide-pet",
       "    const tree = tools.concat(S.buildMenuTree(this.animations));",
       """    const tree = tools.concat(S.buildMenuTree(this.animations), [
      // 隐藏：只藏形象，语音继续；⌥⌘P 叫回（不建菜单栏图标）
      { label: '隐藏大肥鱼', action: 'hide-pet' },
      // 退出：落标记后隐藏，不会被守护重启回弹
      { label: '退出桌宠', action: 'quit-pet' },
    ]);""",
       "sprite.js 右键菜单")

ensure("sprite.js", "leaf.action === 'hide-pet'",
       "    if (!leaf.anim) return;",
       """    if (leaf.action === 'hide-pet') {
      if (window.petBridge && window.petBridge.hidePet) window.petBridge.hidePet();
      return;
    }
    if (!leaf.anim) return;""",
       "sprite.js 隐藏点击处理")

ensure("sprite.js", "leaf.action === 'quit-pet'",
       "    if (!leaf.anim) return;",
       """    if (leaf.action === 'quit-pet') {
      if (window.petBridge && window.petBridge.quitPet) window.petBridge.quitPet();
      return;
    }
    if (!leaf.anim) return;""",
       "sprite.js 退出点击处理")

# ---------------- preload.js ----------------
ensure("preload.js", "hidePet",
       "  openDshSite(url) {",
       """  // 隐藏 / 退出（都只动 Helper，不动 DSH）
  hidePet() { ipcRenderer.send('pet:hide'); },
  quitPet() { ipcRenderer.send('pet:quit'); },
  openDshSite(url) {""",
       "preload.js 隐藏/退出桥")

ensure("preload.js", "onPetMuted",
       "  openDshSite(url) {",
       """  // 主进程通知静音/恢复（退出时用）
  onPetMuted(cb) { ipcRenderer.on('pet-muted', (_e, v) => cb(!!v)); },
  openDshSite(url) {""",
       "preload.js 静音通知桥")

# ---------------- main.js ----------------
s = read("main.js")

if "HIDDEN_FLAG" in s:
    skipped.append("main.js 隐藏/退出/快捷键")
else:
    if "setupTray" in s or "refreshTrayMenu" in s:
        problems.append("main.js：检测到旧版托盘补丁（没有隐藏标记）。"
                        "请先把 main.js 恢复成 .bak-* 原版，再重跑本脚本。")
    else:
        backup("main.js")

        old_imp = "const { app, BrowserWindow, ipcMain, screen, shell, protocol } = electronApi;"
        if old_imp in s:
            s = s.replace(old_imp,
                          "const { app, BrowserWindow, ipcMain, screen, shell, protocol, "
                          "globalShortcut } = electronApi;", 1)
        else:
            problems.append("main.js：没认出 electronApi 解构行，快捷键可能不可用")

        block = """/* ---------- 隐藏标记（跨 Helper 重启记住） ---------- */
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
  // 不建菜单栏图标；只注册快捷键（Option+Cmd+P / Ctrl+Alt+P）
  try { globalShortcut.register('CommandOrControl+Alt+P', () => togglePet()); } catch {}
}
app.whenReady().then(() => {"""
        s = s.replace("app.whenReady().then(() => {", block, 1)

        call = "  createPetWindows();"
        if call in s:
            s = s.replace(call, call + """
  // 防回弹：标记存在时，任何 show 都立刻藏回去
  for (const w of windows.values()) { w.on('show', () => { if (isHiddenFlag()) w.hide(); }); }
  setupShortcut();""", 1)
        else:
            problems.append("main.js：没找到 createPetWindows() 调用，快捷键没注册")

        anchor = "  ipcMain.on('pet:open-site', (event, payload) => {"
        if anchor in s:
            s = s.replace(anchor, """  ipcMain.on('pet:hide', () => { setHiddenFlag(true); petWindows().forEach((w) => w.hide()); }); // 只藏形象，语音继续
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
""" + anchor, 1)
        else:
            problems.append("main.js：没找到 pet:open-site 锚点，隐藏/退出 IPC 没插入")

        write("main.js", s)
        applied.append("main.js 隐藏/退出/快捷键")

# ---------------- 收尾自检 ----------------
for name, marker, label in [
    ("sprite.js", "hide-pet", "sprite.js 菜单项"),
    ("sprite.js", "leaf.action === 'hide-pet'", "sprite.js 隐藏点击"),
    ("sprite.js", "leaf.action === 'quit-pet'", "sprite.js 退出点击"),
    ("preload.js", "hidePet", "preload.js 隐藏/退出桥"),
    ("preload.js", "onPetMuted", "preload.js 静音桥"),
    ("main.js", "HIDDEN_FLAG", "main.js 隐藏标记"),
    ("main.js", "pet:quit", "main.js 退出 IPC"),
]:
    if marker not in read(name):
        problems.append("%s：缺少「%s」" % (name, label))

# 旧版（v1.2.0 早期）会建菜单栏图标；v1.2.1 不需要，但不必为此回滚
if "new Tray(" in read("main.js"):
    notes.append("main.js 里还留着旧版菜单栏图标代码（new Tray）。"
                 "不影响本轮改动；想彻底去掉，先恢复 main.js.bak-* 再重跑本脚本。")

if applied:
    print("已应用：" + "、".join(applied))
if skipped:
    print("之前已有，跳过：" + "、".join(skipped))
for n in notes:
    print("提示：" + n)
if problems:
    print("")
    print("有问题，没完全打好：")
    for p in problems:
        print("  - " + p)
    print("")
    print("可把上面的报错连同插件版本号发到 Issues；原文件已备份为 *.bak-HHMM。")
    sys.exit(1)

print("补丁完成，重启 DSH 生效。")
PY
