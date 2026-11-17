#!/usr/bin/env python3
"""Package only the current Nezha art revision and its local preview."""
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "data/nezha_art_v2.json").read_text())
paths = {manifest["portrait"], manifest["battle_master"]}
paths.update(sheet["path"] for sheet in manifest["sheets"].values())
paths.update([
    "data/nezha_art_v2.json", "data/nezha_art_generation.json", "docs/nezha_art_v2.md",
    "tools/measure_nezha_art.py", "tools/package_nezha_art.py",
    "previews/nezha/index.html", "previews/nezha/catalog.js", "previews/nezha/player.js",
    "previews/nezha/overview.png", "previews/nezha/check-samadhi.png",
    "previews/nezha/asset_check.json", "previews/nezha/preview_check.json",
    "previews/nezha/nezha_actions_v2.mp4",
    "assets/fonts/ShanheSerif.otf", "assets/battle/fortress_amber.webp",
])
assert not any("_v1" in path for path in paths)
out = ROOT / "deliverables/nezha_art_v2.zip"
out.parent.mkdir(parents=True, exist_ok=True)
readme = """哪吒美术资源 · 第二版（取消风火轮）

完整解压后，在解压目录执行 python3 -m http.server 8765，
浏览器访问 http://127.0.0.1:8765/previews/nezha/ 可播放、逐帧检查动作与特效。
视频：previews/nezha/nezha_actions_v2.mp4
当前立绘和战斗造型：assets/characters/nezha/*_v2.png
人物动作：assets/characters/nezha/animations/，共 42 帧。
独立特效：assets/characters/nezha/effects/，共 28 帧。
每帧取样区、脚底锚点、时长、事件、头像裁切区：data/nezha_art_v2.json
制作说明与接入状态：docs/nezha_art_v2.md

本包为独立的 2D 美术关键帧与预览资源，不包含完整游戏。
此套资源及灼烧规则已接入 Fenshen Godot 项目；实战请启动项目中的 project.godot。
请保留包内目录结构；预览所需图片、字体和脚本均在包内。
重新测量索引需要 Python、Pillow、NumPy；本地 HTML 预览需要任意静态文件服务器。
直接观看 MP4 无需启动服务器。
"""
with ZipFile(out, "w", compression=ZIP_DEFLATED, compresslevel=6) as z:
    z.writestr("README.txt", readme)
    for path in sorted(paths):
        assert (ROOT / path).is_file(), path
        z.write(ROOT / path, path)
with ZipFile(out) as z:
    assert z.testzip() is None
    assert all("_v1.png" not in name for name in z.namelist())
receipt = {"archive": str(out.relative_to(ROOT)), "bytes": out.stat().st_size,
           "sha256": hashlib.sha256(out.read_bytes()).hexdigest(), "entries": len(paths) + 1,
           "character_frames": 42, "effect_frames": 28, "revision": "no_wind_fire_wheels"}
(ROOT / "deliverables/nezha_art_v2_receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt))
