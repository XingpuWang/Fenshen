#!/usr/bin/env python3
"""Measure the live Nezha actor and effect atlases without editing image pixels."""
import copy
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from measure_nezha_art import bounds, seam

ROOT = Path(__file__).resolve().parents[1]
BASE = "assets/characters/nezha/v4/"
ACTOR_BASE = "assets/characters/nezha/v5/"
ROOTS = {
    "qiankun": [201,202,202,195,195,194,190,184,181,181,184,186,188,192,198,201],
    "samadhi": [200,192,185,180,185,187,189,190,190,186,181,181,181,185,191,199],
}


def main():
    data = copy.deepcopy(json.loads((ROOT / "data/nezha_art_v3.json").read_text()))
    data.update(version=4, revision="战斗小人重绘 / 火尖枪双段连刺 / 乾坤圈与三昧真火16帧",
                battle_master=ACTOR_BASE + "battle_master.png", battle_master_frame=None)
    report = {"source_images_modified": False, "warnings": [], "sheets": {}}
    for key in ["actions", "attack", "qiankun", "samadhi", "ring_fx", "samadhi_fx"]:
        path = (ACTOR_BASE if key in ("attack", "actions") else BASE) + key + ".png"
        raw = (ROOT / path).read_bytes()
        image = Image.open(ROOT / path)
        assert image.mode == "RGBA", key
        pixels = np.asarray(image)
        alpha = pixels[:, :, 3]
        w, h = image.size
        cw, ch = w / 4, h / 4
        assert float((alpha == 0).mean()) > (.001 if key.endswith("_fx") else .4), key
        ys = [0] + [seam(alpha, round(r * ch), round(ch * .08), 0, w, True) for r in range(1, 4)] + [h]
        frames = []
        fingerprints = []
        for row in range(4):
            xs = [0] + [seam(alpha, round(c * cw), round(cw * .08), ys[row], ys[row+1], False) for c in range(1, 4)] + [w]
            for col in range(4):
                idx = row * 4 + col
                x, y = xs[col], ys[row]
                tile = alpha[y:ys[row+1], x:xs[col+1]]
                visible, solid = bounds(tile >= 48), bounds(tile >= 160)
                if min(solid[:2]) < 1 or solid[0]+solid[2] >= tile.shape[1] or solid[1]+solid[3] >= tile.shape[0]:
                    report["warnings"].append(f"{key}:{idx}: solid pixels at frame edge")
                if key in ("attack", "actions"):
                    # The new drawings are registered to one ground root, including
                    # the airborne stride. A silhouette centroid would follow the spear.
                    px, py = col*cw + 220, row*ch + 250
                elif key.endswith("_fx"):
                    px = col*cw + cw*(.60 if key == "ring_fx" else .50)
                    py = row*ch + ch*(.51 if key == "ring_fx" else .87)
                else:
                    py = y + solid[1] + solid[3]
                    px = col*cw + ROOTS[key][idx]
                frames.append({"source": [x,y,xs[col+1]-x,ys[row+1]-y],
                               "pivot": [round(px-x,2),round(py-y,2)], "visible":visible,"solid":solid})
                fingerprints.append(hashlib.sha256(pixels[y:ys[row+1],x:xs[col+1]].tobytes()).hexdigest())
        assert len(set(fingerprints)) == 16, (key, "repeated source frames")
        body_height = (256 if key == "ring_fx" else ch) if key.endswith("_fx") else 240
        data["sheets"][key] = dict(path=path,size=[w,h],columns=4,rows=4,body_height=body_height,facing="right",frames=frames)
        report["sheets"][key] = dict(size=[w,h],frames=16,unique_frames=len(set(fingerprints)),
                                     fully_transparent_fraction=round(float((alpha==0).mean()),4),sha256=hashlib.sha256(raw).hexdigest())

    def clip(key, sheet, times, events, description, loop=False):
        data["clips"][key].update(sheet=sheet,frames=list(range(16)),durations_ms=times,
                                 events=events,description=description,loop=loop)

    # Measured at the painted red-gold tips on drawings six and ten.
    clip("attack","attack",data["clips"]["attack"]["durations_ms"],
         [{"at_ms":270,"event":"jab","socket":[0.846,-0.562],"rotation":-0.079},
          {"at_ms":465,"event":"second_jab","socket":[0.842,-0.562],"rotation":-0.053}],
         "16帧提枪、探步、双刺与收势，乾坤圈随双手持枪扣于腰侧，红绫随第二刺回落。")
    clip("qiankun","qiankun",[60]*6+[55,60,65,70,80,80,90,60,60,60],
         [{"at_ms":360,"event":"release_ring"},{"at_ms":610,"event":"ring_impact"},{"at_ms":860,"event":"catch_ring"}],
         "16帧蓄势、掷圈、随势、接圈；独立16帧金圈与赤金拖尾随真实飞行往返。")
    clip("samadhi","samadhi",[70]*12+[90,100,120,150],
         [{"at_ms":420,"event":"lotus_windup"},{"at_ms":840,"event":"lotus_impact"}],
         "16帧抬枪、引火、指向爆发、收势；火莲在0.84秒与实际伤害同时爆发。")
    clip("fire_field","samadhi",[50]*10+[60,60,150,180,210,200],
         [{"at_ms":620,"event":"cast_field"}],"复用修长比例施法动作，大地图火阵仍在0.62秒释放。")
    # The twelve apparition drawings are registered to the rear shoulder.
    # Even the nearly transparent arrival and departure frames have measured bounds.
    path = "assets/battle/hero_fx/three_heads.png"
    with Image.open(ROOT / path) as image:
        alpha = np.asarray(image.getchannel("A"))
        width, height = image.size
    cw, ch = width // 4, height // 3
    frames = []
    for index in range(12):
        x, y = index % 4 * cw, index // 4 * ch
        tile = alpha[y:y + ch, x:x + cw]
        frames.append({"source": [x,y,cw,ch], "pivot": [192,341],
                       "visible": bounds(tile >= 24), "solid": bounds(tile >= 40)})
    data["sheets"]["three_heads_fx"] = dict(path=path, size=[width,height], columns=4, rows=3,
                                         body_height=320, facing="right", frames=frames)
    data["clips"]["three_heads_fx"].update(durations_ms=[60,60,75,75,60,60,75,70,65,65,80,85],
        description="三首六臂法相自后肩凝形，随0.27秒、0.465秒两次枪击展臂，随后化为金线与落瓣。")
    clip("ring_fx","ring_fx",[31.25]*16,[],"16帧乾坤圈旋转和火焰拖尾，完整覆盖0.5秒的往返飞行。")
    clip("samadhi_fx","samadhi_fx",[70]*12+[80,100,120,140],
         [{"at_ms":420,"event":"lotus_burst"}],"16帧法印、火蕾、火莲爆发、碎瓣、余烬；分层绘制，爆发对齐命中。")
    data["counts"] = dict(character_frames=64,effect_frames=66,animation_sheets=4,effect_sheets=5,
                          sampled_clip_frames=sum(len(c["frames"]) for c in data["clips"].values()))
    (ROOT / "data/nezha_art_v4.json").write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
    (ROOT / "previews/nezha/v4/asset-check.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({"warnings":report["warnings"],"sheets":len(report["sheets"]),"clip_frames":data["counts"]["sampled_clip_frames"]},ensure_ascii=False))
    assert not report["warnings"],report["warnings"]


if __name__ == "__main__": main()
