#!/usr/bin/env python3
"""用你自己的 MiniMax 账号复刻一个音色（可选，非商业）。

用法：
  export MINIMAX_API_KEY="你自己的 key"
  pip install requests
  python tools/minimax_clone.py --audio my_ref.wav --voice-id my_dafeiyu_01

可选：
  --host https://api.minimax.chat     # 或你的区域 host
  --model speech-2.8-hd
  --prompt-audio prompt.wav --prompt-text "示例音频的文字"
  --demo-text "爸爸，做完啦！"

说明：
  - 参考音要求 10 秒–5 分钟，mp3/m4a/wav，≤20MB。
  - 复刻本身不立即收费；**第一次用这个音色合成时**才会扣 ¥9.90。
  - 本脚本只读环境变量，不会把 key 写进任何文件。
"""
import argparse
import json
import os
import re
import sys

try:
    import requests
except ImportError:
    sys.exit("缺少 requests：先 pip install requests")


def check_voice_id(v):
    if not (8 <= len(v) <= 256):
        sys.exit("voice_id 长度必须是 8–256")
    if not re.match(r"^[A-Za-z][A-Za-z0-9_-]*$", v):
        sys.exit("voice_id 必须以字母开头，只能含字母/数字/-/_")
    if v[-1] in "-_":
        sys.exit("voice_id 末位不能是 - 或 _")


def upload(host, key, path, purpose):
    with open(path, "rb") as f:
        r = requests.post(
            host + "/v1/files/upload",
            headers={"Authorization": f"Bearer {key}"},
            data={"purpose": purpose},
            files={"file": (os.path.basename(path), f)},
            timeout=180,
        )
    try:
        d = r.json()
    except Exception:
        sys.exit(f"上传返回非 JSON（HTTP {r.status_code}）：{r.text[:300]}")
    if r.status_code != 200 or (d.get("base_resp") or {}).get("status_code") != 0:
        sys.exit(f"上传失败：HTTP {r.status_code} {json.dumps(d, ensure_ascii=False)[:400]}")
    return (d.get("file") or {}).get("file_id")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio", required=True, help="10 秒–5 分钟的参考音")
    ap.add_argument("--voice-id", required=True, help="自定义 voice_id，8–256 位，字母开头")
    ap.add_argument("--host", default=os.environ.get("MINIMAX_HOST", "https://api.minimax.chat"))
    ap.add_argument("--model", default="speech-2.8-hd")
    ap.add_argument("--prompt-audio", help="可选：<8 秒示例音，增强相似度")
    ap.add_argument("--prompt-text", help="示例音对应的文字")
    ap.add_argument("--demo-text", default="爸爸，做完啦！", help="复刻试听文本")
    args = ap.parse_args()

    key = (os.environ.get("MINIMAX_API_KEY") or "").strip()
    if not key:
        sys.exit("没有设置 MINIMAX_API_KEY（只放在环境变量里，不要提交到仓库）")
    check_voice_id(args.voice_id)
    host = args.host.rstrip("/")

    print("上传参考音…", flush=True)
    file_id = upload(host, key, args.audio, "voice_clone")
    prompt_id = None
    if args.prompt_audio:
        if not args.prompt_text:
            sys.exit("给了 --prompt-audio 就必须同时给 --prompt-text")
        print("上传示例音…", flush=True)
        prompt_id = upload(host, key, args.prompt_audio, "prompt_audio")

    payload = {
        "file_id": file_id,
        "voice_id": args.voice_id,
        "text": args.demo_text,
        "model": args.model,
    }
    if prompt_id:
        payload["clone_prompt"] = {"prompt_audio": prompt_id, "prompt_text": args.prompt_text}

    print("复刻中…", flush=True)
    r = requests.post(host + "/v1/voice_clone",
                      headers={"Authorization": f"Bearer {key}",
                               "Content-Type": "application/json"},
                      json=payload, timeout=300)
    try:
        d = r.json()
    except Exception:
        sys.exit(f"复刻返回非 JSON（HTTP {r.status_code}）：{r.text[:300]}")
    base = d.get("base_resp") or {}
    if r.status_code != 200 or base.get("status_code") != 0:
        sys.exit(f"复刻失败：HTTP {r.status_code} {json.dumps(d, ensure_ascii=False)[:500]}")

    print("\n✅ 复刻成功")
    print("voice_id:", args.voice_id)
    if d.get("demo_audio"):
        print("试听:", d["demo_audio"])
    print("\n下一步：")
    print("  1. 把 voice_id 填进 ~/.dsh/pet-tts/config.json：")
    print('     {"engine":"minimax","voice":"%s","model":"%s","speed":1.0,"pitch":0}'
          % (args.voice_id, args.model))
    print("  2. 设置 MINIMAX_API_KEY 环境变量，启动 tools/tts_server.py")
    print("  3. bash tools/patch-pet-voice.sh，重启 DSH")
    print("\n注意：第一次正式合成会扣 ¥9.90 复刻费；自托管输出仅限非商业。")


if __name__ == "__main__":
    main()
