#!/usr/bin/env python3
"""Build the first-person hands as skinned glTF binaries.

The Meshy characters have one bone per hand, so their paws cannot hold a fan
with the thumb or pinch a single card. These hands are modelled as a signed
distance field, meshed with surface nets and skinned to a wrist, a thumb and
four three-joint fingers. Godot paints fur, pads and claws per preset.

Writes godot/assets/hands/hand_left.glb and hand_right.glb.
"""

import json
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "godot" / "assets" / "hands"
STEP = 0.0016
TAU = 0.0022

# Right hand at rest, meters. The wrist joint is the origin, fingers run along
# +Y, the back of the hand faces +Z and the thumb sits toward -X.
# name, knuckle, direction, segment lengths, radius at knuckle/middle/last/tip
FINGERS = [
    ("Index", (-0.0245, 0.0870, 0.0005), (-0.085, 1.0, 0.0), (0.041, 0.024, 0.019), (0.0090, 0.0083, 0.0076, 0.0068)),
    ("Middle", (-0.0075, 0.0900, 0.0012), (0.0, 1.0, 0.0), (0.045, 0.027, 0.020), (0.0094, 0.0087, 0.0079, 0.0071)),
    ("Ring", (0.0092, 0.0865, 0.0005), (0.085, 1.0, 0.0), (0.042, 0.026, 0.019), (0.0088, 0.0081, 0.0074, 0.0066)),
    ("Pinky", (0.0245, 0.0785, -0.0008), (0.18, 1.0, 0.0), (0.033, 0.019, 0.017), (0.0078, 0.0072, 0.0065, 0.0059)),
]
THUMB_BASE = (-0.0185, 0.0275, -0.0105)
THUMB_DIRS = [(-0.62, 0.74, -0.22), (-0.45, 0.87, -0.15), (-0.36, 0.92, -0.10)]
THUMB_LENS = (0.046, 0.0335, 0.027)
THUMB_RADII = (0.0118, 0.0108, 0.0098, 0.0086)
THUMB_NAIL = (-0.55, 0.0, 0.83)
FLAT = 0.9


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


# einsum instead of @: Accelerate raises bogus divide-by-zero flags in matmul.
def rows_dot(p, v):
    return np.einsum("ij,j->i", p, v)


def rows_in(p, basis):
    return np.einsum("ij,jk->ik", p, basis)


def frame(along, back):
    y = unit(along)
    z = np.asarray(back, float) - y * np.dot(back, y)
    z = unit(z)
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)


def smin(a, b, k):
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def round_cone(p, a, b, ra, rb):
    ba = b - a
    l2 = float(np.dot(ba, ba))
    rr = ra - rb
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = rows_dot(pa, ba)
    z = y - l2
    x = pa * l2 - y[:, None] * ba
    x2 = np.einsum("ij,ij->i", x, x)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    near_b = np.sign(z) * a2 * z2 > k
    near_a = np.sign(y) * a2 * y2 < k
    side = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - ra
    return np.where(near_b, np.sqrt(x2 + z2) * il2 - rb, np.where(near_a, np.sqrt(x2 + y2) * il2 - ra, side))


def ellipsoid(p, c, r, basis=None):
    q = p - c
    if basis is not None:
        q = rows_in(q, basis)
    r = np.asarray(r, float)
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def flat_cone(p, a, b, ra, rb, basis, flat):
    """Round cone squashed along the basis z axis (back to palm)."""
    q = rows_in(p - a, basis)
    q[:, 2] /= flat
    a0 = np.zeros(3)
    b0 = (b - a).dot(basis)
    b0[2] /= flat
    return round_cone(q, a0, b0, ra, rb) * flat


class Digit:
    def __init__(self, name, joints, radii, back):
        self.name = name
        self.joints = [np.asarray(j, float) for j in joints]
        self.radii = radii
        self.frames = []
        for i in range(3):
            self.frames.append(frame(self.joints[i + 1] - self.joints[i], back))
        self.lengths = [float(np.linalg.norm(self.joints[i + 1] - self.joints[i])) for i in range(3)]

    def field(self, p):
        j, r = self.joints, self.radii
        d = None
        for i in range(3):
            seg = flat_cone(p, j[i], j[i + 1], r[i], r[i + 1], self.frames[i], FLAT)
            d = seg if d is None else smin(d, seg, 0.0028)
        f = self.frames[2]
        pad_c = j[2] + (j[3] - j[2]) * 0.58 - f[:, 2] * (r[2] * 0.34)
        pad = ellipsoid(p, pad_c, (r[2] * 0.80, self.lengths[2] * 0.40, r[2] * 0.62), f)
        d = smin(d, pad, 0.0032)
        knuckle = j[1] + self.frames[1][:, 2] * (r[1] * 0.22)
        bump = np.linalg.norm(p - knuckle, axis=1) - r[1] * 0.93
        return smin(d, bump, 0.004)

    def along(self, p):
        """Arc length of the closest point on the joint chain. Negative before the base."""
        best = np.full(len(p), np.inf)
        s = np.zeros(len(p))
        start = 0.0
        for i in range(3):
            a, b = self.joints[i], self.joints[i + 1]
            ab = b - a
            t = rows_dot(p - a, ab) / float(np.dot(ab, ab))
            lo = -np.inf if i == 0 else 0.0
            hi = np.inf if i == 2 else 1.0
            t = np.clip(t, lo, hi)
            dist = np.linalg.norm(p - (a + t[:, None] * ab), axis=1)
            take = dist < best - 1e-9
            best = np.where(take, dist, best)
            s = np.where(take, start + t * self.lengths[i], s)
            start += self.lengths[i]
        return s

    def flow(self, s):
        out = np.zeros((len(s), 3))
        edge = np.cumsum(self.lengths)
        for i in range(3):
            lo = -np.inf if i == 0 else edge[i - 1]
            hi = np.inf if i == 2 else edge[i]
            pick = (s >= lo) & (s < hi)
            out[pick] = unit(self.joints[i + 1] - self.joints[i])
        return out


def build_digits():
    digits = []
    t = [np.asarray(THUMB_BASE, float)]
    for d, length in zip(THUMB_DIRS, THUMB_LENS):
        t.append(t[-1] + unit(d) * length)
    digits.append(Digit("Thumb", t, THUMB_RADII, unit(THUMB_NAIL)))
    for name, knuckle, direction, lengths, radii in FINGERS:
        j = [np.asarray(knuckle, float)]
        for length in lengths:
            j.append(j[-1] + unit(direction) * length)
        digits.append(Digit(name, j, radii, (0.0, 0.0, 1.0)))
    return digits


class Hand:
    def __init__(self):
        self.digits = build_digits()
        fingers = self.digits[1:]
        self.parts = []
        self.parts.append(("carpus", lambda p: ellipsoid(p, np.array([0.0, 0.012, -0.0005]), (0.0265, 0.020, 0.015))))
        for f in fingers:
            head = f.joints[0] - unit(f.joints[1] - f.joints[0]) * 0.004
            base = np.array([f.joints[0][0] * 0.62, 0.022, f.joints[0][2] + 0.001])
            basis = frame(head - base, (0.0, 0.0, 1.0))
            self.parts.append(("meta" + f.name, lambda p, a=base, b=head, m=basis, r=f.radii[0]: flat_cone(p, a, b, 0.0080, r + 0.0008, m, 0.8)))
        self.parts.append(("fill", lambda p: ellipsoid(p, np.array([0.0, 0.056, -0.004]), (0.0345, 0.040, 0.0100))))
        self.parts.append(("thenar", lambda p: round_cone(p, np.array([-0.010, 0.020, -0.0105]), np.array([-0.031, 0.056, -0.0130]), 0.0135, 0.0098)))
        self.parts.append(("hypothenar", lambda p: round_cone(p, np.array([0.0195, 0.022, -0.0075]), np.array([0.0285, 0.072, -0.0065]), 0.0110, 0.0092)))
        self.parts.append(("ridge", lambda p: ellipsoid(p, np.array([0.0, 0.080, -0.006]), (0.0335, 0.0115, 0.0088))))
        arm = frame((0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
        # Only as long as the sleeve overlaps it, and narrowing into the cuff,
        # so a bent wrist does not push its end out through the sleeve.
        self.forearm = lambda p: flat_cone(p, np.array([0.0, -0.06, 0.0008]), np.array([0.0, -0.002, 0.0]), 0.0205, 0.0245, arm, 0.72)

    def core_parts(self, p):
        return {name: fn(p) for name, fn in self.parts}

    def core(self, p, parts=None):
        parts = parts or self.core_parts(p)
        d = None
        for value in parts.values():
            d = value if d is None else smin(d, value, 0.009)
        return smin(self.forearm(p), d, 0.014)

    def field(self, p):
        core = self.core(p)
        out = None
        for digit in self.digits:
            k = 0.011 if digit.name == "Thumb" else 0.0085
            joined = smin(core, digit.field(p), k)
            out = joined if out is None else np.minimum(out, joined)
        return out


def grad(fn, p, h=0.0003):
    g = np.zeros_like(p)
    for axis in range(3):
        e = np.zeros(3)
        e[axis] = h
        g[:, axis] = (fn(p + e) - fn(p - e)) / (2.0 * h)
    return g


def surface_nets(field, origin, step):
    s = field
    offs = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]], float)
    corners = [s[o[0]:s.shape[0] - 1 + o[0], o[1]:s.shape[1] - 1 + o[1], o[2]:s.shape[2] - 1 + o[2]] for o in offs.astype(int)]
    inside = sum((c < 0).astype(np.int8) for c in corners)
    active = (inside > 0) & (inside < 8)
    cells = np.argwhere(active)
    vals = np.stack([c[active] for c in corners], axis=1)
    acc = np.zeros((len(cells), 3))
    cnt = np.zeros(len(cells))
    for a, b in [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]:
        va, vb = vals[:, a], vals[:, b]
        cross = (va < 0) != (vb < 0)
        t = np.where(cross, va / np.where(cross, va - vb, 1.0), 0.0)
        pos = offs[a] + t[:, None] * (offs[b] - offs[a])
        acc[cross] += pos[cross]
        cnt[cross] += 1
    verts = origin + (cells + acc / cnt[:, None]) * step
    index = -np.ones(active.shape, np.int64)
    index[active] = np.arange(len(cells))
    quads = []
    a, b = s[:-1, 1:-1, 1:-1], s[1:, 1:-1, 1:-1]
    sign = (a < 0) != (b < 0)
    i, j, k = np.nonzero(sign)
    j, k = j + 1, k + 1
    q = np.stack([index[i, j - 1, k - 1], index[i, j, k - 1], index[i, j, k], index[i, j - 1, k]], axis=1)
    quads.append(np.where((a[sign] < 0)[:, None], q, q[:, ::-1]))
    a, b = s[1:-1, :-1, 1:-1], s[1:-1, 1:, 1:-1]
    sign = (a < 0) != (b < 0)
    i, j, k = np.nonzero(sign)
    i, k = i + 1, k + 1
    q = np.stack([index[i - 1, j, k - 1], index[i - 1, j, k], index[i, j, k], index[i, j, k - 1]], axis=1)
    quads.append(np.where((a[sign] < 0)[:, None], q, q[:, ::-1]))
    a, b = s[1:-1, 1:-1, :-1], s[1:-1, 1:-1, 1:]
    sign = (a < 0) != (b < 0)
    i, j, k = np.nonzero(sign)
    i, j = i + 1, j + 1
    q = np.stack([index[i - 1, j - 1, k], index[i, j - 1, k], index[i, j, k], index[i - 1, j, k]], axis=1)
    quads.append(np.where((a[sign] < 0)[:, None], q, q[:, ::-1]))
    quads = np.concatenate(quads)
    d02 = np.linalg.norm(verts[quads[:, 0]] - verts[quads[:, 2]], axis=1)
    d13 = np.linalg.norm(verts[quads[:, 1]] - verts[quads[:, 3]], axis=1)
    short = (d02 <= d13)[:, None]
    t1 = np.where(short, quads[:, [0, 1, 2]], quads[:, [1, 2, 3]])
    t2 = np.where(short, quads[:, [0, 2, 3]], quads[:, [1, 3, 0]])
    tris = np.concatenate([t1, t2])
    used = np.unique(tris)
    remap = -np.ones(len(verts), np.int64)
    remap[used] = np.arange(len(used))
    return verts[used], remap[tris]


def smooth(verts, tris, rounds, fn):
    n = len(verts)
    for _ in range(rounds):
        acc = np.zeros_like(verts)
        cnt = np.zeros(n)
        for a, b in [(0, 1), (1, 2), (2, 0)]:
            np.add.at(acc, tris[:, a], verts[tris[:, b]])
            np.add.at(cnt, tris[:, a], 1.0)
            np.add.at(acc, tris[:, b], verts[tris[:, a]])
            np.add.at(cnt, tris[:, b], 1.0)
        target = acc / np.maximum(cnt, 1.0)[:, None]
        g = grad(fn, verts)
        nrm = g / np.maximum(np.linalg.norm(g, axis=1), 1e-9)[:, None]
        move = target - verts
        move -= nrm * np.einsum("ij,ij->i", move, nrm)[:, None]
        verts = verts + move * 0.5
        verts = project(verts, fn, 2)
    return verts


def project(verts, fn, rounds):
    for _ in range(rounds):
        d = fn(verts)
        g = grad(fn, verts)
        verts = verts - g * (d / np.maximum(np.einsum("ij,ij->i", g, g), 1e-12))[:, None]
    return verts


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


BONE_NAMES = ["Wrist"]
for _digit in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
    BONE_NAMES += [_digit + "1", _digit + "2", _digit + "3", _digit + "4"]


def skin(hand, verts, normals):
    n = len(verts)
    parts = hand.core_parts(verts)
    core = hand.core(verts, parts)
    names = ["core"] + [d.name for d in hand.digits]
    dist = [core] + [d.field(verts) for d in hand.digits]
    dist = np.stack(dist, axis=1)
    low = dist.min(axis=1, keepdims=True)
    member = np.exp(-(dist - low) / TAU)
    member /= member.sum(axis=1, keepdims=True)
    weights = np.zeros((n, len(BONE_NAMES)))
    flow = np.zeros((n, 3))
    palmar = np.zeros((n, 3))
    pads = np.zeros(n)
    # Fur shortens along each digit, the way it does over toes.
    fur = member[:, 0].copy()
    # Wrist and palm, with the knuckle skin handed to the nearest finger.
    m = member[:, 0]
    core_w = np.zeros((n, len(BONE_NAMES)))
    core_w[:, 0] = 1.0
    best = np.full(n, np.inf)
    for digit in hand.digits[1:]:
        j0 = digit.joints[0]
        axis = unit(digit.joints[1] - j0)
        rel = verts - j0
        s = rows_dot(rel, axis)
        side = np.linalg.norm(rel - s[:, None] * axis, axis=1)
        reach = np.exp(-(np.maximum(side - digit.radii[0], 0.0) / 0.006) ** 2)
        near = np.linalg.norm(rel, axis=1)
        take = near < best
        best = np.where(take, near, best)
        u = smoothstep(-0.009, 0.009, s) * reach
        bone = BONE_NAMES.index(digit.name + "1")
        core_w[take] = 0.0
        core_w[take, 0] = 1.0 - u[take]
        core_w[take, bone] = u[take]
    thumb = hand.digits[0]
    t_axis = unit(thumb.joints[1] - thumb.joints[0])
    t_s = rows_dot(verts - thumb.joints[0], t_axis)
    thenar_near = parts["thenar"] - np.min(np.stack(list(parts.values()), axis=1), axis=1) < 0.002
    t_u = 0.62 * smoothstep(-0.012, 0.03, t_s) * thenar_near
    t1 = BONE_NAMES.index("Thumb1")
    core_w = core_w * (1.0 - t_u)[:, None]
    core_w[:, t1] += t_u
    weights += core_w * m[:, None]
    flow += np.array([0.0, 1.0, 0.0]) * m[:, None]
    palmar += np.array([0.0, 0.0, -1.0]) * m[:, None]
    palm_pad = smoothstep(1.0, 0.4, np.sqrt(((verts[:, 0] + 0.001) / 0.022) ** 2 + ((verts[:, 1] - 0.0755) / 0.0105) ** 2))
    palm_pad *= smoothstep(0.45, 0.8, -normals[:, 2]) * 0.85
    pads = np.maximum(pads, palm_pad * m)
    for col, digit in enumerate(hand.digits, start=1):
        m = member[:, col]
        s = digit.along(verts)
        l0, l1, l2 = digit.lengths
        fur += m * (0.85 - 0.5 * smoothstep(0.0, l0 + l1 + l2, s))
        h0 = 0.010 if digit.name == "Thumb" else 0.008
        u1 = smoothstep(-h0, h0, s)
        u2 = smoothstep(l0 - 0.0055, l0 + 0.0055, s)
        u3 = smoothstep(l0 + l1 - 0.0045, l0 + l1 + 0.0045, s)
        base = BONE_NAMES.index(digit.name + "1")
        weights[:, 0] += m * (1.0 - u1)
        weights[:, base] += m * (u1 - u2)
        weights[:, base + 1] += m * (u2 - u3)
        weights[:, base + 2] += m * u3
        flow += digit.flow(s) * m[:, None]
        down = -digit.frames[2][:, 2]
        palmar += down * m[:, None]
        last = digit.frames[2]
        r = digit.radii[3]
        local = rows_in(verts - digit.joints[2], last)
        reach = np.sqrt((local[:, 0] / (0.62 * r)) ** 2 + ((local[:, 1] - 0.6 * l2) / (0.36 * l2)) ** 2 + ((local[:, 2] + r) / (0.75 * r)) ** 2)
        pads = np.maximum(pads, smoothstep(1.0, 0.45, reach) * m)
    weights = np.maximum(weights, 0.0)
    order = np.argsort(-weights, axis=1)[:, :4]
    top = np.take_along_axis(weights, order, axis=1)
    top /= np.maximum(top.sum(axis=1, keepdims=True), 1e-9)
    flow -= normals * np.einsum("ij,ij->i", flow, normals)[:, None]
    length = np.linalg.norm(flow, axis=1)
    fallback = np.cross(normals, np.array([1.0, 0.0, 0.0]))
    flow = np.where((length > 1e-4)[:, None], flow / np.maximum(length, 1e-9)[:, None], fallback / np.maximum(np.linalg.norm(fallback, axis=1), 1e-9)[:, None])
    palmar /= np.maximum(np.linalg.norm(palmar, axis=1), 1e-9)[:, None]
    under = smoothstep(0.05, 0.75, np.einsum("ij,ij->i", normals, palmar))
    return order.astype(np.uint16), top.astype(np.float32), flow, under, pads, fur


def bone_frames(hand):
    """Global rest transform of every bone: rotation columns and head position."""
    out = {"Wrist": (np.eye(3), np.zeros(3))}
    for digit in hand.digits:
        for i in range(4):
            basis = digit.frames[min(i, 2)]
            out[digit.name + str(i + 1)] = (basis, digit.joints[i])
    return out


def parent_of(name):
    if name == "Wrist":
        return None
    digit, index = name[:-1], int(name[-1])
    return "Wrist" if index == 1 else digit + str(index - 1)


def quat_from_matrix(m):
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0.0:
        s = np.sqrt(t + 1.0) * 2.0
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2.0
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2.0
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2.0
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.asarray(q, float)
    return q / np.linalg.norm(q)


def mirror_frames(frames):
    flip = np.diag([-1.0, 1.0, 1.0])
    return {name: (flip.dot(basis).dot(flip), flip.dot(head)) for name, (basis, head) in frames.items()}


def pack(name, verts, normals, flow, uv, uv2, color, joints, weights, tris, frames):
    blobs = []
    views = []
    accessors = []

    def push(data, target=None):
        while sum(len(b) for b in blobs) % 4:
            blobs.append(b"\x00")
        offset = sum(len(b) for b in blobs)
        blobs.append(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        return len(views) - 1

    def accessor(array, ctype, kind, target=None, bounds=False):
        data = np.ascontiguousarray(array).tobytes()
        acc = {"bufferView": push(data, target), "componentType": ctype, "count": int(len(array)), "type": kind}
        if bounds:
            acc["min"] = [float(v) for v in array.min(axis=0)]
            acc["max"] = [float(v) for v in array.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    tangent = np.concatenate([flow, np.ones((len(flow), 1))], axis=1).astype(np.float32)
    attributes = {
        "POSITION": accessor(verts.astype(np.float32), 5126, "VEC3", 34962, True),
        "NORMAL": accessor(normals.astype(np.float32), 5126, "VEC3", 34962),
        "TANGENT": accessor(tangent, 5126, "VEC4", 34962),
        "TEXCOORD_0": accessor(uv.astype(np.float32), 5126, "VEC2", 34962),
        "TEXCOORD_1": accessor(uv2.astype(np.float32), 5126, "VEC2", 34962),
        "COLOR_0": accessor(color.astype(np.float32), 5126, "VEC4", 34962),
        "JOINTS_0": accessor(joints, 5123, "VEC4", 34962),
        "WEIGHTS_0": accessor(weights, 5126, "VEC4", 34962),
    }
    indices = accessor(tris.reshape(-1).astype(np.uint32), 5125, "SCALAR", 34963)
    inverse = []
    for bone in BONE_NAMES:
        basis, head = frames[bone]
        m = np.eye(4)
        m[:3, :3] = basis
        m[:3, 3] = head
        inverse.append(np.linalg.inv(m).T.reshape(-1))
    ibm = accessor(np.asarray(inverse, np.float32), 5126, "MAT4")
    nodes = []
    for bone in BONE_NAMES:
        basis, head = frames[bone]
        parent = parent_of(bone)
        if parent is None:
            local_r, local_t = basis, head
        else:
            p_basis, p_head = frames[parent]
            local_r = p_basis.T.dot(basis)
            local_t = p_basis.T.dot(head - p_head)
        node = {"name": bone, "translation": [float(v) for v in local_t], "rotation": [float(v) for v in quat_from_matrix(local_r)]}
        children = [i for i, other in enumerate(BONE_NAMES) if parent_of(other) == bone]
        if children:
            node["children"] = children
        nodes.append(node)
    nodes.append({"name": "HandMesh", "mesh": 0, "skin": 0})
    nodes.append({"name": name, "children": [0, len(BONE_NAMES)], "extras": {"unit": "meter", "fingers": "+Y", "back": "+Z"}})
    blob = b"".join(blobs)
    gltf = {
        "asset": {"version": "2.0", "generator": "25-40 fp-hands-v1"},
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": [{"name": name, "primitives": [{"attributes": attributes, "indices": indices, "material": 0}]}],
        "materials": [{"name": "Fur", "pbrMetallicRoughness": {"baseColorFactor": [0.42, 0.3, 0.2, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.85}}],
        "skins": [{"name": name, "joints": list(range(len(BONE_NAMES))), "inverseBindMatrices": ibm, "skeleton": 0}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(text) % 4:
        text += b" "
    while len(blob) % 4:
        blob += b"\x00"
    chunks = struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(blob), b"BIN\x00") + blob
    return struct.pack("<4sII", b"glTF", 2, 12 + len(chunks)) + chunks


def main():
    hand = Hand()
    lo = np.array([-0.090, -0.112, -0.050])
    hi = np.array([0.062, 0.212, 0.036])
    count = np.ceil((hi - lo) / STEP).astype(int) + 1
    axes = [lo[i] + np.arange(count[i]) * STEP for i in range(3)]
    grid = np.stack(np.meshgrid(*axes, indexing="ij"), axis=-1).reshape(-1, 3)
    field = np.empty(len(grid))
    chunk = 400000
    for start in range(0, len(grid), chunk):
        field[start:start + chunk] = hand.field(grid[start:start + chunk])
    field = field.reshape(count)
    verts, tris = surface_nets(field, lo, STEP)
    verts = project(verts, hand.field, 3)
    verts = smooth(verts, tris, 3, hand.field)
    g = grad(hand.field, verts)
    normals = g / np.maximum(np.linalg.norm(g, axis=1), 1e-9)[:, None]
    joints, weights, flow, under, pads, fur = skin(hand, verts, normals)
    color = np.stack([1.0 - pads, pads, under, fur], axis=1)
    for label, array in [("position", verts), ("normal", normals), ("flow", flow), ("weight", weights), ("color", color)]:
        if not np.all(np.isfinite(array)):
            raise SystemExit("non-finite %s data" % label)
    frames = bone_frames(hand)
    OUT.mkdir(parents=True, exist_ok=True)
    uv = verts[:, :2] * 10.0
    uv2 = np.stack([verts[:, 2] * 10.0, np.zeros(len(verts))], axis=1)
    right = pack("HandRight", verts, normals, flow, uv, uv2, color, joints, weights, tris, frames)
    (OUT / "hand_right.glb").write_bytes(right)
    flip = np.array([-1.0, 1.0, 1.0])
    left = pack("HandLeft", verts * flip, normals * flip, flow * flip, uv * np.array([-1.0, 1.0]), uv2, color, joints, weights, tris[:, ::-1], mirror_frames(frames))
    (OUT / "hand_left.glb").write_bytes(left)
    print("hands: %d vertices, %d triangles" % (len(verts), len(tris)))


if __name__ == "__main__":
    main()
