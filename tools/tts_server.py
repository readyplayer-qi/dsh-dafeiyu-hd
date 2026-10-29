#!/usr/bin/env python3
"""大肥鱼 · 本地语音服务（edge-tts 免费 / 可选 MiniMax 克隆音色）

用法：
  1. 安装 edge-tts：  pip install edge-tts
  2. 启动服务：       python tools/tts_server.py
  3. 装语音挂钩：     bash tools/patch-pet-voice.sh
  4. 重启 DSH

监听 127.0.0.1:18888：
  GET /tts?text=...  返回 mp3
  GET /health        自检（引擎、edge-tts、ffmpeg、是否有 MiniMax key）

默认只用 edge-tts，不需要任何 key。
想用自己克隆的 MiniMax 音色：
  - 在环境变量里设置 MINIMAX_API_KEY（你自己的 key）
  - 在 ~/.dsh/pet-tts/config.json 里设置 engine=minimax、voice=<你的 voice_id>
  - 本仓库不包含任何 MiniMax key 或克隆音色。
"""
import json
import os
import shutil
import subprocess
import tempfile
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOME = os.path.expanduser("~")
CFG = os.path.join(HOME, ".dsh/pet-tts/config.json")
PORT = int(os.environ.get("PET_TTS_PORT", "18888"))

DEFAULTS = {
    "engine": "edge",                       # edge | minimax
    "edgeVoice": "zh-CN-XiaoyiNeural",
    "pitchHz": "+25Hz",
    "rate": "-6%",
    "voice": "",                            # 你自己的 MiniMax voice_id
    "model": "speech-2.8-hd",
    "speed": 1.0,
    "pitch": 0,
    "dsp": "loudnorm=I=-16:TP=-1.5",
    "maxChars": 80,
}


def cfg():
    try:
        return {**DEFAULTS, **json.load(open(CFG, encoding="utf-8"))}
    except Exception:
        return dict(DEFAULTS)


def minimax_key():
    return (os.environ.get("MINIMAX_API_KEY") or "").strip()


def minimax_host():
    return (os.environ.get("MINIMAX_HOST") or "https://api.minimax.chat").rstrip("/")


def find_edge():
    for p in (shutil.which("edge-tts"),
              os.path.join(HOME, "Library/Python/3.9/bin/edge-tts"),
              os.path.join(HOME, ".local/bin/edge-tts")):
        if p and os.path.exists(p):
            return p
    return None


def find_ffmpeg():
    for p in (shutil.which("ffmpeg"), os.path.join(HOME, ".dsh/bin/ffmpeg")):
        if p and os.path.exists(p):
            return p
    return None


def encode(raw, out, dsp):
    ff = find_ffmpeg()
    if ff and dsp:
        subprocess.run([ff, "-y", "-loglevel", "error", "-i", raw, "-af", dsp,
                        "-c:a", "libmp3lame", "-b:a", "160k", out],
                       capture_output=True, timeout=40)
        return out if os.path.exists(out) and os.path.getsize(out) else raw
    return raw


def synth_minimax(text, c):
    key = minimax_key()
    voice = (c.get("voice") or "").strip()
    if not key or not voice:
        return None
    body = {
        "model": c.get("model", "speech-2.8-hd"),
        "text": text,
        "stream": False,
        "voice_setting": {"voice_id": voice,
                          "speed": float(c.get("speed", 1.0)),
                          "vol": 1.0, "pitch": int(c.get("pitch", 0))},
        "audio_setting": {"sample_rate": 32000, "bitrate": 128000,
                          "format": "mp3", "channel": 1},
    }
    req = urllib.request.Request(
        minimax_host() + "/v1/t2a_v2",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    raw = out = None
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            d = json.loads(r.read())
        hexaudio = (d.get("data") or {}).get("audio")
        if not hexaudio:
            return None
        fd, raw = tempfile.mkstemp(suffix=".mp3")
        os.close(fd)
        with open(raw, "wb") as f:
            f.write(bytes.fromhex(hexaudio))
        fd, out = tempfile.mkstemp(suffix=".mp3")
        os.close(fd)
        use = encode(raw, out, c.get("dsp") or "")
        with open(use, "rb") as f:
            return f.read()
    except Exception:
        return None
    finally:
        for p in (raw, out):
            try:
                if p:
                    os.remove(p)
            except Exception:
                pass


def synth_edge(text, c):
    edge = find_edge()
    if not edge:
        return None
    fd, raw = tempfile.mkstemp(suffix=".mp3")
    os.close(fd)
    fd, out = tempfile.mkstemp(suffix=".mp3")
    os.close(fd)
    try:
        subprocess.run([edge, f"--voice={c['edgeVoice']}", f"--text={text}",
                        f"--pitch={c['pitchHz']}", f"--rate={c['rate']}",
                        f"--write-media={raw}"],
                       capture_output=True, timeout=40)
        if not os.path.exists(raw) or os.path.getsize(raw) == 0:
            return None
        use = encode(raw, out, c.get("dsp") or "")
        with open(use, "rb") as f:
            return f.read()
    except Exception:
        return None
    finally:
        for p in (raw, out):
            try:
                os.remove(p)
            except Exception:
                pass


def synth(text, c):
    if c.get("engine") == "minimax":
        data = synth_minimax(text, c)
        if data:
            return data
        # key 缺失/余额不足/网络失败 → 回落免费 edge
    return synth_edge(text, c)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,OPTIONS")

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/health":
            c = cfg()
            engine = "minimax" if (c.get("engine") == "minimax"
                                   and minimax_key() and c.get("voice")) else "edge"
            body = json.dumps({
                "ok": bool(engine == "minimax" or find_edge()),
                "engine": engine,
                "configuredEngine": c.get("engine"),
                "edgeTts": find_edge(),
                "ffmpeg": find_ffmpeg(),
                "minimaxKey": bool(minimax_key()),
                "voice": c.get("voice") if engine == "minimax" else c.get("edgeVoice"),
            }, ensure_ascii=False).encode()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if u.path != "/tts":
            self.send_response(404)
            self.end_headers()
            return
        text = (parse_qs(u.query).get("text") or [""])[0].strip()
        if not text:
            self.send_response(400)
            self.end_headers()
            return
        text = text[: int(cfg().get("maxChars", 80))]
        data = synth(text, cfg())
        if not data:
            self.send_response(500)
            self.end_headers()
            return
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    c = cfg()
    engine = "minimax" if (c.get("engine") == "minimax" and minimax_key()
                           and c.get("voice")) else "edge"
    print(f"pet-tts ({engine}) listening on 127.0.0.1:{PORT}", flush=True)
    if engine == "edge" and not find_edge():
        print("警告：没找到 edge-tts。先 pip install edge-tts，再重启本服务。", flush=True)
    if c.get("engine") == "minimax" and not minimax_key():
        print("提示：config 里 engine=minimax，但没有设置 MINIMAX_API_KEY；已自动回落 edge。", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
