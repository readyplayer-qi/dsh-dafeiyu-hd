# 变更记录

## v1.2.2 · 2026-10-29

- 语音改为可选：默认无声；新增 `tools/tts_server.py`（免费 edge-tts）和 `tools/patch-pet-voice.sh`（安装语音 + 设置页提示）
- 新增「自定义音色」教程 `自定义音色.md` + `tools/minimax_clone.py`：用你自己的 MiniMax 账号复刻；包内不含 key/voice_id/参考音
- `tools/tts_server.py` 支持 edge / minimax 双引擎；没有 key 自动回落免费 edge
- 模型与动画未变，高清包仍是 v1.1.0 的 zip

## v1.2.1 · 2026-10-28

- 移除菜单栏（托盘）图标：不再常驻占位，只保留快捷键（Mac Option+Cmd+P / Win Ctrl+Alt+P）
- 修复：点「退出」后旧进程被守护重启，看起来像“退了又回来”；现退出会写入 `display: none`，重启后不再出现
- 同步更新 `tools/patch-pet-menu.sh` / `patch-pet-menu.ps1`
- 修复补丁脚本：右键「隐藏大肥鱼 / 退出桌宠」的点击处理原先锚点写错（`if (leaf.anim)` 少了 `!`），新装用户点了没反应
- 补丁脚本改为逐项补齐：重复执行只补缺失项；锚点对不上会报错，不再打印“已应用”
- 语音改为可选（默认无声）：新增 `tools/tts_server.py`（免费 edge-tts）与 `tools/patch-pet-voice.sh`；README 补「让桌宠说话」
- 新增可选「自定义音色」教程 `自定义音色.md` + `tools/minimax_clone.py`（用户自己的 MiniMax 账号；包内不含 key/音色）

## v1.2.0 · 2026-10-28

新增可选交互增强（`tools/patch-pet-menu.sh`，插件更新后需重跑）：

- 右键「隐藏大肥鱼」：只藏形象，语音继续；⌥⌘P 或菜单栏图标叫回
- 右键「退出桌宠」：真退出（把 `display` 写成 `none`，进程结束）
- 默认隐藏状态跨 Helper 重启记住（不会被守护进程重启回弹）
- 设置页「显示位置」下方加提示：「都不显示」= 关闭桌宠

> 模型与动画未改动，高清包仍是 v1.1.0 的 zip。
## v1.1.0 · 2026-10-26

- 台词全面改写为“女儿”口吻（称呼：爸爸）
- 六档工作状态台词重写
- 工作状态动作重映射（东张西望 / 开心跃动 / 害羞惊讶）
- 贴图 2048² → 4096²
- 106 个动画 640×360 → 1280×720（Real-ESRGAN anime 6B，保留 alpha）
- 窗口尺寸 462 → 600
- 新增成长记脚本（陪伴天数 / 任务计数）

## v1.0.0 · 原始版本

- 来自 氵六青 的 DS鲸鱼娘 Live2D 模型
- 8 组动作 + 44 个表情
