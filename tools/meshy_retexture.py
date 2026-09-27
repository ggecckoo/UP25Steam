#!/usr/bin/env python3
"""Retexture the six Meshy characters so the clothes read as real cloth.

Faces, fur and feathers are asked to stay. Humanoids are rigged again from
the retextured task. Birds stay unrigged. Live game files are not replaced;
results land next to the current models as *-cloth.glb.
"""

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art" / "karakterler" / "3d"
STATE = OUT / "meshy-tasks.json"
NAMES = ["kaya", "sis", "kok", "nida", "kul", "dere"]
HUMANOIDS = {"kaya", "sis", "kok", "dere"}
API = "https://api.meshy.ai/openapi/v1"

PROMPTS = {
    "kaya": (
        "Keep the ibex face, amber eyes, swept horns and olive-gray fur unchanged. "
        "Clothing only: a heavy olive wool overcoat with visible nap, weave and lapels, "
        "over an open cream linen shirt with soft wrinkles and one small brass button. "
        "Matte cloth, slight wear, seams. Dim walnut card room, one warm brass lamp. "
        "No plastic, no vinyl, no shiny leather, no flat color."
    ),
    "sis": (
        "Keep the lynx face, ear tufts and spotted fur unchanged. "
        "Clothing only: a charcoal wool coat with a real woven nap, soft folds and a dark shirt underneath. "
        "Matte, slight wear, visible seams. Dim walnut card room, one warm brass lamp. "
        "No plastic, no vinyl, no costume shine, no flat color."
    ),
    "kok": (
        "Keep the badger face, cream stripe and fur unchanged. "
        "Clothing only: a worn olive cotton vest with visible stitching and buttons over a dark shirt. "
        "Matte cloth, soft folds, slight wear. Dim walnut card room, one warm brass lamp. "
        "No plastic, no shiny leather, no flat color."
    ),
    "nida": (
        "Keep the little owl face, speckled cream feathers, dark eyes and gold leaf earring unchanged. "
        "Clothing only: a thick deep-red wool shawl with visible weave and soft drape over a dark charcoal buttoned shirt. "
        "Matte textile, slight wear. Dim walnut card room, one warm brass lamp. "
        "No plastic, no satin, no flat color."
    ),
    "kul": (
        "Keep the hooded crow face, black head, gray body feathers and thin brass neck ring unchanged. "
        "Clothing only: a plain dark charcoal cotton shirt with a real weave, shoulder seams and soft wrinkles. "
        "Matte, slight wear. Dim walnut card room, one warm brass lamp. "
        "No plastic, no vinyl, no flat color."
    ),
    "dere": (
        "Keep the otter face, whiskers, dark eyes and chestnut fur unchanged. "
        "Clothing only: a cream linen shirt, collar open, sleeves rolled, visible weave, seams and natural wrinkles. "
        "Matte cloth, slight wear. Dim walnut card room, one warm brass lamp. "
        "No plastic, no shiny fabric, no flat color."
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
    return json.loads(STATE.read_text())


def save_state(state):
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def create_retexture(key, name, image_id):
    status, payload = request(key, "POST", "/retexture", {
        "input_task_id": image_id,
        "text_style_prompt": PROMPTS[name],
        "ai_model": "meshy-6",
        "enable_original_uv": True,
        "enable_pbr": True,
        "remove_lighting": True,
        "texture_resolution": "4k",
        "target_formats": ["glb"],
    })
    if status not in (200, 202):
        print(f"retexture {name} failed {status} {payload.get('message', payload)}", flush=True)
        return ""
    task_id = payload.get("result") or payload.get("id") or ""
    print(f"retexture {name} {task_id}", flush=True)
    return task_id


def create_rig(key, name, source_id):
    status, payload = request(key, "POST", "/rigging", {
        "input_task_id": source_id,
        "height_meters": 1.5,
    })
    if status not in (200, 202):
        print(f"rig {name} failed {status} {payload.get('message', payload)}", flush=True)
        return ""
    task_id = payload.get("result") or payload.get("id") or ""
    print(f"rig {name} {task_id}", flush=True)
    return task_id


def poll_once(key, kind, task_id):
    path = "/retexture/" if kind == "cloth" else "/rigging/"
    status, payload = request(key, "GET", path + task_id)
    if status == 429:
        print(f"wait {kind} {task_id} rate limit", flush=True)
        return {"status": "PENDING"}
    if status != 200:
        return {"status": "FAILED", "task_error": {"message": f"http {status}"}}
    state = payload.get("status", "")
    print(f"{kind} {task_id} {state} {payload.get('progress', 0)}", flush=True)
    return payload


def download(url, path):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=180) as resp:
        path.write_bytes(resp.read())
    print(f"saved {path.name} {path.stat().st_size}", flush=True)


def main():
    key = load_key()
    state = load_state()
    cloth = state.setdefault("cloth", {})
    for name in NAMES:
        if name in cloth and cloth[name].get("id"):
            continue
        image_id = state["images"][name]["id"]
        task_id = create_retexture(key, name, image_id)
        cloth[name] = {"id": task_id} if task_id else {"error": "create failed"}
        save_state(state)
        time.sleep(1.2)

    pending = [
        name for name in NAMES
        if cloth.get(name, {}).get("id") and "result" not in cloth[name] and "error" not in cloth[name]
    ]
    while pending:
        still = []
        for name in pending:
            payload = poll_once(key, "cloth", cloth[name]["id"])
            status = payload.get("status", "")
            if status == "SUCCEEDED":
                urls = payload.get("model_urls") or {}
                cloth[name]["result"] = {
                    "glb": urls.get("glb", ""),
                    "thumbnail": payload.get("thumbnail_url", ""),
                }
                save_state(state)
                thumb = cloth[name]["result"]["thumbnail"]
                if thumb:
                    download(thumb, OUT / f"{name}-cloth.png")
                if urls.get("glb"):
                    download(urls["glb"], OUT / f"{name}-cloth.glb")
            elif status in ("FAILED", "CANCELED"):
                message = (payload.get("task_error") or {}).get("message", status)
                cloth[name]["error"] = message
                save_state(state)
                print(f"cloth {name} error {message}", flush=True)
            else:
                still.append(name)
        pending = still
        if pending:
            time.sleep(8)

    rigs = state.setdefault("cloth_rigs", {})
    for name in NAMES:
        if name not in HUMANOIDS:
            continue
        if name in rigs and (rigs[name].get("id") or rigs[name].get("error")):
            continue
        source = cloth.get(name, {}).get("id", "")
        if not source or cloth[name].get("error"):
            rigs[name] = {"error": "no cloth"}
            save_state(state)
            continue
        rig_id = create_rig(key, name, source)
        rigs[name] = {"id": rig_id} if rig_id else {"error": "create failed"}
        save_state(state)
        time.sleep(1.2)

    rig_pending = [
        name for name in NAMES
        if name in HUMANOIDS and rigs.get(name, {}).get("id") and "result" not in rigs[name] and "error" not in rigs[name]
    ]
    while rig_pending:
        still = []
        for name in rig_pending:
            payload = poll_once(key, "rig", rigs[name]["id"])
            status = payload.get("status", "")
            if status == "SUCCEEDED":
                result = payload.get("result") or {}
                rigs[name]["result"] = {"glb": result.get("rigged_character_glb_url", "")}
                save_state(state)
                if rigs[name]["result"]["glb"]:
                    download(rigs[name]["result"]["glb"], OUT / f"{name}-cloth-rig.glb")
            elif status in ("FAILED", "CANCELED"):
                message = (payload.get("task_error") or {}).get("message", status)
                rigs[name]["error"] = message
                save_state(state)
                print(f"rig {name} error {message}", flush=True)
            else:
                still.append(name)
        rig_pending = still
        if rig_pending:
            time.sleep(8)
    print("CLOTH_READY", flush=True)


if __name__ == "__main__":
    main()
