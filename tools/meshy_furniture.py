#!/usr/bin/env python3
"""Build the approved card room's table, chair, and lamp with Meshy.

A full-room photo comes back as a flat cutout, so each piece is a textured
object. Task ids are stored so a second run does not spend the credits again.
"""

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art" / "sahneler" / "3d"
GODOT = ROOT / "godot" / "assets" / "room"
STATE = OUT / "meshy-furniture.json"
API = "https://api.meshy.ai/openapi/v2"
NAMES = ["masa", "sandalye", "lamba"]
PROMPTS = {
    "masa": (
        "A round game-ready card table, thick dark walnut rim and apron, "
        "deep green wool felt top, one thin brass inlay ring inside the rim, "
        "solid wooden base, realistic wood grain, no chairs, no people"
    ),
    "sandalye": (
        "A dark oak dining chair, curved top rail, three vertical wooden slats, "
        "solid wood seat, four straight legs, realistic wood grain, "
        "game-ready, no cushion, no people"
    ),
    "lamba": (
        "A hanging brass dome pendant lamp, wide shallow metal shade, "
        "short stem and small ceiling canopy, warm aged brass, "
        "realistic, game-ready, no people"
    ),
}


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
    return {"preview": {}, "refine": {}}


def save_state(state):
    OUT.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def create_preview(key, name):
    status, payload = request(key, "POST", "/text-to-3d", {
        "mode": "preview",
        "prompt": PROMPTS[name],
        "ai_model": "latest",
        "topology": "triangle",
        "target_polycount": 30000 if name == "masa" else 15000,
        "should_remesh": True,
    })
    if status not in (200, 202):
        print(f"preview {name} failed {status} {payload.get('message', payload)}", flush=True)
        return ""
    task_id = payload.get("result") or payload.get("id") or ""
    print(f"preview {name} {task_id}", flush=True)
    return task_id


def create_refine(key, name, preview_id):
    status, payload = request(key, "POST", "/text-to-3d", {
        "mode": "refine",
        "preview_task_id": preview_id,
        "enable_pbr": True,
        "ai_model": "latest",
        "target_formats": ["glb"],
    })
    if status not in (200, 202):
        print(f"refine {name} failed {status} {payload.get('message', payload)}", flush=True)
        return ""
    task_id = payload.get("result") or payload.get("id") or ""
    print(f"refine {name} {task_id}", flush=True)
    return task_id


def poll_once(key, task_id):
    status, payload = request(key, "GET", "/text-to-3d/" + task_id)
    if status == 429:
        print(f"wait {task_id} rate limit", flush=True)
        return {"status": "PENDING"}
    if status != 200:
        return {"status": "FAILED", "task_error": {"message": f"http {status}"}}
    print(f"task {task_id} {payload.get('status', '')} {payload.get('progress', 0)}", flush=True)
    return payload


def download(url, path):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=180) as resp:
        path.write_bytes(resp.read())
    print(f"saved {path.name} {path.stat().st_size}", flush=True)


def wait_group(key, state, group):
    pending = [
        name for name in NAMES
        if state[group].get(name, {}).get("id")
        and "result" not in state[group][name]
        and "error" not in state[group][name]
    ]
    while pending:
        still = []
        for name in pending:
            payload = poll_once(key, state[group][name]["id"])
            status = payload.get("status", "")
            if status == "SUCCEEDED":
                state[group][name]["result"] = {
                    "glb": (payload.get("model_urls") or {}).get("glb", ""),
                    "thumbnail": payload.get("thumbnail_url", ""),
                }
                save_state(state)
            elif status in ("FAILED", "CANCELED"):
                message = (payload.get("task_error") or {}).get("message", status)
                state[group][name]["error"] = message
                save_state(state)
                print(f"{group} {name} error {message}", flush=True)
            else:
                still.append(name)
        pending = still
        if pending:
            time.sleep(8)


def main():
    key = load_key()
    state = load_state()
    state.setdefault("preview", {})
    state.setdefault("refine", {})
    for name in NAMES:
        if state["preview"].get(name, {}).get("id"):
            continue
        task_id = create_preview(key, name)
        state["preview"][name] = {"id": task_id} if task_id else {"error": "create failed"}
        save_state(state)
        time.sleep(1.2)
    wait_group(key, state, "preview")
    for name in NAMES:
        if state["refine"].get(name, {}).get("id") or state["refine"].get(name, {}).get("error"):
            continue
        preview = state["preview"].get(name, {})
        if preview.get("error") or not preview.get("id"):
            state["refine"][name] = {"error": "no preview"}
            save_state(state)
            continue
        task_id = create_refine(key, name, preview["id"])
        state["refine"][name] = {"id": task_id} if task_id else {"error": "create failed"}
        save_state(state)
        time.sleep(1.2)
    wait_group(key, state, "refine")
    OUT.mkdir(parents=True, exist_ok=True)
    GODOT.mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        result = state["refine"].get(name, {}).get("result") or {}
        if result.get("thumbnail"):
            download(result["thumbnail"], OUT / f"{name}-meshy.png")
        if result.get("glb"):
            path = OUT / f"{name}.glb"
            download(result["glb"], path)
            (GODOT / f"{name}.glb").write_bytes(path.read_bytes())
        else:
            print(f"missing {name}", flush=True)
    print("FURNITURE_DONE", flush=True)


if __name__ == "__main__":
    main()
