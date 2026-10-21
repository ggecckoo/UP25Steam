#!/usr/bin/env python3
"""Make the fox croupier with Meshy: a text-to-3D preview, then (once the
preview has been looked at) the textured refine and the humanoid rig.

    python3 tools/meshy_croupier.py preview   # untextured draft + thumbnail
    python3 tools/meshy_croupier.py refine    # texture the accepted draft
    python3 tools/meshy_croupier.py rig       # rig it, write godot/assets/characters/tilki.glb

The API key is read from the gitignored .env file. Task ids are kept in
art/karakterler/3d/meshy-croupier.json, so a step run twice resumes instead
of spending the credits again.
"""

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art" / "karakterler" / "3d"
GODOT = ROOT / "godot" / "assets" / "characters"
STATE = OUT / "meshy-croupier.json"
API = "https://api.meshy.ai/openapi"
NAME = "tilki"

PROMPT = (
    "A slim anthropomorphic red fox croupier standing upright on two legs, tall and thin, "
    "long elegant snout, bright orange fur with a white chest, white muzzle and white tail tip, "
    "amber eyes, wearing an ivory dress shirt with brass sleeve garters, a bottle green waistcoat "
    "with brass buttons, a burgundy bow tie and warm tan trousers, slender furry hands, bushy tail, "
    "realistic fur, painterly realistic style"
)
TEXTURE = (
    "bright orange red fox fur, white chest and muzzle, ivory cotton shirt, bottle green wool "
    "waistcoat with brass buttons, burgundy silk bow tie, warm tan trousers, painterly realistic"
)


def load_key():
    for line in (ROOT / ".env").read_text().splitlines():
        if line.startswith("MESHY_API_KEY="):
            key = line.split("=", 1)[1].strip().strip('"').strip("'")
            if key.startswith("msy_") and len(key) > 20:
                return key
    raise SystemExit("MESHY_API_KEY missing in .env")


def request(key, method, path, body=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(detail)
        except json.JSONDecodeError:
            parsed = {"message": detail[:400]}
        return exc.code, parsed


def load_state():
    if STATE.exists():
        return json.loads(STATE.read_text())
    return {}


def save_state(state):
    OUT.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def poll(key, path):
    while True:
        status, payload = request(key, "GET", path)
        if status == 429:
            time.sleep(8)
            continue
        if status != 200:
            return {"status": "FAILED", "task_error": {"message": f"http {status} {payload}"}}
        state = payload.get("status", "")
        print(f"{path} {state} {payload.get('progress', 0)}", flush=True)
        if state in ("SUCCEEDED", "FAILED", "CANCELED"):
            return payload
        time.sleep(10)


def download(url, path):
    with urllib.request.urlopen(urllib.request.Request(url), timeout=300) as resp:
        path.write_bytes(resp.read())
    print(f"saved {path} {path.stat().st_size}", flush=True)


def start(key, state, step, path, body):
    if step not in state:
        status, payload = request(key, "POST", path, body)
        if status not in (200, 202):
            raise SystemExit(f"{step} failed {status} {payload.get('message', payload)}")
        state[step] = {"id": payload.get("result") or payload.get("id")}
        save_state(state)
        print(f"{step} {state[step]['id']}", flush=True)
    return state[step]["id"]


def preview(key, state):
    task = start(key, state, "preview", "/v2/text-to-3d", {
        "mode": "preview",
        "prompt": PROMPT,
        "art_style": "realistic",
        "ai_model": "latest",
        "topology": "triangle",
        "target_polycount": 25000,
        "should_remesh": True,
        "symmetry_mode": "auto",
        "pose_mode": "a-pose",
    })
    payload = poll(key, f"/v2/text-to-3d/{task}")
    if payload.get("status") != "SUCCEEDED":
        raise SystemExit(f"preview {payload.get('task_error')}")
    state["preview"]["thumbnail"] = payload.get("thumbnail_url", "")
    save_state(state)
    if state["preview"]["thumbnail"]:
        download(state["preview"]["thumbnail"], OUT / f"{NAME}-preview.png")
    glb = (payload.get("model_urls") or {}).get("glb")
    if glb:
        download(glb, OUT / f"{NAME}-preview.glb")


def refine(key, state):
    task = start(key, state, "refine", "/v2/text-to-3d", {
        "mode": "refine",
        "preview_task_id": state["preview"]["id"],
        "enable_pbr": True,
        "texture_prompt": TEXTURE,
        "ai_model": "latest",
    })
    payload = poll(key, f"/v2/text-to-3d/{task}")
    if payload.get("status") != "SUCCEEDED":
        raise SystemExit(f"refine {payload.get('task_error')}")
    if payload.get("thumbnail_url"):
        download(payload["thumbnail_url"], OUT / f"{NAME}-meshy.png")
    glb = (payload.get("model_urls") or {}).get("glb")
    if glb:
        download(glb, OUT / f"{NAME}-mesh.glb")


def rig(key, state):
    task = start(key, state, "rig", "/v1/rigging", {
        "input_task_id": state["refine"]["id"],
        "height_meters": 1.6,
    })
    payload = poll(key, f"/v1/rigging/{task}")
    if payload.get("status") != "SUCCEEDED":
        raise SystemExit(f"rig {payload.get('task_error')}")
    glb = (payload.get("result") or {}).get("rigged_character_glb_url")
    if not glb:
        raise SystemExit("rig returned no glb")
    path = OUT / f"{NAME}.glb"
    download(glb, path)
    GODOT.mkdir(parents=True, exist_ok=True)
    (GODOT / f"{NAME}.glb").write_bytes(path.read_bytes())
    print("MESHY_DONE", flush=True)


def main():
    step = sys.argv[1] if len(sys.argv) > 1 else "preview"
    key = load_key()
    state = load_state()
    {"preview": preview, "refine": refine, "rig": rig}[step](key, state)


if __name__ == "__main__":
    main()
