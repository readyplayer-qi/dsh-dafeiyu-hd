# 上游依赖与更新流程

本仓库是**衍生作品**，不是 GitHub fork。上游更新不会自动同步，需要手动处理。

## 一、上游是谁

| 上游 | 作用 | 我们从它拿了什么 |
|---|---|---|
| **DS鲸鱼娘 Live2D 模型**（氵六青） | 模型与动画 | `pet/ds-whale-girl/` 全部素材 |
| [dsh-pet-live2d](https://github.com/A8Chann/dsh-pet-live2d) | 桌宠插件 | 运行环境、配置字段规范 |
| [dsh-pet](https://github.com/PC2005-cloud/dsh-pet) | 桌宠核心（v0.3.7 时验证） | 工作状态事件、气泡、TTS 挂载点 |

记录时间：2026-10-26

## 二、上游更新了怎么办

### 情况 A：模型素材更新（新动作/新表情/修图）

不会自动同步。要跟的话，按这个顺序重放我们的改动：

```
1. 用新版 pet 目录替换 pet/ds-whale-girl/
2. 重新应用 config/ 里的三块配置：
   - whisperPrompt
   - workStatusTexts
   - animations.events.workStatus
3. 对新素材跑一遍超分：
   python3 tools/upscale_pet.py --all
4. 检查 alpha（每个文件解码首帧，透明像素 >50%）
5. 更新 CHANGELOG 与 UPSTREAM
```

**不跟也能用**——当前版本是自洽的，不依赖上游未来版本。

### 情况 B：插件更新（dsh-pet / dsh-pet-live2d）

**风险最高**，因为配置字段可能变。更新后自检：

| 检查项 | 现象 |
|---|---|
| 工作状态台词 | 不显示 / 显示成默认句 |
| 动作映射 | 动作不跟着状态变 |
| 气泡 | 不弹 / 弹出位置错 |
| 语音 | 不读 / 读错 |

任一异常 → 先回滚插件，再对照新版的配置文档改字段名。

### 情况 C：授权变更

每年检查一次上游 LICENSE。若从 CC BY-NC-SA 改成更严格的条款，本仓库需同步修改：
- `LICENSE`
- `NOTICE.md`
- README 的许可说明

## 三、我们自己的更新

在**当前仓库**上迭代即可，不需要碰上游：

| 想改什么 | 改哪里 |
|---|---|
| 台词 | `config/片段.json` + 本地 `main-config.jsonc` |
| 动作映射 | 同上 |
| 高清化参数 | `tools/upscale_pet.py` |
| 新增动作的高清版 | 单独跑 `upscale_pet.py`（可只处理指定文件） |

改完上传 GitHub，发新版 Release。
