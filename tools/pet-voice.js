/* 大肥鱼语音 + 成长记
 * 作者：ReadyPlayer_柒（MIT）
 */
/* 大肥鱼语音：监听桌面气泡，调本地 TTS 播放 */
(() => {
  if (window.__petVoice) return;
  window.__petVoice = true;
  const BASE = "http://127.0.0.1:18888";
  const spoken = new Set();
  let current = null;

  function speak(text) {
    const t = (text || "").trim();
    if (!t || t.length < 2) return;
    if (/^[¥￥\d.,\s]+$/.test(t)) return;          // 纯数字/余额不念
    if (t.indexOf("余额") >= 0) return;
    if (t.indexOf("失败") >= 0 || t.indexOf("Error") >= 0) return;
    if (spoken.has(t)) return;
    spoken.add(t);
    if (spoken.size > 300) spoken.clear();
    try {
      if (current) { try { current.pause(); } catch (e) {} current = null; }
      fetch(BASE + "/tts?text=" + encodeURIComponent(t.slice(0, 80)))
        .then(r => (r.ok ? r.blob() : null))
        .then(b => {
          if (!b) return;
          const a = new Audio(URL.createObjectURL(b));
          current = a;
          a.play().catch(() => {});
        })
        .catch(() => {});
    } catch (e) {}
  }

  // ---------- 成长记：陪伴天数 + 完成任务次数（存本地，不依赖配置重载） ----------
  const GKEY = "dfy_growth_v1";
  const today = () => new Date().toISOString().slice(0, 10);
  function gLoad() {
    try { return JSON.parse(localStorage.getItem(GKEY) || "{}"); } catch (e) { return {}; }
  }
  function gSave(g) {
    try { localStorage.setItem(GKEY, JSON.stringify(g)); } catch (e) {}
  }
  function daysSince(d) {
    if (!d) return 1;
    const a = new Date(d + "T00:00:00"), b = new Date(today() + "T00:00:00");
    return Math.max(1, Math.round((b - a) / 86400000) + 1);
  }
  function grow(text) {
    const g = gLoad();
    if (!g.first) g.first = today();
    const isDone = /做完|搞定|完成|收工/.test(text);
    const isGreet = /回来啦|等爸爸|一起加油|今天忙不忙/.test(text);
    if (isDone) {
      g.done = (g.done || 0) + 1;
      if (g.lastDone !== today()) { g.lastDone = today(); g.todayCount = 0; }
      g.todayCount = (g.todayCount || 0) + 1;
      gSave(g);
      if (g.todayCount === 1) setTimeout(() => speak("爸爸，今天第一次搞定"), 1400);
      else if (g.done % 10 === 0) setTimeout(() => speak("爸爸，这是第 " + g.done + " 次啦"), 1400);
    } else if (isGreet) {
      if (g.lastGreet !== today()) {
        g.lastGreet = today(); gSave(g);
        setTimeout(() => speak("今天是第 " + daysSince(g.first) + " 天陪爸爸"), 1400);
      }
    } else {
      gSave(g);
    }
  }

  const seen = new WeakMap();
  function scan(root) {
    const nodes = root.querySelectorAll ? root.querySelectorAll(".pet-bubble") : [];
    for (const el of nodes) {
      const txt = (el.textContent || "").trim();
      if (!txt) continue;
      if (!el.classList.contains("is-on")) continue;
      if (seen.get(el) === txt) continue;
      seen.set(el, txt);
      speak(txt);
      grow(txt);
    }
  }

  new MutationObserver(() => scan(document)).observe(document.body, {
    childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["class"]
  });
  setTimeout(() => scan(document), 1500);
  window.__petVoiceDebug = { speak, grow, reset: () => { try { localStorage.removeItem(GKEY); } catch (e) {} } };
})();
