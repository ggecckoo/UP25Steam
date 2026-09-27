#!/usr/bin/env python3
"""Send the six approved portraits to Meshy, then rig the textured models.

The API key is read from the gitignored .env file. Task ids are stored in
art/karakterler/3d/meshy-tasks.json so a second run resumes instead of
spending the credits again.
"""

import base64
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art" / "karakterler"
OUT = ART / "3d"
GODOT = ROOT / "godot" / "assets" / "characters"
STATE = OUT / "meshy-tasks.json"
NAMES = ["kaya", "sis", "kok", "nida", "kul", "dere"]
API = "https://api.meshy.ai/openapi/v1"


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
    return {"images": {}, "rigs": {}}


def save_state(state):
    OUT.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def portrait_uri(name):
    blob = (ART / f"{name}-portre.png").read_bytes()
    return "data:image/png;base64," + base64.b64encode(blob).decode("ascii")


def create_image(key, name):
    status, payload = request(key, "POST", "/image-to-3d", {
        "image_url": portrait_uri(name),
        "ai_model": "latest",
        "should_texture": True,
        "enable_pbr": True,
        "should_remesh": True,
        "topology": "triangle",
        "target_polycount": 25000,
        "pose_mode": "a-pose",
        "image_enhancement": False,
        "target_formats": ["glb"],
    })
    if status not in (200, 202):
        raise SystemExit(f"image {name} failed {status} {payload.get('message', payload)}")
    task_id = payload.get("result") or payload.get("id")
    if not task_id:
        raise SystemExit(f"image {name} returned no id")
    print(f"image {name} {task_id}", flush=True)
    return task_id


def create_rig(key, name, image_id):
    status, payload = request(key, "POST", "/rigging", {
        "input_task_id": image_id,
        "height_meters": 1.5,
    })
    if status not in (200, 202):
        print(f"rig {name} failed {status} {payload.get('message', payload)}", flush=True)
        return ""
    task_id = payload.get("result") or payload.get("id")
    print(f"rig {name} {task_id}", flush=True)
    return task_id or ""


def poll(key, kind, task_id):
    path = "/image-to-3d/" if kind == "image" else "/rigging/"
    while True:
        status, payload = request(key, "GET", path + task_id)
        if status == 429:
            print(f"wait {kind} {task_id} rate limit", flush=True)
            time.sleep(8)
            continue
        if status != 200:
            return {"status": "FAILED", "task_error": {"message": f"http {status}"}}
        state = payload.get("status", "")
        progress = payload.get("progress", 0)
        print(f"{kind} {task_id} {state} {progress}", flush=True)
        if state in ("SUCCEEDED", "FAILED", "CANCELED"):
            return payload
        time.sleep(8)


def download(url, path):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=180) as resp:
        path.write_bytes(resp.read())


def main(names=None):
    names = list(names or NAMES)
    key = load_key()
    state = load_state()
    for name in names:
        if name not in state["images"]:
            state["images"][name] = {"id": create_image(key, name)}
            save_state(state)
            time.sleep(1)

    pending = [
        name for name in names
        if "result" not in state["images"][name] and "error" not in state["images"][name]
    ]
    while pending:
        still = []
        for name in pending:
            payload = poll(key, "image", state["images"][name]["id"])
            if payload.get("status") == "SUCCEEDED":
                state["images"][name]["result"] = {
                    "glb": (payload.get("model_urls") or {}).get("glb", ""),
                    "thumbnail": payload.get("thumbnail_url", ""),
                }
                save_state(state)
            elif payload.get("status") in ("FAILED", "CANCELED"):
                message = (payload.get("task_error") or {}).get("message", payload.get("status"))
                state["images"][name]["error"] = message
                save_state(state)
                print(f"image {name} error {message}", flush=True)
            else:
                still.append(name)
        pending = still

    for name in names:
        image = state["images"][name]
        if image.get("error") or not image.get("result", {}).get("glb"):
            continue
        if name not in state["rigs"]:
            rig_id = create_rig(key, name, image["id"])
            state["rigs"][name] = {"id": rig_id} if rig_id else {"error": "create failed"}
            save_state(state)
            time.sleep(1)

    rig_pending = [
        name for name in names
        if state["rigs"].get(name, {}).get("id") and "result" not in state["rigs"][name] and "error" not in state["rigs"][name]
    ]
    while rig_pending:
        still = []
        for name in rig_pending:
            payload = poll(key, "rig", state["rigs"][name]["id"])
            if payload.get("status") == "SUCCEEDED":
                result = payload.get("result") or {}
                state["rigs"][name]["result"] = {
                    "glb": result.get("rigged_character_glb_url", ""),
                    "fbx": result.get("rigged_character_fbx_url", ""),
                }
                save_state(state)
            elif payload.get("status") in ("FAILED", "CANCELED"):
                message = (payload.get("task_error") or {}).get("message", payload.get("status"))
                state["rigs"][name]["error"] = message
                save_state(state)
                print(f"rig {name} error {message}", flush=True)
            else:
                still.append(name)
        rig_pending = still

    OUT.mkdir(parents=True, exist_ok=True)
    GODOT.mkdir(parents=True, exist_ok=True)
    for name in names:
        image = state["images"].get(name, {})
        thumb = (image.get("result") or {}).get("thumbnail")
        if thumb:
            download(thumb, OUT / f"{name}-meshy.png")
        mesh = (image.get("result") or {}).get("glb")
        if mesh:
            download(mesh, OUT / f"{name}-mesh.glb")
        rig = (state["rigs"].get(name, {}).get("result") or {}).get("glb")
        if rig:
            path = OUT / f"{name}.glb"
            download(rig, path)
            (GODOT / f"{name}.glb").write_bytes(path.read_bytes())
            print(f"saved {name} {path.stat().st_size}", flush=True)
        else:
            print(f"missing rig {name}", flush=True)
    print("MESHY_DONE", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:] or None)
