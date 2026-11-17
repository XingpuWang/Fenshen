#!/usr/bin/env python3
"""Register v3 source atlases without changing any source image pixels."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

from measure_nezha_art import bounds, seam

ROOT = Path(__file__).resolve().parents[1]
BASE = "assets/characters/nezha/v3/"
TIMING = [65, 55, 55, 50, 45, 60, 45, 45, 45, 65, 50, 50, 55, 55, 45, 60]


def main():
    old = json.loads((ROOT / "data/nezha_art_v2.json").read_text())
    data = dict(version=3, character="nezha", name="哪吒", revision="独立暖色立绘 / Q版战斗 / 三头六臂", runtime_integrated=True,
                status="runtime_integrated", portrait=BASE + "portrait.png",
                battle_master=BASE + "actions.png", battle_master_frame=0,
                portrait_regions={"map": [374, 83, 265, 265], "map_panel": [328, 45, 370, 399], "battle": [324, 40, 390, 524]},
                sheets={}, clips={})
    report = dict(source_images_modified=False, warnings=[], sheets={})
    roots = [188, 188, 188, 182, 172, 170, 171, 176, 168, 170, 172, 176, 172, 188, 188, 188]
    for key, cols, rows, body_height in [("attack", 4, 4, 210), ("actions", 4, 6, 214), ("three_heads_fx", 4, 3, 286)]:
        path = BASE + key + ".png"
        im = Image.open(ROOT / path)
        assert im.mode == "RGBA", (key, im.mode)
        a = np.asarray(im)[:, :, 3]
        w, h = im.size
        cw, ch = w / cols, h / rows
        ys = [0] + [seam(a, round(r * ch), round(ch * .08), 0, w, True) for r in range(1, rows)] + [h]
        frames = []
        for row in range(rows):
            xs = [0] + [seam(a, round(c * cw), round(cw * .10), ys[row], ys[row + 1], False) for c in range(1, cols)] + [w]
            for col in range(cols):
                idx = row * cols + col
                x, y = xs[col], ys[row]
                tile = a[y:ys[row + 1], x:xs[col + 1]]
                visible, solid = bounds(tile >= 48), bounds(tile >= 160)
                if min(solid[:2]) < 1 or solid[0]+solid[2] >= tile.shape[1] or solid[1]+solid[3] >= tile.shape[0]:
                    report["warnings"].append(f"{key}:{idx}: solid edge")
                if key == "three_heads_fx":
                    px, py = col * cw + cw / 2, row * ch + ch * .90
                else:
                    # Feet registration removes tiny raster shifts without removing
                    # the drawn lean, recoil, step or collapsed defeat pose.
                    py = y + solid[1] + solid[3]
                    px = col * cw + (roots[idx] if key == "attack" else 140)
                    if key == "actions" and row == 3:
                        px = col * cw + [140, 140, 140, 142][col]
                frames.append(dict(source=[x,y,xs[col+1]-x,ys[row+1]-y], pivot=[round(px-x,2),round(py-y,2)], visible=visible, solid=solid))
        data["sheets"][key] = dict(path=path, size=[w,h], columns=cols, rows=rows, body_height=body_height, facing="right", frames=frames)
        report["sheets"][key] = dict(size=[w,h], frames=len(frames), fully_transparent_fraction=round(float((a==0).mean()),4), solid_bounds=[f["solid"] for f in frames])
    for key in ["combat_fx", "samadhi_fx", "fire_field_fx"]:
        data["sheets"][key] = old["sheets"][key]
    for key in ["spear_fx", "ring_fx", "burn_fx", "samadhi_fx", "fire_field_fx"]:
        data["clips"][key] = old["clips"][key]

    def clip(key, name, sheet, frames, times, loop=False, events=None, description=""):
        data["clips"][key] = dict(name=name, sheet=sheet, frames=frames, durations_ms=times, loop=loop, events=events or [], description=description)

    clip("idle", "待机", "actions", list(range(4)), [280,280,280,280], True)
    clip("run", "奔跑", "actions", list(range(4,8)), [100,100,100,100], True)
    clip("hit", "受击", "actions", list(range(8,12)), [65,85,95,105])
    clip("defeat", "倒地", "actions", list(range(12,16)), [180,220,260,420])
    clip("qiankun", "乾坤圈", "actions", list(range(16,20)), [180,180,500,180], events=[{"at_ms":360,"event":"release_ring"},{"at_ms":860,"event":"catch_ring"}])
    clip("samadhi", "三昧真火", "actions", list(range(20,24)), [400,440,200,260], events=[{"at_ms":840,"event":"lotus_impact"}])
    clip("fire_field", "火莲焚阵", "actions", list(range(20,24)), [300,320,480,260], events=[{"at_ms":620,"event":"cast_field"}])
    events = [{"at_ms":sum(TIMING[:i]),"event":"jab" if i==5 else "second_jab","socket":[.84,-.58],"rotation":-.02} for i in [5,9]]
    clip("attack", "火尖枪 · 连刺", "attack", list(range(16)), TIMING, events=events, description="16帧双段连刺，每段命中触发三头六臂溅射；每累计三次命中叠加一层灼烧。")
    clip("three_heads_fx", "三头六臂", "three_heads_fx", list(range(12)), [65,65,65,75,75,75,75,75,65,65,65,65], description="金色三首六臂法相在角色背后显现、出击、碎瓣消散；角色与特效分层。")
    data["counts"] = dict(character_frames=40, effect_frames=36, animation_sheets=2, effect_sheets=4, sampled_clip_frames=sum(len(c["frames"]) for c in data["clips"].values()))
    (ROOT / "data/nezha_art_v3.json").write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
    out = ROOT / "previews/nezha/v3"
    out.mkdir(parents=True,exist_ok=True)
    (out / "asset-check.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps(report,ensure_ascii=False))
    assert not report["warnings"], report["warnings"]


if __name__ == "__main__":
    main()
