#!/usr/bin/env python3
"""Rig the crow (kul.glb) as the standing croupier.

Meshy's auto-rigger failed on the bird, so this places a skeleton by hand on
the A-posed mesh and paints envelope weights region by region. Bone names
and hierarchy follow the Meshy rigs the seated cast uses (Hips, Spine02,
Spine01, Spine, LeftArm, ...), each bone's +Y pointing at its child, so the
same reach and aim maths drive it. Writes godot/assets/characters/krupiye.glb.
"""

import json
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "godot" / "assets" / "characters" / "kul.glb"
TARGET = ROOT / "godot" / "assets" / "characters" / "krupiye.glb"
HEIGHT = 1.55

# Joint positions in the source mesh's own frame (about 1.9 tall, facing +Z,
# left side +X), read off the mesh: wing axis by PCA, legs and spine by
# height slices.
JOINTS = {
    "Hips": (0.0, -0.45, 0.02),
    "Spine02": (0.0, -0.25, 0.06),
    "Spine01": (0.0, -0.02, 0.1),
    "Spine": (0.0, 0.22, 0.11),
    "neck": (0.0, 0.47, 0.09),
    "Head": (0.0, 0.6, 0.1),
    "head_end": (0.0, 0.95, 0.1),
    "headfront": (0.0, 0.63, 0.52),
    "LeftShoulder": (0.12, 0.4, 0.0),
    "LeftArm": (0.33, 0.41, -0.06),
    "LeftForeArm": (0.56, 0.01, -0.03),
    "LeftHand": (0.8, -0.3, 0.19),
    "LeftHandTip": (0.93, -0.55, 0.34),
    "LeftUpLeg": (0.17, -0.55, -0.03),
    "LeftLeg": (0.17, -0.72, -0.06),
    "LeftFoot": (0.19, -0.86, 0.0),
    "LeftToeBase": (0.19, -0.93, 0.12),
    "LeftToeTip": (0.19, -0.95, 0.26),
}
for name, pos in list(JOINTS.items()):
    if name.startswith("Left"):
        JOINTS["Right" + name[4:]] = (-pos[0], pos[1], pos[2])

# name, parent, child the +Y axis aims at
BONES = [
    ("Hips", None, "Spine02"),
    ("LeftUpLeg", "Hips", "LeftLeg"),
    ("LeftLeg", "LeftUpLeg", "LeftFoot"),
    ("LeftFoot", "LeftLeg", "LeftToeBase"),
    ("LeftToeBase", "LeftFoot", "LeftToeTip"),
    ("RightUpLeg", "Hips", "RightLeg"),
    ("RightLeg", "RightUpLeg", "RightFoot"),
    ("RightFoot", "RightLeg", "RightToeBase"),
    ("RightToeBase", "RightFoot", "RightToeTip"),
    ("Spine02", "Hips", "Spine01"),
    ("Spine01", "Spine02", "Spine"),
    ("Spine", "Spine01", "neck"),
    ("LeftShoulder", "Spine", "LeftArm"),
    ("LeftArm", "LeftShoulder", "LeftForeArm"),
    ("LeftForeArm", "LeftArm", "LeftHand"),
    ("LeftHand", "LeftForeArm", "LeftHandTip"),
    ("RightShoulder", "Spine", "RightArm"),
    ("RightArm", "RightShoulder", "RightForeArm"),
    ("RightForeArm", "RightArm", "RightHand"),
    ("RightHand", "RightForeArm", "RightHandTip"),
    ("neck", "Spine", "Head"),
    ("Head", "neck", "head_end"),
    ("head_end", "Head", None),
    ("headfront", "Head", None),
]
INDEX = {name: i for i, (name, _p, _c) in enumerate(BONES)}


def load(path):
    blob = path.read_bytes()
    _, _, length = struct.unpack("<III", blob[:12])
    off = 12
    chunks = []
    while off < length:
        clen, _ctype = struct.unpack("<II", blob[off:off + 8])
        chunks.append(blob[off + 8:off + 8 + clen])
        off += 8 + clen
    return json.loads(chunks[0]), chunks[1]


def accessor(doc, binary, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    kind = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[acc["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    data = np.frombuffer(binary, dtype=kind, count=acc["count"] * width, offset=start)
    return data.reshape(-1, width) if width > 1 else data


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def segment_distance(points, a, b):
    ab = b - a
    t = np.clip(np.sum((points - a) * ab, axis=1) / max(float(np.sum(ab * ab)), 1e-9), 0.0, 1.0)
    return np.linalg.norm(points - (a + t[:, None] * ab), axis=1), t


def blend(points, bones, power=4.0):
    """Inverse-distance weights to the given bones' segments."""
    cols = []
    for name in bones:
        child = dict((n, c) for n, _p, c in BONES)[name]
        a = np.array(JOINTS[name])
        b = np.array(JOINTS[child]) if child else a + np.array([0.0, 0.05, 0.0])
        dist, _t = segment_distance(points, a, b)
        cols.append(1.0 / np.power(dist + 0.015, power))
    w = np.stack(cols, axis=1)
    return w / w.sum(axis=1, keepdims=True)


def weights(points):
    count = len(points)
    full = np.zeros((count, len(BONES)))
    x, y, z = points[:, 0], points[:, 1], points[:, 2]
    side = np.where(x >= 0.0, "Left", "Right")

    def put(mask, names, amount=None):
        idx = np.nonzero(mask)[0]
        if len(idx) == 0:
            return
        w = blend(points[idx], names)
        share = 1.0 if amount is None else amount[idx]
        for k, name in enumerate(names):
            full[idx, INDEX[name]] += w[:, k] * share

    # How far each vertex belongs to its wing: past the gap between chest and
    # wing (chest edge at |x| 0.32, wing at 0.365) below the shoulder, easing
    # in across the sleeve at shoulder height.
    shoulder_band = smooth(0.24, 0.36, np.abs(x)) * smooth(0.24, 0.34, y) * (1.0 - smooth(0.46, 0.56, y))
    wing_band = smooth(0.322, 0.345, np.abs(x)) * smooth(-0.64, -0.58, y) * (1.0 - smooth(0.3, 0.4, y))
    arm = np.maximum(shoulder_band, wing_band) * (y < 0.56)
    low = (y < -0.56) & (np.abs(x) < 0.5)
    legs = low & (z > -0.14)
    tail = low & (z <= -0.14)
    head = y > 0.46
    body = ~legs & ~tail
    torso_share = 1.0 - arm
    for s in ("Left", "Right"):
        mine = side == s
        put(mine & body & (arm > 0.0), [s + "Shoulder", s + "Arm", s + "ForeArm", s + "Hand"], arm)
        put(mine & legs, ["Hips", s + "UpLeg", s + "Leg", s + "Foot", s + "ToeBase"])
    put(tail, ["Hips", "Spine02"])
    trunk = body & ~head
    put(trunk, ["Hips", "Spine02", "Spine01", "Spine", "LeftShoulder", "RightShoulder"], torso_share)
    put(body & head, ["Spine", "neck", "Head"], torso_share)
    lost = int(np.sum(full.sum(axis=1) < 1e-6))
    if lost:
        raise SystemExit("%d vertices fell outside every region" % lost)
    # Keep the four strongest influences.
    order = np.argsort(-full, axis=1)[:, :4]
    picked = np.take_along_axis(full, order, axis=1)
    picked = picked / np.maximum(picked.sum(axis=1, keepdims=True), 1e-9)
    return order.astype(np.uint16), picked.astype(np.float32)


def rest_frames():
    """Bind transform per bone: at its joint, +Y toward its child."""
    frames = {}
    for name, parent, child in BONES:
        origin = np.array(JOINTS[name], dtype=np.float64)
        if child:
            up = np.array(JOINTS[child]) - origin
        else:
            up = origin - np.array(JOINTS[parent])
        up = up / np.linalg.norm(up)
        # Twist: keep +Z toward the front where the bone allows it.
        ahead = np.array([0.0, 0.0, 1.0]) if abs(up[2]) < 0.9 else np.array([0.0, -1.0, 0.0])
        right = np.cross(up, ahead)
        right /= np.linalg.norm(right)
        ahead = np.cross(right, up)
        basis = np.stack([right, up, ahead], axis=1)
        m = np.eye(4)
        m[:3, :3] = basis
        m[:3, 3] = origin
        frames[name] = m
    return frames


def quat(m):
    r = m[:3, :3]
    tr = np.trace(r)
    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2
        w, x, y, z = 0.25 * s, (r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s
    elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
        s = np.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
        w, x, y, z = (r[2, 1] - r[1, 2]) / s, 0.25 * s, (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s
    elif r[1, 1] > r[2, 2]:
        s = np.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
        w, x, y, z = (r[0, 2] - r[2, 0]) / s, (r[0, 1] + r[1, 0]) / s, 0.25 * s, (r[1, 2] + r[2, 1]) / s
    else:
        s = np.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
        w, x, y, z = (r[1, 0] - r[0, 1]) / s, (r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s, 0.25 * s
    q = np.array([x, y, z, w])
    return (q / np.linalg.norm(q)).tolist()


def main():
    doc, binary = load(SOURCE)
    prim = doc["meshes"][0]["primitives"][0]
    points = accessor(doc, binary, prim["attributes"]["POSITION"]).astype(np.float64)
    normals = accessor(doc, binary, prim["attributes"]["NORMAL"]).astype(np.float32)
    uvs = accessor(doc, binary, prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
    indices = accessor(doc, binary, prim["indices"]).astype(np.uint32)
    joints, influence = weights(points)

    # Into metres, feet on the floor, centred under the hips.
    scale = HEIGHT / (points[:, 1].max() - points[:, 1].min())
    shift = np.array([-JOINTS["Hips"][0], -points[:, 1].min(), -JOINTS["Hips"][2]])
    placed = ((points + shift) * scale).astype(np.float32)
    for name in JOINTS:
        JOINTS[name] = tuple((np.array(JOINTS[name]) + shift) * scale)
    frames = rest_frames()

    out = bytearray()
    views = []
    accessors = []

    def push(data, target=None):
        while len(out) % 4:
            out.append(0)
        view = {"buffer": 0, "byteOffset": len(out), "byteLength": len(data)}
        if target:
            view["target"] = target
        out.extend(data)
        views.append(view)
        return len(views) - 1

    def add(array, ctype, kind, target=None, bounds=False):
        view = push(np.ascontiguousarray(array).tobytes(), target)
        acc = {"bufferView": view, "componentType": ctype, "count": len(array), "type": kind}
        if bounds:
            acc["min"] = array.min(axis=0).tolist()
            acc["max"] = array.max(axis=0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    pos_a = add(placed, 5126, "VEC3", 34962, bounds=True)
    nrm_a = add(normals, 5126, "VEC3", 34962)
    uv_a = add(uvs, 5126, "VEC2", 34962)
    jnt_a = add(joints, 5123, "VEC4", 34962)
    wgt_a = add(influence, 5126, "VEC4", 34962)
    idx_a = add(indices, 5125, "SCALAR", 34963)
    inverse = np.stack([np.linalg.inv(frames[name]).T.astype(np.float32) for name, _p, _c in BONES])
    ibm_a = add(inverse.reshape(len(BONES), 16), 5126, "MAT4")
    accessors[ibm_a]["type"] = "MAT4"

    images = []
    for image in doc["images"]:
        view = doc["bufferViews"][image["bufferView"]]
        data = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        images.append({"name": image.get("name", ""), "mimeType": image["mimeType"], "bufferView": push(data)})

    nodes = []
    for name, parent, _child in BONES:
        local = frames[name] if parent is None else np.linalg.inv(frames[parent]) @ frames[name]
        nodes.append({"name": name, "translation": local[:3, 3].tolist(), "rotation": quat(local)})
    for name, parent, _child in BONES:
        kids = [INDEX[n] for n, p, _c in BONES if p == name]
        if kids:
            nodes[INDEX[name]]["children"] = kids
    mesh_node = len(nodes)
    nodes.append({"name": "crow", "mesh": 0, "skin": 0})
    nodes.append({"name": "Armature", "children": [mesh_node, INDEX["Hips"]]})

    gltf = {
        "asset": {"version": "2.0", "generator": "tools/rig_dealer.py"},
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": [{"name": "crow", "primitives": [{
            "attributes": {"POSITION": pos_a, "NORMAL": nrm_a, "TEXCOORD_0": uv_a, "JOINTS_0": jnt_a, "WEIGHTS_0": wgt_a},
            "indices": idx_a,
            "material": 0,
        }]}],
        "skins": [{"name": "Armature", "joints": list(range(len(BONES))), "inverseBindMatrices": ibm_a, "skeleton": INDEX["Hips"]}],
        "materials": doc["materials"],
        "textures": doc["textures"],
        "samplers": doc.get("samplers", [{}]),
        "images": images,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": 0}],
    }
    while len(out) % 4:
        out.append(0)
    gltf["buffers"][0]["byteLength"] = len(out)
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(text) % 4:
        text += b" "
    total = 12 + 8 + len(text) + 8 + len(out)
    blob = struct.pack("<III", 0x46546C67, 2, total)
    blob += struct.pack("<II", len(text), 0x4E4F534A) + text
    blob += struct.pack("<II", len(out), 0x004E4942) + bytes(out)
    TARGET.write_bytes(blob)
    heavy = np.bincount(joints[:, 0], minlength=len(BONES))
    print("wrote", TARGET.relative_to(ROOT), "verts", len(placed), "height %.2f" % (placed[:, 1].max() - placed[:, 1].min()))
    for name, _p, _c in BONES:
        print("  %-13s main bone of %5d verts" % (name, heavy[INDEX[name]]))


if __name__ == "__main__":
    main()
