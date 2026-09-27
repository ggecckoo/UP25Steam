#!/usr/bin/env python3
"""Turn the approved table-room image into a textured Meshy model.

No rig. Task id is stored beside the model so a second run does not spend
the credits again. The API key stays in the gitignored .env file.
"""

import base64
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / "art" / "sahneler" / "06-masa-oda-acik.png"
OUT = ROOT / "art" / "sahneler" / "3d"
GODOT = ROOT / "godot" / "assets" / "room"
STATE = OUT / "meshy-room.json"
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
    return {}


def save_state(state):
    OUT.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def image_uri():
    blob = IMAGE.read_bytes()
    return "data:image/png;base64," + base64.b64encode(blob).decode("ascii")


def create(key):
    status, payload = request(key, "POST", "/image-to-3d", {
        "image_url": image_uri(),
        "ai_model": "latest",
        "should_texture": True,
        "enable_pbr": True,
        "should_remesh": True,
        "topology": "triangle",
        "target_polycount": 80000,
        "symmetry_mode": "off",
        "image_enhancement": False,
        "target_formats": ["glb"],
    })
    if status not in (200, 202):
        raise SystemExit(f"room failed {status} {payload.get('message', payload)}")
    task_id = payload.get("result") or payload.get("id")
    if not task_id:
        raise SystemExit("room returned no id")
    print(f"room {task_id}", flush=True)
    return task_id


def poll(key, task_id):
    while True:
        status, payload = request(key, "GET", "/image-to-3d/" + task_id)
        if status == 429:
            print("wait room rate limit", flush=True)
            time.sleep(8)
            continue
        if status != 200:
            return {"status": "FAILED", "task_error": {"message": f"http {status}"}}
        state = payload.get("status", "")
        print(f"room {task_id} {state} {payload.get('progress', 0)}", flush=True)
        if state in ("SUCCEEDED", "FAILED", "CANCELED"):
            return payload
        time.sleep(8)


def download(url, path):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=180) as resp:
        path.write_bytes(resp.read())
    print(f"saved {path.name} {path.stat().st_size}", flush=True)


def main():
    key = load_key()
    state = load_state()
    if not state.get("id"):
        state = {"id": create(key)}
        save_state(state)
    if "result" not in state and "error" not in state:
        payload = poll(key, state["id"])
        if payload.get("status") == "SUCCEEDED":
            state["result"] = {
                "glb": (payload.get("model_urls") or {}).get("glb", ""),
                "thumbnail": payload.get("thumbnail_url", ""),
            }
        else:
            message = (payload.get("task_error") or {}).get("message", payload.get("status"))
            state["error"] = message
            print(f"room error {message}", flush=True)
        save_state(state)
    if state.get("error"):
        raise SystemExit("room failed")
    OUT.mkdir(parents=True, exist_ok=True)
    GODOT.mkdir(parents=True, exist_ok=True)
    result = state["result"]
    if result.get("thumbnail"):
        download(result["thumbnail"], OUT / "masa-oda-meshy.png")
    path = OUT / "masa-oda.glb"
    download(result["glb"], path)
    (GODOT / "masa-oda.glb").write_bytes(path.read_bytes())
    print("ROOM_DONE", flush=True)


if __name__ == "__main__":
    main()
