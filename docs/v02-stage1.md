# SHIFT v0.2 — 第一阶段验收

在 Godot 中打开 project.godot，运行主场景 scenes/battle.tscn（F6 或 F5）。

## 当前行为

- 开场：双方 unarmed_idle；像素字体显示 Press Shift to Start；音乐未播放。
- 首次 Shift：开始音乐和第一轮，玩家轻剑、Boss 盾牌；这次按键不计入切换。
- 玩家序列：轻剑 → 盾 → 重剑。每轮最多接受一次切换，忽略长按重复事件。
- Boss 第一轮盾牌，以后每轮自动在轻剑、盾牌之间交替；Boss 使用基础数值。
- 音乐按提供的 130 BPM。每轮先等待一拍（约 0.461538 秒），此时隐藏游标且不消耗切换机会。第一拍落下显示第一格，第八拍落下显示第八格；每格持续一拍，八格显示阶段约 3.692308 秒。
- Normal：游标位于第 1–7 格时按键。Perfect：游标位于黄色第 8 格时按键，整格的一拍均有效。取消原 100ms 判定。
- 窗口之后按键显示 Miss，保留武器；整轮不按键也保留武器，不自动显示 Miss。
- 第 8 格结束时隐藏游标并立即结算双方伤害，播放行动动画。每轮共 11 拍：1 拍预备、8 拍格子显示、2 拍动作播放；音乐连续播放。下一轮再次从隐藏游标的预备阶段开始。
- 双方 7 点生命；移除 22 回合限制；一方归零结束，同时归零为 Draw。结局显示 Victory/Defeat/Draw 并停止音乐。

## 沿用和补充的规则

- 轻剑对非盾基础伤害 2；遇盾无伤害，自身反弹 1。
- 重剑先蓄力一轮，继续持有下一轮重击：基础伤害 5，对盾 3；切武器取消蓄力。
- Perfect 作用于成功切换后的武器。轻剑伤害 +1，遇盾时额外自伤 1；盾对轻剑的反弹 +1；重剑伤害 +1（对盾也 +1）。
- Perfect 重剑在蓄力时保存强化，供下一次重击使用，之后消耗；切武器丢弃保存的强化。轻剑/盾强化仅本轮生效。
- 盾对重剑沿用旧规则：减伤，不反弹。
- 音乐时钟使用播放位置、混音间隔和输出延迟补偿；默认文件起点为节拍网格起点，第一格显示在其后一拍。若实际音频前奏有偏移，可调整 Battle 的 beat_offset_seconds。
- 本阶段结束后通过重新运行场景开始下一次测试。

## 资源组织

- assets/fonts/monogram.ttf：当前像素字体，关闭抗锯齿/子像素定位，使用原生 16 号字形。逻辑画布提升到 160×120，美术按整数 2 倍显示，保持角色像素风和原窗口大小。
- assets/music/boss/：战斗音乐，保留作曲者原文件名。
- assets/character_related/player 和 boss：GIF 原素材、PNG 横向帧图及 sprite_frames.tres。
- 每帧画布 56×40；tools/export_character_animations.py 可重新导出 PNG 和 SpriteFrames。
- 角色 old 目录保存上一版素材，当前战斗不引用它们。
- assets/ui/healthbars/player 和 boss：当前使用的血条（从旧资源复制保留）。
- assets/ui/timeline_bar.png、timeline_cursor.png：当前八格时间轴及游标。
- 原倒计时图片等未使用资源保留，但不再接入战斗场景。

## 自动验证

在项目目录执行：

```powershell
godot --headless --path . --script res://tests/battle_rules_test.gd
godot --headless --path . --script res://tests/battle_scene_test.gd
```

230 项规则检查及 90 项场景检查通过，覆盖伤害矩阵、首拍前隐藏、八格拍点、最后一格整拍 Perfect、多轮精确边界、武器序列、蓄力、输入锁定和全部结局。
另外已执行真实音频播放时钟检查和渲染截图检查。

## 人工验收重点

1. 开场文字可读、双方徒手动画循环，首次 Shift 后音乐启动且初始武器正确。
2. 第一拍之前没有游标；第一拍显示第一格，第八拍显示黄色最后一格。第八格整拍都是 Perfect，格子结束时游标隐藏并结算。
3. 提前切换显示 Normal；窗口内切换显示 Perfect；迟到显示 Miss 且武器不变。
4. 连按/长按不会在同一轮反复切换，不按键不会强制换武器。
5. Perfect 盾反弹为 2；Perfect 重剑能在下一轮重击中生效；切走则取消蓄力强化。
6. 生命归零、同归于尽及音乐停止表现正确。
7. 听音乐人工确认第一拍偏移和输入手感；本阶段使用提供的 130 BPM，未修改音乐内容。

音频同步实现参考 Godot 官方说明：
https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html
