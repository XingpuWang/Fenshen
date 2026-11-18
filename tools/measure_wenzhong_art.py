#!/usr/bin/env python3
"""Measure source atlas alpha and register animation; never edits image pixels."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from measure_nezha_art import bounds, seam

ROOT = Path(__file__).resolve().parents[1]
BASE = "assets/characters/wenzhong/v1/"
OUT = ROOT / "previews/wenzhong/v1"
SHEETS = ["actions", "attack", "thunder_whip", "nine_thunders",
          "attack_fx", "thunder_whip_fx", "nine_thunders_fx", "thunder_seal_fx"]
# Crown-to-sole scale of the resting guard, independent of the height of a raised baton.
BODY_HEIGHT = {"actions": 262, "attack": 360, "thunder_whip": 240, "nine_thunders": 246}


def main():
    data = dict(version=1, character="wenzhong", name="闻仲", status="runtime_integrated",
                portrait=BASE+"portrait.png", battle_master=BASE+"battle_master.png",
                portrait_regions={"map": [468, 90, 250, 250],
                                  "map_panel": [348, 35, 440, 488],
                                  "battle": [348, 35, 440, 590]}, sheets={}, clips={})
    report = {"source_images_modified": False, "warnings": [], "sheets": {}}
    for key in SHEETS:
        path = BASE+key+".png"
        raw = (ROOT/path).read_bytes()
        im = Image.open(ROOT/path)
        assert im.mode == "RGBA", key
        pixels = np.asarray(im)
        alpha = pixels[:, :, 3]
        w, h = im.size
        cw, ch = w/4, h/4
        transparent = float((alpha == 0).mean())
        assert transparent > (.001 if key.endswith("_fx") else .4), (key, transparent)
        ys = [0]+[seam(alpha, round(r*ch), round(ch*.06), 0, w, True) for r in range(1, 4)]+[h]
        frames, hashes = [], []
        for row in range(4):
            xs = [0]+[seam(alpha, round(c*cw), round(cw*.06), ys[row], ys[row+1], False) for c in range(1, 4)]+[w]
            for col in range(4):
                x, y = xs[col], ys[row]
                tile = alpha[y:ys[row+1], x:xs[col+1]]
                # Late electric embers are intentionally translucent throughout.
                threshold = min(160, int(tile.max()*.8)) if key.endswith("_fx") else 160
                visible, solid = bounds(tile >= 48), bounds(tile >= threshold)
                if min(solid[:2]) < 1 or solid[0]+solid[2] >= tile.shape[1] or solid[1]+solid[3] >= tile.shape[0]:
                    report["warnings"].append(f"{key}:{row*4+col}: solid pixels at tile edge")
                if key.endswith("_fx"):
                    px = col*cw+cw*.5
                    py = row*ch+ch*(.5 if key == "attack_fx" else .84)
                else:
                    sole = solid[1] + solid[3]
                    py = y + sole
                    if key == "actions":
                        # Running alternates the planted leg. Keep the body on one axis
                        # and register the passing poses to the ground under the stride.
                        px = col*cw + 200
                        if row == 1: py = y + 262
                    else:
                        # Both boots remain planted through the swings. Their midpoint
                        # follows the stance without drifting toward hair, cape or weapons.
                        boots = np.flatnonzero((tile[max(0, sole-round(ch*.06)):sole] >= 160).any(axis=0))
                        px = x + (int(boots[0])+int(boots[-1]))*.5
                frames.append(dict(source=[x,y,xs[col+1]-x,ys[row+1]-y],
                                   pivot=[round(px-x,2),round(py-y,2)], visible=visible, solid=solid))
                hashes.append(hashlib.sha256(pixels[y:ys[row+1], x:xs[col+1]].tobytes()).hexdigest())
        assert len(set(hashes)) == 16, (key, "repeated frames")
        data["sheets"][key] = dict(path=path, size=[w,h], columns=4, rows=4,
                                   body_height=BODY_HEIGHT.get(key, ch),
                                   facing="right", frames=frames)
        report["sheets"][key] = dict(size=[w,h], frames=16, unique_frames=16,
                                     fully_transparent_fraction=round(transparent,4),
                                     sha256=hashlib.sha256(raw).hexdigest())

    def clip(key, sheet, durations, events=(), frames=None, loop=False):
        data["clips"][key] = dict(sheet=sheet, frames=list(range(16)) if frames is None else frames,
                                  durations_ms=durations, events=list(events), loop=loop)

    clip("idle", "actions", [250]*4, frames=[0,1,2,3], loop=True)
    clip("run", "actions", [100]*4, frames=[4,5,6,7], loop=True)
    clip("hit", "actions", [80]*4, frames=[8,9,10,11])
    clip("defeat", "actions", [180,180,180,600], frames=[12,13,14,15])
    clip("attack", "attack", [40]*12+[50]*4,
         [{"at_ms":160,"event":"arc_start"},{"at_ms":320,"event":"impact"}])
    clip("thunder_whip", "thunder_whip", [105]*10+[80,80,90,90,100,110],
         [{"at_ms":550,"event":"charge_start"},{"at_ms":1050,"event":"impact"}])
    clip("nine_thunders", "nine_thunders", [130]*10+[80,80,90,90,100,110],
         [{"at_ms":600,"event":"charge_start"},{"at_ms":1300,"event":"impact"}])
    clip("thunder_seal", "nine_thunders", [62]*10+[90,100,110,130,150,160],
         [{"at_ms":620,"event":"release"},{"at_ms":1120,"event":"impact"}])
    clip("attack_fx", "attack_fx", [40]*4+[30]*12, [{"at_ms":160,"event":"impact"}])
    clip("thunder_whip_fx", "thunder_whip_fx", [62.5]*8+[80]*8, [{"at_ms":500,"event":"impact"}])
    clip("nine_thunders_fx", "nine_thunders_fx", [87.5]*8+[100]*6+[120,140], [{"at_ms":700,"event":"impact"}])
    clip("thunder_seal_fx", "thunder_seal_fx", [62.5]*8+[90]*8, [{"at_ms":500,"event":"impact"}])
    data["counts"] = dict(character_frames=64, effect_frames=64, animation_sheets=4, effect_sheets=4,
                          sampled_clip_frames=sum(len(c["frames"]) for c in data["clips"].values()))
    OUT.mkdir(parents=True,exist_ok=True)
    (ROOT/"data/wenzhong_art_v1.json").write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
    (OUT/"asset-check.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({"warnings":report["warnings"],"sheets":len(SHEETS),"sampled_frames":data["counts"]["sampled_clip_frames"]}))
    assert not report["warnings"], report["warnings"]


if __name__ == "__main__": main()
