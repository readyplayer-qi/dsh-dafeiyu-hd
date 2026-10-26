#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Real-ESRGAN 超分桌宠动画（保留 alpha）
# 作者：ReadyPlayer_柒（MIT）
"""把桌宠 webm 动画做 Real-ESRGAN 超分（保留 alpha）
用法：~/.venvs/u312/bin/python upscale_pet.py [--all]
默认处理 10 个常用动作；--all 处理全部。
"""
import os, sys, glob, time, subprocess, shutil, json
import numpy as np
import torch
from PIL import Image
from spandrel import ModelLoader

FF = os.path.expanduser("~/.dsh/bin/ffmpeg")
ASSETS = os.environ.get("PET_WEBM_DIR") or os.path.expanduser(
    "~/.dsh/profiles/desktop/node_modules/dsh-pet/assets/webm")
MODEL = os.environ.get("ESRGAN_MODEL") or os.path.expanduser("~/models/RealESRGAN_x4plus_anime_6B.pth")
WORK = "/tmp/pet_upscale_work"
LOG = os.path.expanduser("~/.dsh/pet-tts/upscale.log")

TARGETS = [
    "待机呼吸休闲", "工作状态-思考冒泡", "工作状态-忙碌点按", "工作状态-清点归档",
    "东张西望", "点击回应-开心跃动", "点击回应-害羞惊讶", "点击回应-元气挥手",
    "点击回应-傲娇生气", "点击回应-挠痒咯咯笑",
]

def log(msg):
    line = time.strftime("[%H:%M:%S] ") + msg
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")

def main():
    allmode = "--all" in sys.argv
    if not os.path.exists(MODEL):
        sys.exit(f"找不到模型：{MODEL}\n请下载 RealESRGAN_x4plus_anime_6B.pth 并设置 ESRGAN_MODEL")
    names = [os.path.splitext(f)[0] for f in os.listdir(ASSETS) if f.endswith(".webm")]
    todo = names if allmode else [n for n in TARGETS if n in names]
    log(f"开始：{len(todo)} 个动作（{'全部' if allmode else '常用'}）")

    dev = "mps" if torch.backends.mps.is_available() else "cpu"
    model = ModelLoader().load_from_file(MODEL); model.eval(); model.to(dev)

    for idx, name in enumerate(todo, 1):
        src = os.path.join(ASSETS, name + ".webm")
        # 已处理过（宽 1280）就跳过
        probe = subprocess.run([os.path.expanduser("~/.dsh/bin/ffprobe"), "-v", "error",
                                "-select_streams", "v:0", "-show_entries", "stream=width",
                                "-of", "default=nw=1:nk=1", src], capture_output=True, text=True)
        if probe.stdout.strip() == "1280":
            log(f"[{idx}/{len(todo)}] 跳过（已是 1280）：{name}")
            continue
        t0 = time.time()
        wd = os.path.join(WORK, name); shutil.rmtree(wd, ignore_errors=True)
        frames = os.path.join(wd, "in"); outdir = os.path.join(wd, "out")
        os.makedirs(frames); os.makedirs(outdir)
        subprocess.run([FF, "-y", "-loglevel", "error", "-c:v", "libvpx-vp9", "-i", src, "-vsync", "0",
                        "-c:v", "png", "-pix_fmt", "rgba", os.path.join(frames, "%04d.png")], check=True)
        files = sorted(glob.glob(os.path.join(frames, "*.png")))
        with torch.no_grad():
            for f in files:
                im = Image.open(f).convert("RGBA")
                arr = np.asarray(im)
                rgb, a = arr[:, :, :3], arr[:, :, 3]
                x = torch.from_numpy(rgb).float().div(255).permute(2, 0, 1).unsqueeze(0).to(dev)
                y = model(x).clamp(0, 1)[0].permute(1, 2, 0).cpu().numpy()
                yimg = Image.fromarray((y * 255).round().astype(np.uint8)).resize((1280, 720), Image.LANCZOS)
                aimg = Image.fromarray(a).resize((1280, 720), Image.LANCZOS)
                Image.merge("RGBA", (*yimg.split(), aimg)).save(os.path.join(outdir, os.path.basename(f)))
        tmp_out = os.path.join(wd, "out.webm")
        subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30",
                        "-i", os.path.join(outdir, "%04d.png"),
                        "-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-auto-alt-ref", "1",
                        "-lag-in-frames", "25", "-b:v", "0", "-crf", "24", "-row-mt", "1",
                        "-metadata:s:v:0", "alpha_mode=1", "-an", tmp_out], check=True)
        # 校验 alpha：解码首帧，透明像素必须 >50%，否则不替换
        chk = os.path.join(wd, "chk.png")
        subprocess.run([FF, "-y", "-loglevel", "error", "-c:v", "libvpx-vp9", "-i", tmp_out,
                        "-frames:v", "1", chk], check=True)
        from PIL import Image as _I
        import numpy as _np
        alpha = _np.asarray(_I.open(chk).convert("RGBA"))[:, :, 3]
        ratio = float((alpha < 10).mean())
        if ratio < 0.5:
            log(f"[{idx}/{len(todo)}] ✗ alpha 丢失（透明 {ratio*100:.1f}%），保留原文件：{name}")
            shutil.rmtree(wd, ignore_errors=True)
            continue
        shutil.move(tmp_out, src)
        log(f"[{idx}/{len(todo)}] 完成 {name}：{len(files)} 帧，{(time.time()-t0)/60:.1f} 分钟")
        shutil.rmtree(wd, ignore_errors=True)
    log("全部完成")

if __name__ == "__main__":
    main()
