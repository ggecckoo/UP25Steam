#!/usr/bin/env python3
"""Build the six seated 25-40 characters as skinned glTF binaries.

One skeleton, seated at the table, shared by every preset. Species differ
by mesh and material only, so SitIdle, PlayCard, LeanIn, LeanBack,
WatchLeft and WatchRight play on all six.
"""

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art" / "karakterler" / "3d"
GODOT = ROOT / "godot" / "assets" / "characters"

# Bone local translation is meters. Euler is degrees, applied as XYZ.
# Child offset is the bone length. Arms run along local -Y before rotation.
BONES = [
    ("Hips", None, (0.00, 0.50, 0.00), (0, 0, 0)),
    ("Spine", "Hips", (0.00, 0.12, 0.00), (14, 0, 0)),
    ("Chest", "Spine", (0.00, 0.15, 0.00), (10, 0, 0)),
    ("Neck", "Chest", (0.00, 0.16, 0.02), (16, 0, 0)),
    ("Head", "Neck", (0.00, 0.08, 0.00), (8, 0, 0)),
    ("Muzzle", "Head", (0.00, -0.02, 0.06), (0, 0, 0)),
    ("EarL", "Head", (-0.07, 0.08, 0.00), (0, 0, 18)),
    ("EarR", "Head", (0.07, 0.08, 0.00), (0, 0, -18)),
    ("HornL", "Head", (-0.05, 0.09, -0.02), (-110, -15, 35)),
    ("HornR", "Head", (0.05, 0.09, -0.02), (-110, 15, -35)),
    ("ClavicleL", "Chest", (-0.08, 0.10, 0.03), (0, 10, 8)),
    ("UpperArmL", "ClavicleL", (-0.10, -0.02, 0.00), (-60, 8, 14)),
    ("ForearmL", "UpperArmL", (0.00, -0.22, 0.00), (-86, 0, 0)),
    ("HandL", "ForearmL", (0.00, -0.18, 0.00), (-10, 15, 0)),
    ("ThumbL", "HandL", (0.03, -0.015, 0.02), (15, 0, 35)),
    ("IndexL", "HandL", (-0.005, -0.045, 0.025), (30, 0, 6)),
    ("ClavicleR", "Chest", (0.08, 0.10, 0.03), (0, -10, -8)),
    ("UpperArmR", "ClavicleR", (0.10, -0.02, 0.00), (-60, -8, -14)),
    ("ForearmR", "UpperArmR", (0.00, -0.22, 0.00), (-86, 0, 0)),
    ("HandR", "ForearmR", (0.00, -0.18, 0.00), (-10, -15, 0)),
    ("ThumbR", "HandR", (-0.03, -0.015, 0.02), (15, 0, -35)),
    ("IndexR", "HandR", (0.005, -0.045, 0.025), (30, 0, -6)),
    ("ThighL", "Hips", (-0.08, -0.04, 0.02), (-48, 6, 4)),
    ("ShinL", "ThighL", (0.00, -0.26, 0.00), (24, 0, 0)),
    ("FootL", "ShinL", (0.00, -0.24, 0.00), (10, 0, 0)),
    ("ThighR", "Hips", (0.08, -0.04, 0.02), (-48, -6, -4)),
    ("ShinR", "ThighR", (0.00, -0.26, 0.00), (24, 0, 0)),
    ("FootR", "ShinR", (0.00, -0.24, 0.00), (10, 0, 0)),
]

BONE_INDEX = {name: i for i, (name, *_rest) in enumerate(BONES)}


def euler_quat(rx, ry, rz):
    rx, ry, rz = math.radians(rx), math.radians(ry), math.radians(rz)
    cx, sx = math.cos(rx * 0.5), math.sin(rx * 0.5)
    cy, sy = math.cos(ry * 0.5), math.sin(ry * 0.5)
    cz, sz = math.cos(rz * 0.5), math.sin(rz * 0.5)
    return (
        sx * cy * cz + cx * sy * sz,
        cx * sy * cz - sx * cy * sz,
        cx * cy * sz + sx * sy * cz,
        cx * cy * cz - sx * sy * sz,
    )


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def qnorm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def quat_align(a, b):
    if a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3] < 0:
        return (-b[0], -b[1], -b[2], -b[3])
    return b


def quat_mat(q):
    x, y, z, w = qnorm(q)
    return (
        (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
        (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
        (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)),
    )


def mat_mul(a, b):
    out = [[0.0] * 4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            out[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
    return out


def mat_trs(t, q):
    r = quat_mat(q)
    return (
        (r[0][0], r[0][1], r[0][2], t[0]),
        (r[1][0], r[1][1], r[1][2], t[1]),
        (r[2][0], r[2][1], r[2][2], t[2]),
        (0.0, 0.0, 0.0, 1.0),
    )


def mat_inv_rigid(m):
    r = tuple(tuple(m[i][j] for j in range(3)) for i in range(3))
    rt = tuple(tuple(r[j][i] for j in range(3)) for i in range(3))
    t = (m[0][3], m[1][3], m[2][3])
    ti = (
        -(rt[0][0] * t[0] + rt[0][1] * t[1] + rt[0][2] * t[2]),
        -(rt[1][0] * t[0] + rt[1][1] * t[1] + rt[1][2] * t[2]),
        -(rt[2][0] * t[0] + rt[2][1] * t[1] + rt[2][2] * t[2]),
    )
    return (
        (rt[0][0], rt[0][1], rt[0][2], ti[0]),
        (rt[1][0], rt[1][1], rt[1][2], ti[1]),
        (rt[2][0], rt[2][1], rt[2][2], ti[2]),
        (0.0, 0.0, 0.0, 1.0),
    )


def mat_point(m, p):
    x, y, z = p
    return (
        m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
        m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
        m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3],
    )


def mat_dir(m, d):
    x, y, z = d
    return (
        m[0][0] * x + m[0][1] * y + m[0][2] * z,
        m[1][0] * x + m[1][1] * y + m[1][2] * z,
        m[2][0] * x + m[2][1] * y + m[2][2] * z,
    )


def vnorm(v):
    n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / n, v[1] / n, v[2] / n)


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vmul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def pose_locals(scale, deltas=None):
    deltas = deltas or {}
    locals_ = []
    for name, _parent, t, euler in BONES:
        d = deltas.get(name, (0, 0, 0))
        e = (euler[0] + d[0], euler[1] + d[1], euler[2] + d[2])
        locals_.append((name, (t[0] * scale, t[1] * scale, t[2] * scale), euler_quat(*e)))
    return locals_


def world_matrices(locals_):
    by_name = {name: (t, q) for name, t, q in locals_}
    worlds = [None] * len(BONES)
    for i, (name, parent, _t, _e) in enumerate(BONES):
        t, q = by_name[name]
        local = mat_trs(t, q)
        worlds[i] = local if parent is None else mat_mul(worlds[BONE_INDEX[parent]], local)
    return worlds


def sphere(stacks, slices):
    verts = []
    norms = []
    idx = []
    for iy in range(stacks + 1):
        v = iy / stacks
        phi = v * math.pi
        for ix in range(slices + 1):
            u = ix / slices
            theta = u * math.tau
            x = math.sin(phi) * math.cos(theta)
            y = math.cos(phi)
            z = math.sin(phi) * math.sin(theta)
            verts.append((x, y, z))
            norms.append((x, y, z))
    for iy in range(stacks):
        for ix in range(slices):
            a = iy * (slices + 1) + ix
            b = a + slices + 1
            idx.extend((a, b, a + 1, b, b + 1, a + 1))
    return verts, norms, idx


def cone(stacks, slices):
    verts = [(0.0, 0.0, 0.0)]
    norms = [(0.0, -1.0, 0.0)]
    for iy in range(stacks + 1):
        v = iy / stacks
        r = 1.0 - v
        y = v
        ring = []
        for ix in range(slices):
            theta = ix / slices * math.tau
            ring.append((r * math.cos(theta), y, r * math.sin(theta)))
        slope = 1.0
        for x, yv, z in ring:
            verts.append((x, yv, z))
            norms.append(vnorm((x, r * slope * 0.15, z)))
    base = 1
    tip = len(verts)
    verts.append((0.0, 1.0, 0.0))
    norms.append((0.0, 1.0, 0.0))
    idx = []
    for ix in range(slices):
        nxt = (ix + 1) % slices
        idx.extend((0, base + nxt, base + ix))
    for iy in range(stacks):
        for ix in range(slices):
            nxt = (ix + 1) % slices
            a = base + iy * slices + ix
            b = base + (iy + 1) * slices + ix
            an = base + iy * slices + nxt
            bn = base + (iy + 1) * slices + nxt
            if iy == stacks - 1:
                idx.extend((a, an, tip))
            else:
                idx.extend((a, b, an, an, b, bn))
    return verts, norms, idx


def arc_tube(length, radius, bend_deg, stacks, slices):
    bend = math.radians(bend_deg)
    curve = length / max(bend, 0.001)
    verts = []
    norms = []
    idx = []
    rings = []
    for iy in range(stacks + 1):
        t = iy / stacks
        ang = t * bend
        cx = 0.0
        cy = curve * math.sin(ang)
        cz = -curve * (1.0 - math.cos(ang))
        tangent = vnorm((0.0, math.cos(ang), -math.sin(ang)))
        side = (1.0, 0.0, 0.0)
        up = vnorm((
            tangent[1] * side[2] - tangent[2] * side[1],
            tangent[2] * side[0] - tangent[0] * side[2],
            tangent[0] * side[1] - tangent[1] * side[0],
        ))
        r = radius * (1.0 - t * 0.62)
        ring = []
        for ix in range(slices):
            a = ix / slices * math.tau
            n = vadd(vmul(side, math.cos(a) * r), vmul(up, math.sin(a) * r))
            ring.append((vadd((cx, cy, cz), n), vnorm(n)))
        rings.append(ring)
    for ring in rings:
        for p, n in ring:
            verts.append(p)
            norms.append(n)
    for iy in range(stacks):
        for ix in range(slices):
            nxt = (ix + 1) % slices
            a = iy * slices + ix
            b = (iy + 1) * slices + ix
            an = iy * slices + nxt
            bn = (iy + 1) * slices + nxt
            idx.extend((a, b, an, an, b, bn))
    return verts, norms, idx


def torus(major_n, minor_n):
    verts = []
    norms = []
    idx = []
    for i in range(major_n):
        a = i / major_n * math.tau
        ca, sa = math.cos(a), math.sin(a)
        for j in range(minor_n):
            b = j / minor_n * math.tau
            cb, sb = math.cos(b), math.sin(b)
            n = (ca * cb, sb, sa * cb)
            verts.append(n)
            norms.append(vnorm(n))
    for i in range(major_n):
        for j in range(minor_n):
            i2 = (i + 1) % major_n
            j2 = (j + 1) % minor_n
            a = i * minor_n + j
            b = i2 * minor_n + j
            c = i * minor_n + j2
            d = i2 * minor_n + j2
            idx.extend((a, b, c, c, b, d))
    return verts, norms, idx


UNIT = {
    "sphere": sphere(8, 12),
    "sphere_hi": sphere(10, 16),
    "cone": cone(6, 10),
    "horn": arc_tube(1.0, 0.12, 70, 8, 8),
    "torus": torus(16, 8),
}


def transform_part(kind, bone, center, radii, rot, scale_len=1.0):
    verts, norms, idx = UNIT[kind]
    q = euler_quat(*rot)
    r = quat_mat(q)
    out_v = []
    out_n = []
    for v, n in zip(verts, norms):
        radius = radii[0]
        p = (v[0] * radius, v[1] * radii[1] * scale_len, v[2] * radius)
        if kind == "torus":
            major, minor = radii[0], radii[1]
            p = (v[0] * minor + math.cos(0) * 0, v[1] * minor, v[2] * minor)
            # UNIT torus is a tube of radius 1 around the origin. Rebuild on the ring.
        out_v.append(vadd(center, mat_dir(mat_trs((0, 0, 0), q), p)))
        nn = (n[0] / radii[0], n[1] / max(radii[1], 1e-4), n[2] / radii[2])
        out_n.append(vnorm(mat_dir(mat_trs((0, 0, 0), q), nn)))
    return out_v, out_n, idx


def torus_part(center, major, minor, rot):
    verts, norms, idx = UNIT["torus"]
    q = euler_quat(*rot)
    out_v = []
    out_n = []
    major_n, minor_n = 16, 8
    k = 0
    built = []
    built_n = []
    for i in range(major_n):
        a = i / major_n * math.tau
        ca, sa = math.cos(a), math.sin(a)
        for j in range(minor_n):
            b = j / minor_n * math.tau
            cb, sb = math.cos(b), math.sin(b)
            # Ring in the XZ plane, tube radius minor, ring radius major.
            n = (ca * cb, sb, sa * cb)
            p = (ca * (major + minor * cb), minor * sb, sa * (major + minor * cb))
            built.append(p)
            built_n.append(n)
            k += 1
    for p, n in zip(built, built_n):
        out_v.append(vadd(center, mat_dir(mat_trs((0, 0, 0), q), p)))
        out_n.append(vnorm(mat_dir(mat_trs((0, 0, 0), q), n)))
    return out_v, out_n, idx


class Prim:
    def __init__(self, positions, normals, indices, joints, weights, color, rough, metal):
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.joints = joints
        self.weights = weights
        self.color = color
        self.rough = rough
        self.metal = metal


def add_weighted(prims, kind, bone, parent_bone, center, radii, rot, color, worlds, scale, rough=0.82, metal=0.0, scale_len=1.0):
    if kind == "torus":
        local_v, local_n, idx = torus_part(center, radii[0], radii[1], rot)
    elif kind == "horn":
        verts, norms, idx = arc_tube(radii[1], radii[0], 70, 8, 8)
        q = euler_quat(*rot)
        local_v = [vadd(center, mat_dir(mat_trs((0, 0, 0), q), p)) for p in verts]
        local_n = [vnorm(mat_dir(mat_trs((0, 0, 0), q), n)) for n in norms]
    else:
        local_v, local_n, idx = transform_part(kind if kind != "sphere_hi" else "sphere_hi", bone, center, radii, rot, scale_len)
    world = worlds[BONE_INDEX[bone]]
    positions = [mat_point(world, p) for p in local_v]
    normals = [vnorm(mat_dir(world, n)) for n in local_n]
    joint = BONE_INDEX[bone]
    parent = BONE_INDEX[parent_bone] if parent_bone else joint
    joints = []
    weights = []
    for p in local_v:
        # Blend the cap nearest the parent joint so elbows and wrists do not split.
        blend = 0.0
        if parent != joint and kind in ("sphere", "sphere_hi"):
            blend = max(0.0, min(1.0, (p[1] + radii[1] * 0.15) / max(radii[1], 0.001)))
            blend *= 0.55
        joints.append((joint, parent, 0, 0))
        weights.append((1.0 - blend, blend, 0.0, 0.0))
    prims.append(Prim(positions, normals, idx, joints, weights, color, rough, metal))


def fur(hex_color):
    return tuple(c / 255.0 for c in hex_color)


def build_parts(name, worlds, scale):
    prims = []
    s = scale

    def E(bone, parent, center, radii, color, rot=(0, 0, 0), kind="sphere", rough=0.84, metal=0.0):
        c = tuple(v * s for v in center)
        r = tuple(v * s for v in radii)
        add_weighted(prims, kind, bone, parent, c, r, rot, color, worlds, s, rough, metal)

    coat = fur((62, 74, 50))
    shirt = fur((230, 220, 200))
    charcoal = fur((42, 46, 52))
    olive = fur((74, 84, 52))
    red = fur((122, 36, 50))
    brass = fur((201, 164, 76))
    black = fur((22, 22, 24))
    cream = fur((232, 224, 208))
    horn_c = fur((92, 80, 64))
    beak_c = fur((28, 28, 30))
    skin_eye = fur((236, 230, 214))
    pupil = fur((18, 16, 14))

    if name == "kaya":
        body = fur((138, 132, 116))
        E("Hips", None, (0, 0.02, 0), (0.14, 0.10, 0.12), body)
        E("Spine", "Hips", (0, 0.04, -0.01), (0.16, 0.12, 0.11), coat)
        E("Chest", "Spine", (0, 0.02, -0.02), (0.20, 0.14, 0.12), coat)
        E("Chest", "Spine", (0, 0.00, 0.05), (0.11, 0.12, 0.07), shirt)
        E("Neck", "Chest", (0, 0.02, 0), (0.07, 0.06, 0.07), body)
        E("Head", "Neck", (0, 0.02, 0.01), (0.11, 0.13, 0.12), body, kind="sphere_hi")
        E("Muzzle", "Head", (0, -0.01, 0.06), (0.055, 0.045, 0.07), body)
        E("Muzzle", "Head", (0, -0.06, 0.03), (0.05, 0.055, 0.045), fur((116, 108, 92)))
        E("EarL", "Head", (0, 0.03, 0), (0.035, 0.06, 0.02), body)
        E("EarR", "Head", (0, 0.03, 0), (0.035, 0.06, 0.02), body)
        E("HornL", "Head", (0, 0.0, 0), (0.028, 0.36, 0.028), horn_c, kind="horn", rough=0.55)
        E("HornR", "Head", (0, 0.0, 0), (0.028, 0.36, 0.028), horn_c, kind="horn", rough=0.55)
        E("Head", "Neck", (-0.045, 0.02, 0.09), (0.018, 0.016, 0.012), skin_eye, rough=0.35)
        E("Head", "Neck", (0.045, 0.02, 0.09), (0.018, 0.016, 0.012), skin_eye, rough=0.35)
        E("Head", "Neck", (-0.045, 0.02, 0.10), (0.009, 0.009, 0.006), pupil, rough=0.3)
        E("Head", "Neck", (0.045, 0.02, 0.10), (0.009, 0.009, 0.006), pupil, rough=0.3)
    elif name == "sis":
        body = fur((168, 140, 102))
        pale = fur((214, 196, 170))
        E("Hips", None, (0, 0.02, 0), (0.12, 0.09, 0.11), body)
        E("Spine", "Hips", (0, 0.04, -0.01), (0.14, 0.11, 0.10), charcoal)
        E("Chest", "Spine", (0, 0.03, -0.015), (0.18, 0.13, 0.11), charcoal)
        E("Chest", "Spine", (0, 0.01, 0.04), (0.09, 0.10, 0.05), black)
        E("Neck", "Chest", (0, 0.03, 0.01), (0.08, 0.07, 0.08), pale)
        E("Head", "Neck", (0, 0.03, 0.02), (0.11, 0.10, 0.12), body, kind="sphere_hi")
        E("Head", "Neck", (0, -0.02, 0.02), (0.12, 0.08, 0.09), pale)
        E("Muzzle", "Head", (0, -0.02, 0.07), (0.04, 0.035, 0.06), pale)
        E("EarL", "Head", (0, 0.05, 0), (0.03, 0.07, 0.02), body)
        E("EarR", "Head", (0, 0.05, 0), (0.03, 0.07, 0.02), body)
        E("EarL", "Head", (0, 0.12, 0), (0.012, 0.045, 0.012), black, kind="cone")
        E("EarR", "Head", (0, 0.12, 0), (0.012, 0.045, 0.012), black, kind="cone")
        E("Head", "Neck", (-0.04, 0.02, 0.10), (0.02, 0.018, 0.012), fur((190, 206, 176)), rough=0.3)
        E("Head", "Neck", (0.04, 0.02, 0.10), (0.02, 0.018, 0.012), fur((190, 206, 176)), rough=0.3)
        E("Head", "Neck", (-0.04, 0.02, 0.11), (0.009, 0.012, 0.006), pupil, rough=0.25)
        E("Head", "Neck", (0.04, 0.02, 0.11), (0.009, 0.012, 0.006), pupil, rough=0.25)
        for side, bone in ((-1, "ForearmL"), (1, "ForearmR")):
            for k, spot in enumerate((0.02, -0.02, 0.05)):
                E(bone, "UpperArmL" if side < 0 else "UpperArmR", (0.02 * side, spot, 0.03), (0.012, 0.01, 0.01), black)
    elif name == "kok":
        E("Hips", None, (0, 0.01, 0), (0.15, 0.10, 0.13), black)
        E("Spine", "Hips", (0, 0.04, 0), (0.17, 0.12, 0.12), black)
        E("Chest", "Spine", (0, 0.02, -0.01), (0.20, 0.13, 0.13), olive)
        E("Chest", "Spine", (0, 0.00, 0.05), (0.10, 0.11, 0.05), black)
        E("Neck", "Chest", (0, 0.02, 0), (0.09, 0.07, 0.09), cream)
        E("Head", "Neck", (0, 0.04, 0.01), (0.12, 0.11, 0.13), black, kind="sphere_hi")
        E("Head", "Neck", (0, 0.07, 0.04), (0.045, 0.12, 0.06), cream)
        E("Muzzle", "Head", (0, -0.03, 0.07), (0.055, 0.045, 0.06), cream)
        E("EarL", "Head", (0, 0.02, 0), (0.04, 0.035, 0.02), black)
        E("EarR", "Head", (0, 0.02, 0), (0.04, 0.035, 0.02), black)
        E("Head", "Neck", (-0.04, 0.02, 0.10), (0.016, 0.014, 0.01), skin_eye, rough=0.35)
        E("Head", "Neck", (0.04, 0.02, 0.10), (0.016, 0.014, 0.01), skin_eye, rough=0.35)
        E("Head", "Neck", (-0.04, 0.02, 0.11), (0.008, 0.008, 0.005), pupil)
        E("Head", "Neck", (0.04, 0.02, 0.11), (0.008, 0.008, 0.005), pupil)
    elif name == "nida":
        feather = fur((214, 186, 146))
        speck = fur((120, 86, 54))
        E("Hips", None, (0, 0.02, 0), (0.09, 0.07, 0.08), black)
        E("Spine", "Hips", (0, 0.03, 0), (0.11, 0.09, 0.09), red)
        E("Chest", "Spine", (0, 0.02, 0.00), (0.16, 0.12, 0.13), red)
        E("Neck", "Chest", (0, 0.02, 0), (0.06, 0.05, 0.06), feather)
        E("Head", "Neck", (0, 0.05, 0.02), (0.13, 0.12, 0.13), feather, kind="sphere_hi")
        E("Muzzle", "Head", (0, -0.015, 0.08), (0.022, 0.05, 0.022), fur((196, 176, 130)), kind="cone", rot=(78, 0, 0), rough=0.45)
        E("Head", "Neck", (-0.05, 0.02, 0.09), (0.038, 0.04, 0.02), skin_eye, rough=0.25)
        E("Head", "Neck", (0.05, 0.02, 0.09), (0.038, 0.04, 0.02), skin_eye, rough=0.25)
        E("Head", "Neck", (-0.05, 0.02, 0.11), (0.02, 0.022, 0.01), fur((40, 24, 16)))
        E("Head", "Neck", (0.05, 0.02, 0.11), (0.02, 0.022, 0.01), fur((40, 24, 16)))
        for sx, sy in ((-0.06, 0.08), (0.05, 0.09), (-0.02, 0.11), (0.07, 0.04), (-0.08, 0.02)):
            E("Head", "Neck", (sx, sy, 0.06), (0.012, 0.01, 0.01), speck)
        E("Head", "Neck", (0.11, -0.02, 0.02), (0.012, 0.02, 0.012), brass, rough=0.35, metal=0.8)
    elif name == "kul":
        gray = fur((138, 142, 146))
        E("Hips", None, (0, 0.02, 0), (0.11, 0.08, 0.10), gray)
        E("Spine", "Hips", (0, 0.04, 0), (0.13, 0.11, 0.10), gray)
        E("Chest", "Spine", (0, 0.02, 0), (0.15, 0.12, 0.11), gray)
        E("Neck", "Chest", (0, 0.02, 0), (0.07, 0.06, 0.07), gray)
        E("Neck", "Chest", (0, 0.04, 0), (0.075, 0.008, 0.075), brass, kind="torus", rough=0.32, metal=0.85)
        E("Head", "Neck", (0, 0.04, 0.01), (0.09, 0.10, 0.11), black, kind="sphere_hi")
        E("Muzzle", "Head", (0, 0.0, 0.07), (0.032, 0.16, 0.032), beak_c, kind="cone", rot=(78, 0, 0), rough=0.4)
        E("Head", "Neck", (-0.035, 0.03, 0.08), (0.016, 0.016, 0.01), fur((90, 62, 40)), rough=0.3)
        E("Head", "Neck", (0.035, 0.03, 0.08), (0.016, 0.016, 0.01), fur((90, 62, 40)), rough=0.3)
        E("Head", "Neck", (-0.035, 0.03, 0.09), (0.008, 0.008, 0.005), pupil)
        E("Head", "Neck", (0.035, 0.03, 0.09), (0.008, 0.008, 0.005), pupil)
    elif name == "dere":
        body = fur((139, 90, 60))
        muzzle = fur((230, 214, 196))
        E("Hips", None, (0, 0.02, 0), (0.12, 0.09, 0.11), body)
        E("Spine", "Hips", (0, 0.04, 0), (0.13, 0.11, 0.10), shirt)
        E("Chest", "Spine", (0, 0.02, 0.01), (0.15, 0.13, 0.11), shirt)
        E("Neck", "Chest", (0, 0.02, 0), (0.07, 0.06, 0.07), muzzle)
        E("Head", "Neck", (0, 0.04, 0.00), (0.11, 0.10, 0.12), body, kind="sphere_hi")
        E("Muzzle", "Head", (0, -0.03, 0.06), (0.07, 0.055, 0.07), muzzle)
        E("EarL", "Head", (0, 0.015, 0), (0.028, 0.03, 0.018), body)
        E("EarR", "Head", (0, 0.015, 0), (0.028, 0.03, 0.018), body)
        E("Head", "Neck", (-0.04, 0.025, 0.09), (0.026, 0.028, 0.016), skin_eye, rough=0.28)
        E("Head", "Neck", (0.04, 0.025, 0.09), (0.026, 0.028, 0.016), skin_eye, rough=0.28)
        E("Head", "Neck", (-0.04, 0.025, 0.105), (0.013, 0.014, 0.008), pupil)
        E("Head", "Neck", (0.04, 0.025, 0.105), (0.013, 0.014, 0.008), pupil)
        E("Chest", "Spine", (0, -0.08, 0.08), (0.012, 0.012, 0.008), brass, rough=0.3, metal=0.75)
    else:
        raise SystemExit(name)

    # Shared limbs. Birds keep dark feathered hands; the coat covers the upper arm.
    limb, hand, sleeve = {
        "kaya": (fur((138, 132, 116)), fur((138, 132, 116)), coat),
        "sis": (fur((168, 140, 102)), fur((190, 164, 126)), charcoal),
        "kok": (black, black, olive),
        "nida": (fur((186, 156, 120)), fur((186, 156, 120)), red),
        "kul": (black, black, fur((138, 142, 146))),
        "dere": (fur((139, 90, 60)), fur((139, 90, 60)), shirt),
    }[name]
    for side, upper, fore, hand_b, thumb, index, parent_u, parent_f, parent_h in (
        ("L", "UpperArmL", "ForearmL", "HandL", "ThumbL", "IndexL", "ClavicleL", "UpperArmL", "ForearmL"),
        ("R", "UpperArmR", "ForearmR", "HandR", "ThumbR", "IndexR", "ClavicleR", "UpperArmR", "ForearmR"),
    ):
        E(upper, parent_u, (0, -0.10, 0), (0.055, 0.12, 0.055), sleeve)
        bare = limb if name == "dere" else sleeve
        E(fore, parent_f, (0, -0.08, 0), (0.045, 0.10, 0.045), bare if name != "dere" else limb)
        E(hand_b, parent_h, (0, -0.03, 0.01), (0.045, 0.04, 0.035), hand)
        E(thumb, hand_b, (0, -0.02, 0), (0.016, 0.028, 0.016), hand)
        E(index, hand_b, (0, -0.025, 0), (0.014, 0.032, 0.014), hand)
    for side, thigh, shin, foot, pu, pf in (
        ("L", "ThighL", "ShinL", "FootL", "Hips", "ThighL"),
        ("R", "ThighR", "ShinR", "FootR", "Hips", "ThighR"),
    ):
        cloth = sleeve if name in ("kaya", "sis") else limb
        E(thigh, pu, (0, -0.12, 0), (0.06, 0.13, 0.06), cloth if name != "nida" else red)
        E(shin, pf, (0, -0.11, 0), (0.045, 0.12, 0.045), limb)
        E(foot, shin if False else "ShinL" if side == "L" else "ShinR", (0, -0.02, 0.05), (0.04, 0.025, 0.07), limb)
    return prims


CLIPS = {
    "SitIdle": {
        "loop": True,
        "keys": [0.0, 1.2, 2.4],
        "deltas": [
            {},
            {"Chest": (2.0, 0, 0), "Head": (1.2, 0, 0), "EarL": (0, 0, 5), "EarR": (0, 0, -5)},
            {},
        ],
    },
    "PlayCard": {
        "loop": False,
        "keys": [0.0, 0.38, 0.62, 1.15],
        "deltas": [
            {},
            {
                "UpperArmR": (-12, 4, 6),
                "ForearmR": (18, 0, 0),
                "HandR": (6, -4, 0),
                "IndexR": (-8, 0, 0),
                "Chest": (0, -4, 0),
            },
            {
                "UpperArmR": (-20, 8, 10),
                "ForearmR": (38, 0, 0),
                "HandR": (12, -8, 0),
                "IndexR": (-18, 0, 0),
                "Chest": (0, -8, 0),
            },
            {},
        ],
    },
    "LeanIn": {
        "loop": False,
        "keys": [0.0, 0.55],
        "deltas": [
            {},
            {"Spine": (10, 0, 0), "Chest": (8, 0, 0), "Neck": (6, 0, 0), "Head": (6, 0, 0)},
        ],
    },
    "LeanBack": {
        "loop": False,
        "keys": [0.0, 0.55],
        "deltas": [
            {},
            {"Spine": (-14, 0, 0), "Chest": (-10, 0, 0), "Neck": (-6, 0, 0), "Head": (-8, 0, 0)},
        ],
    },
    "WatchLeft": {
        "loop": False,
        "keys": [0.0, 0.4],
        "deltas": [{}, {"Neck": (0, 10, 0), "Head": (0, 16, 0)}],
    },
    "WatchRight": {
        "loop": False,
        "keys": [0.0, 0.4],
        "deltas": [{}, {"Neck": (0, -10, 0), "Head": (0, -16, 0)}],
    },
}


def pack_glb(name, scale):
    locals_ = pose_locals(scale)
    worlds = world_matrices(locals_)
    prims = build_parts(name, worlds, scale)
    ibms = [mat_inv_rigid(w) for w in worlds]

    materials = []
    mat_index = {}
    primitives = []
    blobs = []

    def align(n=4):
        while sum(len(b) for b in blobs) % n:
            blobs.append(b"\x00")

    def push(data):
        align(4)
        offset = sum(len(b) for b in blobs)
        blobs.append(data)
        return offset

    def accessor(data, ctype, count, atype, target=None):
        view = {
            "buffer": 0,
            "byteOffset": push(data),
            "byteLength": len(data),
        }
        if target:
            view["target"] = target
        buffer_views.append(view)
        acc = {
            "bufferView": len(buffer_views) - 1,
            "componentType": ctype,
            "count": count,
            "type": atype,
        }
        accessors.append(acc)
        return len(accessors) - 1

    buffer_views = []
    accessors = []

    for prim in prims:
        key = (prim.color, prim.rough, prim.metal)
        if key not in mat_index:
            mat_index[key] = len(materials)
            materials.append({
                "name": "m%d" % len(materials),
                "pbrMetallicRoughness": {
                    "baseColorFactor": [prim.color[0], prim.color[1], prim.color[2], 1],
                    "metallicFactor": prim.metal,
                    "roughnessFactor": prim.rough,
                },
            })
        pos = b"".join(struct.pack("<3f", *p) for p in prim.positions)
        nrm = b"".join(struct.pack("<3f", *n) for n in prim.normals)
        joints = b"".join(struct.pack("<4H", *j) for j in prim.joints)
        weights = b"".join(struct.pack("<4f", *w) for w in prim.weights)
        indices = b"".join(struct.pack("<H", i) for i in prim.indices)
        xs = [p[0] for p in prim.positions]
        ys = [p[1] for p in prim.positions]
        zs = [p[2] for p in prim.positions]
        pa = accessor(pos, 5126, len(prim.positions), "VEC3", 34962)
        accessors[pa]["min"] = [min(xs), min(ys), min(zs)]
        accessors[pa]["max"] = [max(xs), max(ys), max(zs)]
        na = accessor(nrm, 5126, len(prim.normals), "VEC3", 34962)
        ja = accessor(joints, 5123, len(prim.joints), "VEC4", 34962)
        wa = accessor(weights, 5126, len(prim.weights), "VEC4", 34962)
        ia = accessor(indices, 5123, len(prim.indices), "SCALAR", 34963)
        primitives.append({
            "attributes": {"POSITION": pa, "NORMAL": na, "JOINTS_0": ja, "WEIGHTS_0": wa},
            "indices": ia,
            "material": mat_index[key],
        })

    ibm_bytes = b"".join(
        struct.pack("<16f", *[m[c][r] for c in range(4) for r in range(4)])
        for m in ibms
    )
    # Column-major: element (r,c) stored at c*4+r. The loop above writes
    # m[c][r] which is row c, column r if m is row-major. glTF wants column c,
    # row r as m_row_r_col_c. Row-major m[r][c] in column-major order is
    # for c in cols for r in rows: m[r][c].
    ibm_bytes = b"".join(
        struct.pack("<16f", *[m[r][c] for c in range(4) for r in range(4)])
        for m in ibms
    )
    ibm_acc = accessor(ibm_bytes, 5126, len(ibms), "MAT4")

    nodes = []
    for i, (bone_name, _parent, _t, _e) in enumerate(BONES):
        _n, t, q = locals_[i]
        children = [j for j, (bn, parent, *_) in enumerate(BONES) if parent == bone_name]
        node = {"name": bone_name, "translation": list(t), "rotation": list(q)}
        if children:
            node["children"] = children
        nodes.append(node)
    mesh_node = {"name": "Mesh", "mesh": 0, "skin": 0}
    nodes.append(mesh_node)
    root = {
        "name": name,
        "children": [BONE_INDEX["Hips"], len(BONES)],
        "extras": {"preset": name, "skeleton": "seat-v1", "unit": "meter", "forward": "+Z"},
    }
    nodes.append(root)

    animations = []
    for clip, spec in CLIPS.items():
        channels = []
        samplers = []
        times = spec["keys"]
        # Gather bones touched by any key so a clip stays sparse.
        touched = set()
        for delta in spec["deltas"]:
            touched.update(delta)
        for bone in sorted(touched):
            quats = []
            prev = None
            for delta in spec["deltas"]:
                base = BONES[BONE_INDEX[bone]][3]
                d = delta.get(bone, (0, 0, 0))
                q = euler_quat(base[0] + d[0], base[1] + d[1], base[2] + d[2])
                if prev is not None:
                    q = quat_align(prev, q)
                prev = q
                quats.append(q)
            t_off = push(b"".join(struct.pack("<f", t) for t in times))
            t_view = {"buffer": 0, "byteOffset": t_off, "byteLength": 4 * len(times)}
            buffer_views.append(t_view)
            t_acc = len(accessors)
            accessors.append({
                "bufferView": len(buffer_views) - 1,
                "componentType": 5126,
                "count": len(times),
                "type": "SCALAR",
                "min": [times[0]],
                "max": [times[-1]],
            })
            q_off = push(b"".join(struct.pack("<4f", *q) for q in quats))
            q_view = {"buffer": 0, "byteOffset": q_off, "byteLength": 16 * len(quats)}
            buffer_views.append(q_view)
            q_acc = len(accessors)
            accessors.append({
                "bufferView": len(buffer_views) - 1,
                "componentType": 5126,
                "count": len(quats),
                "type": "VEC4",
            })
            samplers.append({"input": t_acc, "output": q_acc, "interpolation": "LINEAR"})
            channels.append({
                "sampler": len(samplers) - 1,
                "target": {"node": BONE_INDEX[bone], "path": "rotation"},
            })
        animations.append({
            "name": clip,
            "channels": channels,
            "samplers": samplers,
            "extras": {"loop": spec["loop"]},
        })

    blob = b"".join(blobs)
    gltf = {
        "asset": {"version": "2.0", "generator": "25-40 seat-v1"},
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": [{"name": name, "primitives": primitives}],
        "skins": [{
            "name": "Seat",
            "joints": list(range(len(BONES))),
            "inverseBindMatrices": ibm_acc,
            "skeleton": BONE_INDEX["Hips"],
        }],
        "materials": materials,
        "animations": animations,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(blob)}],
    }
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(text) % 4:
        text += b" "
    while len(blob) % 4:
        blob += b"\x00"
    chunks = b"".join((
        struct.pack("<I4s", len(text), b"JSON"),
        text,
        struct.pack("<I4s", len(blob), b"BIN\x00"),
        blob,
    ))
    glb = struct.pack("<4sII", b"glTF", 2, 12 + len(chunks)) + chunks
    return glb, worlds, locals_


def write_png(path, width, height, rgb):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(rgb[y * width * 3:(y + 1) * width * 3])
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}


def draw_text(rgb, width, height, text, x, y, color=(232, 220, 190)):
    cursor = x
    for ch in text:
        glyph = FONT.get(ch, FONT[" "])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    for sy in range(2):
                        for sx in range(2):
                            px = cursor + gx * 2 + sx
                            py = y + gy * 2 + sy
                            if 0 <= px < width and 0 <= py < height:
                                i = (py * width + px) * 3
                                rgb[i:i + 3] = bytes(color)
        cursor += 12


def render_sheet(path, poses):
    cols = len(poses)
    pw, ph = 320, 460
    width, height = pw * cols, ph
    rgb = bytearray([22, 16, 14]) * (width * height)
    depth = [1e9] * (width * height)
    light = vnorm((0.25, 0.85, 0.45))
    for col, (label, worlds, prims) in enumerate(poses):
        ox = col * pw
        target = (0.0, 0.82, 0.08)
        eye = (0.42, 0.98, 1.05)
        forward = vnorm(vsub(target, eye))
        right = vnorm((forward[2], 0, -forward[0]))
        up = vnorm((
            right[1] * forward[2] - right[2] * forward[1],
            right[2] * forward[0] - right[0] * forward[2],
            right[0] * forward[1] - right[1] * forward[0],
        ))
        # Recompute a proper camera basis: right = forward cross world-up, then up.
        world_up = (0, 1, 0)
        right = vnorm((
            forward[1] * world_up[2] - forward[2] * world_up[1],
            forward[2] * world_up[0] - forward[0] * world_up[2],
            forward[0] * world_up[1] - forward[1] * world_up[0],
        ))
        up = (
            right[1] * forward[2] - right[2] * forward[1],
            right[2] * forward[0] - right[0] * forward[2],
            right[0] * forward[1] - right[1] * forward[0],
        )

        def project(p):
            d = vsub(p, eye)
            z = vdot(d, forward)
            if z < 0.05:
                return None
            x = vdot(d, right) / z
            y = vdot(d, up) / z
            sx = ox + pw * 0.5 + x * pw * 1.05
            sy = ph * 0.56 - y * ph * 1.05
            return sx, sy, z

        def shade(normal, color):
            nd = max(0.0, vdot(normal, light))
            warm = (1.0, 0.9, 0.72)
            amb = (0.22, 0.16, 0.13)
            return tuple(max(0, min(255, int(255 * color[c] * (amb[c] + nd * warm[c])))) for c in range(3))

        # Felt slab.
        felt_y = worlds[BONE_INDEX["HandR"]][1][3] - 0.035
        felt = [
            (-0.55, felt_y, 0.08), (0.55, felt_y, 0.08), (0.55, felt_y, 0.78), (-0.55, felt_y, 0.78),
        ]
        draw_tri(rgb, depth, width, height, project, felt[0], felt[1], felt[2], (0, 1, 0), (16, 78, 58))
        draw_tri(rgb, depth, width, height, project, felt[0], felt[2], felt[3], (0, 1, 0), (16, 78, 58))
        for prim in prims:
            color = shade  # placeholder to keep lint calm
            for t in range(0, len(prim.indices), 3):
                ia, ib, ic = prim.indices[t:t + 3]
                pa, pb, pc = prim.positions[ia], prim.positions[ib], prim.positions[ic]
                n = vnorm((
                    (pb[1] - pa[1]) * (pc[2] - pa[2]) - (pb[2] - pa[2]) * (pc[1] - pa[1]),
                    (pb[2] - pa[2]) * (pc[0] - pa[0]) - (pb[0] - pa[0]) * (pc[2] - pa[2]),
                    (pb[0] - pa[0]) * (pc[1] - pa[1]) - (pb[1] - pa[1]) * (pc[0] - pa[0]),
                ))
                if vdot(n, forward) > 0.15:
                    continue
                colr = shade(n, prim.color)
                draw_tri(rgb, depth, width, height, project, pa, pb, pc, n, colr)
        draw_text(rgb, width, height, label, ox + 16, ph - 28)
    write_png(path, width, height, rgb)


def draw_tri(rgb, depth, width, height, project, a, b, c, _n, color):
    pa, pb, pc = project(a), project(b), project(c)
    if not pa or not pb or not pc:
        return
    pts = (pa, pb, pc)
    minx = max(0, int(min(p[0] for p in pts)))
    maxx = min(width - 1, int(max(p[0] for p in pts)) + 1)
    miny = max(0, int(min(p[1] for p in pts)))
    maxy = min(height - 1, int(max(p[1] for p in pts)) + 1)
    area = (pb[0] - pa[0]) * (pc[1] - pa[1]) - (pc[0] - pa[0]) * (pb[1] - pa[1])
    if abs(area) < 0.5:
        return
    for y in range(miny, maxy + 1):
        for x in range(minx, maxx + 1):
            w0 = (pb[0] - x) * (pc[1] - y) - (pc[0] - x) * (pb[1] - y)
            w1 = (pc[0] - x) * (pa[1] - y) - (pa[0] - x) * (pc[1] - y)
            w2 = (pa[0] - x) * (pb[1] - y) - (pb[0] - x) * (pa[1] - y)
            if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
                z = (w0 * pa[2] + w1 * pb[2] + w2 * pc[2]) / area
                i = y * width + x
                if z < depth[i]:
                    depth[i] = z
                    o = i * 3
                    rgb[o:o + 3] = bytes(color)


def skeleton_manifest():
    bones = []
    for name, parent, t, euler in BONES:
        bones.append({"name": name, "parent": parent, "translation": list(t), "eulerXYZ": list(euler)})
    return {
        "skeleton": "seat-v1",
        "unit": "meter",
        "up": "+Y",
        "forward": "+Z",
        "bind": "seated, both hands together over the felt",
        "bones": bones,
        "clips": {name: {"loop": spec["loop"], "seconds": spec["keys"][-1]} for name, spec in CLIPS.items()},
        "presets": ["kaya", "sis", "kok", "nida", "kul", "dere"],
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    GODOT.mkdir(parents=True, exist_ok=True)
    scales = {"kaya": 1.06, "sis": 1.0, "kok": 0.98, "nida": 0.86, "kul": 0.96, "dere": 1.0}
    sheet = []
    reach = []
    for name, scale in scales.items():
        glb, worlds, _locals = pack_glb(name, scale)
        path = OUT / f"{name}.glb"
        path.write_bytes(glb)
        (GODOT / f"{name}.glb").write_bytes(glb)
        hand = worlds[BONE_INDEX["HandR"]]
        head = worlds[BONE_INDEX["Head"]]
        print(
            f"{name:5} {path.stat().st_size:7}  head=({head[0][3]:.2f},{head[1][3]:.2f},{head[2][3]:.2f})"
            f"  handR=({hand[0][3]:.2f},{hand[1][3]:.2f},{hand[2][3]:.2f})"
        )
        prims = build_parts(name, worlds, scale)
        sheet.append((name.upper(), worlds, prims))
        locals_play = pose_locals(scale, CLIPS["PlayCard"]["deltas"][1])
        worlds_play = world_matrices(locals_play)
        reach.append((name.upper(), worlds_play, build_parts(name, worlds_play, scale)))
    (OUT / "iskelet.json").write_text(json.dumps(skeleton_manifest(), indent=2) + "\n")
    render_sheet(OUT / "onizleme-oturum.png", sheet)
    render_sheet(OUT / "onizleme-kart.png", reach)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
