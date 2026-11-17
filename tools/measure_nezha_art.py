#!/usr/bin/env python3
"""Measure source PNG alpha and emit atlas metadata. Never modifies image pixels."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = "assets/characters/nezha/"
SHEETS = {
    "idle": ("animations/idle.png", 3, 2, 484, [500] * 6, None),
    "run": ("animations/run.png", 3, 2, 466, [481] * 6, [250, 247, 248, 248, 246, 250]),
    "attack": ("animations/attack.png", 3, 2, 449, [472] * 6, [240, 224, 228, 237, 225, 241]),
    "qiankun": ("animations/qiankun.png", 3, 2, 466, [488] * 6, None),
    "samadhi": ("animations/samadhi.png", 3, 2, 447, [481] * 6, [260, 255, 255, 250, 240, 260]),
    "fire_field": ("animations/fire_field.png", 3, 2, 462, [485] * 6, None),
    "recovery": ("animations/recovery.png", 3, 2, 471, [500, 500, 500, 464, 474, 474], [256, 264, 258, 256, 250, 256]),
    "combat_fx": ("effects/combat.png", 4, 4, 314, None, None),
    "samadhi_fx": ("effects/samadhi.png", 3, 2, 512, [395] * 6, [256] * 6),
    "fire_field_fx": ("effects/fire_field.png", 3, 2, 512, [296] * 6, [256] * 6),
}


def seam(alpha, around, radius, start, end, horizontal):
    scores = []
    for pos in range(max(1, around - radius), min(alpha.shape[0 if horizontal else 1] - 1, around + radius + 1)):
        line = alpha[pos, start:end] if horizontal else alpha[start:end, pos]
        scores.append((int((line >= 48).sum()) * 10000 + abs(pos - around), pos))
    return min(scores)[1]


def bounds(mask):
    ys, xs = np.where(mask)
    if not len(xs):
        raise ValueError("Empty animation frame")
    return [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]


def main():
    catalog = {"version": 2, "character": "nezha", "name": "哪吒", "revision": "无风火轮",
               "status": "runtime_integrated", "runtime_integrated": True,
               "portrait": BASE + "nezha_fullbody_v2.png",
               "battle_master": BASE + "nezha_battle_master_v2.png",
               "portrait_regions": {"map": [350, 112, 300, 360], "map_panel": [322, 100, 390, 315], "battle": [332, 112, 336, 420]},
               "sheets": {}, "clips": {}}
    report = {"source_images_modified": False, "alpha_edge_threshold": 160, "frames": 0, "warnings": [], "sheets": {}}
    for key, (path, cols, rows, body_height, grounds, roots) in SHEETS.items():
        image = Image.open(ROOT / BASE / path)
        assert image.mode == "RGBA", (path, image.mode)
        alpha = np.asarray(image)[:, :, 3]
        width, height = image.size
        cw, ch = width / cols, height / rows
        ys = [0] + [seam(alpha, round(r * ch), round(ch * .10), 0, width, True) for r in range(1, rows)] + [height]
        frames = []
        for row in range(rows):
            xs = [0] + [seam(alpha, round(c * cw), round(cw * .15), ys[row], ys[row + 1], False) for c in range(1, cols)] + [width]
            for col in range(cols):
                idx = row * cols + col
                x0, x1, y0, y1 = xs[col], xs[col + 1], ys[row], ys[row + 1]
                tile = alpha[y0:y1, x0:x1]
                visible = bounds(tile >= 48)
                solid = bounds(tile >= 160)
                if solid[0] < 1 or solid[1] < 1 or solid[0] + solid[2] >= tile.shape[1] or solid[1] + solid[3] >= tile.shape[0]:
                    report["warnings"].append(f"{key}:{idx}: solid pixels at frame edge")
                if key == "combat_fx":
                    px = col * cw + cw * .5
                    py = row * ch + ch * (.86 if row == 2 else .83 if row == 3 else .50)
                else:
                    py = row * ch + grounds[idx]
                    if roots:
                        px = col * cw + roots[idx]
                    else:
                        # Register planted boots, not the spear/ribbon-inclusive silhouette.
                        foot_y = min(height, round(py))
                        foot = alpha[max(y0, foot_y - 13):foot_y + 1, x0:x1]
                        fy, fx = np.where(foot >= 160)
                        px = x0 + float(fx.mean()) if len(fx) else col * cw + cw * .5
                frames.append({"source": [x0, y0, x1 - x0, y1 - y0],
                               "pivot": [round(px - x0, 2), round(py - y0, 2)],
                               "visible": visible, "solid": solid})
        catalog["sheets"][key] = {"path": BASE + path, "size": [width, height], "columns": cols, "rows": rows,
                                  "body_height": body_height, "facing": "right", "frames": frames}
        report["frames"] += len(frames)
        report["sheets"][key] = {"size": [width, height], "frames": len(frames),
                                   "fully_transparent_fraction": round(float((alpha == 0).mean()), 4)}
    specs = {
        "idle": ("待机", "idle", list(range(6)), [200] * 6, True, [], "平稳呼吸，红绫随身体轻动。"),
        "run": ("行走 / 奔跑", "run", list(range(6)), [90] * 6, True, [], "朝右奔跑循环，保持角色比例。"),
        "attack": ("火尖枪 · 连刺", "attack", list(range(6)), [100, 140, 90, 110, 120, 180], False,
                   [{"at_ms": 240, "event": "jab", "socket": [238, -290], "rotation": -0.05},
                    {"at_ms": 440, "event": "lift_strike", "socket": [214, -436], "rotation": -0.65}],
                   "短刺后接挑刺；每累计三次普攻命中叠加一层灼烧，最多三层。"),
        "qiankun": ("乾坤圈", "qiankun", list(range(6)), [140, 220, 160, 180, 160, 180], False,
                    [{"at_ms": 360, "event": "release_ring"}, {"at_ms": 860, "event": "catch_ring"}], "取圈、投出、回收；飞行的乾坤圈使用独立特效。"),
        "samadhi": ("三昧真火", "samadhi", list(range(6)), [160, 240, 220, 220, 200, 260], False,
                    [{"at_ms": 400, "event": "jump"}, {"at_ms": 840, "event": "lotus_impact"}], "蓄势跃起，以火尖枪落地引爆火莲。"),
        "fire_field": ("火莲焚阵", "fire_field", list(range(6)), [160, 220, 240, 220, 260, 260], False,
                       [{"at_ms": 620, "event": "cast_field"}], "立枪结印，指向目标；地面法阵与三道火柱独立播放。"),
        "hit": ("受击", "recovery", [0, 1, 2], [90, 120, 140], False, [], "小幅后仰，回到站立状态。"),
        "defeat": ("倒地", "recovery", [3, 4, 5], [220, 260, 600], False, [], "失衡、跪地、侧身倒下。末帧保持。"),
        "spear_fx": ("枪焰 / 命中", "combat_fx", [0, 1, 2, 3], [70, 70, 90, 120], False, [], "短火痕 → 命中碎光 → 火星消散。"),
        "ring_fx": ("乾坤圈飞行", "combat_fx", [4, 5, 6, 7], [75] * 4, True, [], "旋转圈体与短尾迹。"),
        "burn_fx": ("灼烧", "combat_fx", [8, 9, 10, 11], [150] * 4, True, [], "附着目标的局部火苗。"),
        "passive_fx": ("莲花化身", "combat_fx", [12, 13, 14, 15], [120, 160, 170, 200], False, [], "青白金莲瓣短暂护体。"),
        "samadhi_fx": ("三昧火莲特效", "samadhi_fx", list(range(6)), [140, 140, 140, 180, 180, 240], False, [], "法印、火蕾、绽放、爆发、碎瓣、余烬。"),
        "fire_field_fx": ("火莲阵特效", "fire_field_fx", list(range(6)), [180, 160, 160, 240, 200, 240], False, [], "法阵显形后，三道火柱错落升起并消退。"),
    }
    for key, (name, sheet, frames, durations, loop, events, description) in specs.items():
        catalog["clips"][key] = dict(name=name, sheet=sheet, frames=frames, durations_ms=durations,
                                     loop=loop, events=events, description=description)
    catalog["counts"] = {"character_frames": 42, "effect_frames": 28, "animation_sheets": 7, "effect_sheets": 3}
    (ROOT / "data/nezha_art_v2.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    (ROOT / "previews/nezha/catalog.js").write_text("window.NEZHA_ART = " + json.dumps(catalog, ensure_ascii=False) + ";\n")
    (ROOT / "previews/nezha/asset_check.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"frames": report["frames"], "warnings": report["warnings"], "images_modified": False}))
    if report["warnings"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
