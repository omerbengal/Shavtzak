"""Generates assets/animations/download_failed.json, the Lottie animation of
the in-app refresh's "ההורדה נעצרה" screen (web/app_refresh.js). The same
character as salute_loading.json (tool/salute_loading_gen.py), crying.

Run from shavtzak/ (Python 3, no packages needed):
    python3 tool/download_failed_gen.py assets/animations/download_failed.json
The JSON is generated: change this script, never hand-edit the JSON.

512x512, 30 fps, transparent. It CONTINUES the salute animation: the page
switches to it at the end of a salute loop, and frame 0 here is drawn exactly
like the salute's frame 0 (= its last frame): saluting smile, helmet on the
ground, blue cloud with the download arrow. Three parts, played by
web/app_refresh.js as playSegments([[0, LOOP_START], [LOOP_START, TOTAL]]):
  0 .. INTRO            the turn: the hand drops, the eyes squeeze shut, the
                        smile becomes a wail, sad brows, the cloud greys and
                        its arrow becomes a red ✕
  INTRO .. LOOP_START   the first cry (tears only from its start on)
  LOOP_START .. TOTAL   the cry again, looped forever: tears in flight at its
                        end are the ones at its start, so it is seamless
The cry: the face heaves on every sob (3 per cycle), the mouth trembles, tears
run down the cheeks and squirt from both eyes in arcs (exact gravity, baked
per frame) over the helmet, splashing into a puddle on each side.
Tunables: the constants near the top (INTRO, CYCLE, SOB, EMIT, tear speeds).

The salute's shapes and frame-0 poses are copied here (FACE, SALUTE, GROUND,
hand/eye/mouth/face/cloud/arrow shapes): change them there, change them here.
To look at it: open the app with ?refreshdemo=failed in the address.
"""
import math
import json
import sys

FPS = 30
INTRO = 20                 # the turn from the salute
CYCLE = 90                 # one cry cycle (3 s)
LOOP_START = INTRO + CYCLE
TOTAL = LOOP_START + CYCLE
W = H = 512
R = lambda x: round(x, 2)


# ---------- helpers (as in salute_loading_gen.py) ----------
def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def prog(f, a, b):
    return clamp((f - a) / (b - a))


def ease_io(t):
    t = clamp(t)
    return 4 * t * t * t if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def ease_out(t):
    t = clamp(t)
    return 1 - (1 - t) ** 3


def ease_in(t):
    t = clamp(t)
    return t * t


def ease_out_back(t, s=1.9):
    t = clamp(t) - 1
    return 1 + (s + 1) * t ** 3 + s * t ** 2


def static(v):
    return {"a": 0, "k": v}


def anim(values):
    """values: list of (frame, list) — linear keyframes, holds deduplicated."""
    keep = [values[0]]
    for idx in range(1, len(values) - 1):
        a, b, c = keep[-1], values[idx], values[idx + 1]
        u = (b[0] - a[0]) / (c[0] - a[0])
        if any(abs(av + (cv - av) * u - bv) > 0.25 for av, bv, cv in zip(a[1], b[1], c[1])):
            keep.append(b)
    keep.append(values[-1])
    kfs = []
    for f, v in keep:
        d = len(v)
        kfs.append({"t": f, "s": v, "i": {"x": [1] * d, "y": [1] * d},
                    "o": {"x": [0] * d, "y": [0] * d}})
    kfs[-1] = {"t": kfs[-1]["t"], "s": kfs[-1]["s"]}
    if all(k["s"] == kfs[0]["s"] for k in kfs):
        return static(kfs[0]["s"])
    return {"a": 1, "k": kfs}


def over(fn):
    """A property sampled on every frame of the whole timeline."""
    return anim([(f, fn(f)) for f in range(TOTAL + 1)])


def rgb(h, a=1):
    h = h.lstrip("#")
    return [round(int(h[i:i + 2], 16) / 255, 4) for i in (0, 2, 4)] + [a]


def fill(c, o=100):
    return {"ty": "fl", "c": static(rgb(c)), "o": static(o), "r": 1, "nm": "fill"}


def stroke(c, w, o=100):
    return {"ty": "st", "c": static(rgb(c)), "o": static(o), "w": static(w),
            "lc": 2, "lj": 2, "ml": 4, "nm": "stroke"}


def gfill(stops, s, e):
    k = []
    for p, c in stops:
        k += [p] + rgb(c)[:3]
    return {"ty": "gf", "nm": "gradient", "o": static(100), "r": 1, "t": 1,
            "s": static(list(s)), "e": static(list(e)),
            "g": {"p": len(stops), "k": static(k)}}


def tr(p=(0, 0), r=0, s=(100, 100)):
    return {"ty": "tr", "p": static(list(p)), "a": static([0, 0]), "s": static(list(s)),
            "r": static(r), "o": static(100), "sk": static(0), "sa": static(0)}


def group(nm, items, **t):
    return {"ty": "gr", "nm": nm, "it": items + [tr(**t)]}


def ellipse(p, s):
    return {"ty": "el", "p": static(list(p)), "s": static(list(s)), "d": 1}


def rect(p, s, r):
    return {"ty": "rc", "p": static(list(p)), "s": static(list(s)), "r": static(r), "d": 1}


def path(v, i, o, closed):
    return {"ty": "sh", "ks": static({"v": v, "i": i, "o": o, "c": closed})}


def line(a, b, bend=(0, 0)):
    """Open path a→b; `bend` pulls both handles (a gentle curve)."""
    return path(v=[list(a), list(b)], i=[[0, 0], list(bend)], o=[list(bend), [0, 0]], closed=False)


_ind = [100]


def layer(nm, shapes, p, r=None, s=None, o=None, parent=None, ip=0, op=TOTAL, ind=None):
    if ind is None:
        _ind[0] += 1
        ind = _ind[0]
    ks = {"o": o or static(100), "r": r or static(0), "p": p,
          "a": static([0, 0, 0]), "s": s or static([100, 100, 100])}
    lyr = {"ddd": 0, "ind": ind, "ty": 4, "nm": nm, "sr": 1, "ks": ks, "ao": 0,
           "shapes": shapes, "ip": ip, "op": op, "st": 0, "bm": 0}
    if parent:
        lyr["parent"] = parent
    return lyr


def null(nm, ind, p, r=None):
    return {"ddd": 0, "ind": ind, "ty": 3, "nm": nm, "sr": 1, "ao": 0,
            "ks": {"o": static(100), "r": r or static(0), "p": p,
                   "a": static([0, 0, 0]), "s": static([100, 100, 100])},
            "ip": 0, "op": TOTAL, "st": 0, "bm": 0}


K = 0.5523

# ---------- the salute's frame 0 (copied from salute_loading_gen.py) ----------
FACE = (256, 250)
FX, FY = FACE
EYE_Y = FY - 12
SALUTE = dict(x=162, y=182, r=-32)
GROUND = dict(x=386, y=462, r=14, s=54)
SCENE_S, SCENE_Y = 0.74, 506
SCENE = 9
CLOUD = (256, 66)
BLUE = "#3D7BD9"


def helmet_shapes():
    rx, ry = 138, 118
    dome = path(v=[[-rx, 0], [0, -ry], [rx, 0]],
                i=[[0, 0], [-rx * K, 0], [0, -ry * K]],
                o=[[0, -ry * K], [rx * K, 0], [0, 0]], closed=True)
    shine = path(v=[[-92, -58], [-40, -98]], i=[[0, 0], [-30, 12]], o=[[10, -22], [0, 0]], closed=False)
    return [
        group("shine", [shine, stroke("#9FB062", 10, 70)]),
        group("brim", [rect((0, 2), (306, 24), 12), fill("#4A5524")]),
        group("band", [rect((0, -14), (272, 16), 4), fill("#3F4A1E")]),
        group("spots", [ellipse((-58, -66), (38, 24)), ellipse((30, -88), (30, 20)),
                        ellipse((74, -40), (44, 26)), ellipse((-18, -36), (26, 18)),
                        fill("#57652C")]),
        group("dome", [dome, fill("#6F8038"), stroke("#4A5524", 5)]),
    ]


def hand_shapes():
    lines = [path(v=[[14, y], [56, y]], i=[[0, 0], [0, 0]], o=[[0, 0], [0, 0]], closed=False)
             for y in (-10, 4)]
    return [
        group("finger lines", lines + [stroke("#D98F12", 4)]),
        group("thumb", [rect((-6, 22), (52, 20), 10), fill("#FFB83A"), stroke("#D98F12", 4)]),
        group("palm", [rect((0, 0), (128, 50), 25), fill("#FFC341"), stroke("#D98F12", 4)]),
    ]


def smile_shapes():
    m = path(v=[[-40, 0], [40, 0]], i=[[0, 0], [-22, 24]], o=[[22, 24], [0, 0]], closed=False)
    return [group("mouth", [m, stroke("#5A3B1C", 10)])]


def open_eye_shapes():
    return [group("eye", [ellipse((0, 0), (26, 40)), fill("#5A3B1C")]),
            group("glint", [ellipse((4, -9), (8, 10)), fill("#FFFFFF", 80)])]


def face_shapes():
    return [
        group("blush L", [ellipse((-72, 30), (40, 20)), fill("#FF9E7A", 45)]),
        group("blush R", [ellipse((72, 30), (40, 20)), fill("#FF9E7A", 45)]),
        group("face", [ellipse((0, 0), (244, 244)), fill("#FFCC4D"), stroke("#F0AE2C", 5)]),
    ]


def cloud_lobes():
    return [ellipse((-52, 12), (68, 56)), ellipse((-16, -12), (86, 82)),
            ellipse((32, -2), (72, 66)), ellipse((64, 16), (50, 42)),
            rect((6, 24), (156, 40), 20)]


def cloud_shapes(top, bottom, line_c, shadow_c, shine=True):
    items = []
    if shine:
        s = path(v=[[-46, -26], [-12, -46]], i=[[0, 0], [-18, 2]], o=[[6, -12], [0, 0]], closed=False)
        items.append(group("shine", [s, stroke("#FFFFFF", 7, 90)]))
    return items + [
        group("body", cloud_lobes() + [gfill([(0, top), (1, bottom)], (0, -50), (0, 44))]),
        group("outline", cloud_lobes() + [stroke(line_c, 9)]),
        group("drop shadow", [rect((8, 40), (150, 18), 9), fill(shadow_c, 18)]),
    ]


def arrow_shapes():
    shaft = path(v=[[0, -13], [0, 9]], i=[[0, 0]] * 2, o=[[0, 0]] * 2, closed=False)
    head = path(v=[[-10, 0], [0, 11], [10, 0]], i=[[0, 0]] * 3, o=[[0, 0]] * 3, closed=False)
    return [group("arrow", [shaft, head, stroke(BLUE, 6)]),
            group("badge", [ellipse((0, -1), (40, 40)), fill("#E3EFFF")])]


# ---------- the cry's own drawings ----------
def shut_eye_shapes(side):
    arc = path(v=[[-20, 6], [0, -8], [20, 6]],
               i=[[0, 0], [-11, 0], [0, -6]], o=[[0, -6], [11, 0], [0, 0]], closed=False)
    crease = line((side * 22, 10), (side * 30, 16))
    return [group("eye", [arc, crease, stroke("#5A3B1C", 8)])]


def brow_shapes(side):
    # sad brow: the inner end (towards the nose) raised
    return [group("brow", [line((-side * 22, -10), (side * 22, 4), bend=(0, -3)),
                           stroke("#5A3B1C", 8)])]


def wail_shapes():
    rx, ry = 34, 26
    mouth = path(v=[[-rx, 0], [0, -ry], [rx, 0], [0, ry]],
                 i=[[0, ry * K], [-rx * K, 0], [0, -ry * K], [rx * K, 0]],
                 o=[[0, -ry * K], [rx * K, 0], [0, ry * K], [-rx * K, 0]], closed=True)
    tongue = path(v=[[-18, 18], [0, 8], [18, 18], [0, 25]],
                  i=[[-2, 6], [-10, 0], [0, -6], [10, 0]],
                  o=[[0, -6], [10, 0], [-2, 6], [-10, 0]], closed=True)
    return [group("tongue", [tongue, fill("#FF7A7A")]),
            group("mouth", [mouth, fill("#5A3B1C"), stroke("#5A3B1C", 4)])]


def stream_shapes(side):
    # the 😭 streams: a wet band from the eye down the cheek (grows from y=0)
    return [group("highlight", [line((side * 3, 6), (side * 9, 52), bend=(side * 1, 20)),
                                stroke("#FFFFFF", 4, 70)]),
            group("stream", [line((side * 6, 0), (side * 14, 70), bend=(side * 2, 30)),
                             stroke("#5DADE2", 16, 85)])]


def teardrop_shapes():
    v = [[0, -13], [8, 3], [0, 11], [-8, 3]]
    i = [[0, 0], [0, -6], [4.4, 0], [0, 4.4]]
    o = [[0, 0], [0, 4.4], [-4.4, 0], [0, -6]]
    return [group("glint", [ellipse((-2.5, 2), (4, 5)), fill("#FFFFFF", 85)]),
            group("drop", [path(v=v, i=i, o=o, closed=True), fill("#5DADE2"),
                           stroke("#3A8DC8", 2)])]


def ripple_shapes():
    return [group("ripple", [ellipse((0, 0), (56, 14)), stroke("#5DADE2", 4)])]


def puddle_shapes():
    return [group("puddle", [ellipse((0, 0), (96, 18)), fill("#8EC9EE", 75)]),
            group("shine", [ellipse((-18, -2), (30, 5)), fill("#FFFFFF", 60)])]


def cross_shapes():
    return [group("x", [line((-8, -8), (8, 8)), line((8, -8), (-8, 8)), stroke("#E04848", 6)]),
            group("badge", [ellipse((0, 0), (40, 40)), fill("#FDE8E8")])]


# ---------- motion ----------
SOB = 30                   # frames per sob (divides CYCLE)


def local(f):
    """Frames into the cry (0 at INTRO; the loop part repeats the first cycle)."""
    u = f - INTRO
    return u % CYCLE if u >= CYCLE else u


def settle(f):
    """0 → 1 over the cry's first frames (the loop part is always 1)."""
    return 1 if f >= LOOP_START else prog(f - INTRO, 0, 4)


def sob(f):
    """0..1: the heave of a sob — quick in, slow out. 0 during the turn."""
    if f < INTRO:
        return 0
    u = (local(f) % SOB) / SOB
    if u < 0.18:
        return ease_out(u / 0.18)
    return 1 - ease_out((u - 0.18) / 0.82) ** 0.8


def bob(f):
    """Face lift on each sob (negative = up) + a fine tremble."""
    if f < INTRO:
        return 0
    return -7 * sob(f) + 1.2 * settle(f) * math.sin(2 * math.pi * local(f) / 6)


def turn(a, b):
    """0..1 over frames a..b of the turn (eased)."""
    return lambda f: ease_io(prog(f, a, b))


face_p = lambda x, y: over(lambda f: [x, R(y + bob(f)), 0])
face_s = over(lambda f: [R(100 + 2.5 * sob(f)), R(100 - 2 * sob(f)), 100])


def hand_pose(f):
    """The hand drops away from the salute."""
    t = ease_in(prog(f, 0, 11))
    return [R(SALUTE["x"] - 150 * t), R(SALUTE["y"] + 240 * t), 0], [R(SALUTE["r"] - 60 * t)]


hand_p = over(lambda f: hand_pose(f)[0])
hand_r = over(lambda f: hand_pose(f)[1])
hand_o = over(lambda f: [R(100 * (1 - prog(f, 5, 10)))])

# eyes: the open ovals close, the squeezed arcs take over
open_eye_s = over(lambda f: [100, R(max(4, 100 * (1 - turn(1, 7)(f)))), 100])
open_eye_o = over(lambda f: [0 if f >= 7 else 100])
shut_eye_s = over(lambda f: [100, R(100 * ease_out_back(prog(f, 7, 12), 2.2)) if f < 12 else 100, 100])
shut_eye_o = over(lambda f: [100 if f >= 7 else 0])
brow_s = over(lambda f: [R(100 * ease_out(prog(f, 5, 12)))] * 2 + [100])

# mouth: the smile shrinks, the wail opens
smile_s = over(lambda f: [R(100 * (1 - turn(3, 8)(f)))] * 2 + [100])
smile_o = over(lambda f: [0 if f >= 8 else 100])


def wail_scale(f):
    if f < INTRO:
        k = ease_out_back(prog(f, 8, 14), 2.0)
        return [R(100 * k), R(88 * k), 100]
    w = settle(f) * math.sin(2 * math.pi * local(f) / 5)
    return [R(100 + 8 * sob(f) + 3 * w), R(88 + 20 * sob(f) + 4 * w), 100]


wail_s = over(wail_scale)
stream_s = over(lambda f: [100, R((92 + 10 * sob(f)) * ease_out(prog(f, 12, 20))), 100])

# cloud: blue → grey, arrow → ✕; bobs during the cry
cloud_p = over(lambda f: [CLOUD[0], R(CLOUD[1] + (3 * math.sin(2 * math.pi * local(f) / CYCLE)
                                                     if f >= INTRO else 0)), 0])
cloud_r = over(lambda f: [R(2.5 * math.sin(2 * math.pi * local(f) / (CYCLE / 2)) if f >= INTRO else 0)])
blue_o = over(lambda f: [R(100 * (1 - turn(6, 14)(f)))])
grey_o = over(lambda f: [R(100 * turn(6, 14)(f))])
arrow_s = over(lambda f: [R(100 * (1 - turn(6, 11)(f)))] * 2 + [100])
cross_s = over(lambda f: [R(ease_out_back(prog(f, 10, 16), 2.4) * 100 + 8 * sob(f))] * 2 + [100])

# ---------- tears ----------
G = 0.55
EMIT = 9               # frames between two tears of one eye (divides CYCLE)
GROUND_Y = 470
tear_layers, splash_layers = [], []
for side in (-1, 1):
    x0 = FX + side * (46 + 22)
    lands = []
    for k in range(CYCLE // EMIT):
        t0 = k * EMIT + (4 if side > 0 else 0)
        # fast enough to clear the helmet on the right (and the same on the left)
        vx = side * (3.7 + 0.5 * ((k * 7) % 3) / 2)
        vy = -(5.2 + 0.9 * ((k * 5) % 4) / 3)
        y0 = EYE_Y + 6
        life = (-vy + math.sqrt(vy * vy + 2 * G * (GROUND_Y - y0))) / G
        land_x = x0 + vx * life
        lands.append(land_x)
        # emitted in the first cry (n=0) and in the loop (n=1); one emitted in
        # the loop's last frames flies on past its end, and its twin from the
        # first cry is the one in flight when the loop starts again
        for n in (0, 1):
            a = INTRO + t0 + n * CYCLE
            b = a + life
            lo, hi = math.ceil(a), min(TOTAL, math.floor(b))
            if lo < hi:
                frames = sorted(set(list(range(lo, hi + 1, 2)) + [hi]))
                pos = anim([(f, [R(x0 + vx * (f - a)), R(y0 + vy * (f - a) + G * (f - a) ** 2 / 2), 0])
                            for f in frames])
                rot = anim([(f, [R(math.degrees(math.atan2(-vx, vy + G * (f - a))))]) for f in frames])
                grow = anim([(f, [R(60 + 40 * clamp((f - a) / 5))] * 2 + [100]) for f in frames])
                tear_layers.append(layer("tear", teardrop_shapes(), pos, r=rot, s=grow,
                                         parent=SCENE, ip=lo, op=hi + 1))
            rlo, rhi = math.ceil(b), min(TOTAL, math.floor(b + 12))
            if rlo < rhi:
                frames = list(range(rlo, rhi + 1))
                rs = anim([(f, [R(20 + 100 * ease_out((f - b) / 12))] * 2 + [100]) for f in frames])
                ro = anim([(f, [R(90 * (1 - (f - b) / 12))]) for f in frames])
                splash_layers.append(layer("ripple", ripple_shapes(),
                                           static([R(land_x), GROUND_Y, 0]), s=rs, o=ro,
                                           parent=SCENE, ip=rlo, op=rhi + 1))
    # the puddle spreads in with the first tears
    first = INTRO + (4 if side > 0 else 0) + 40
    puddle_s = over(lambda f, a=first: [R(100 * ease_out(prog(f, a - 4, a + 14)))] * 2 + [100])
    splash_layers.append(layer("puddle", puddle_shapes(),
                               static([R(sum(lands) / len(lands)), GROUND_Y + 2, 0]),
                               s=puddle_s, parent=SCENE))

# ---------- layers ----------
character = [
    layer("hand", hand_shapes(), hand_p, r=hand_r, o=hand_o, parent=SCENE),
    layer("brow left", brow_shapes(-1), face_p(FX - 46, EYE_Y - 27), s=brow_s, parent=SCENE),
    layer("brow right", brow_shapes(1), face_p(FX + 46, EYE_Y - 27), s=brow_s, parent=SCENE),
    layer("shut eye left", shut_eye_shapes(-1), face_p(FX - 46, EYE_Y), s=shut_eye_s, o=shut_eye_o, parent=SCENE),
    layer("shut eye right", shut_eye_shapes(1), face_p(FX + 46, EYE_Y), s=shut_eye_s, o=shut_eye_o, parent=SCENE),
    layer("open eye left", open_eye_shapes(), face_p(FX - 46, EYE_Y), s=open_eye_s, o=open_eye_o, parent=SCENE),
    layer("open eye right", open_eye_shapes(), face_p(FX + 46, EYE_Y), s=open_eye_s, o=open_eye_o, parent=SCENE),
    layer("stream left", stream_shapes(-1), face_p(FX - 52, EYE_Y + 10), s=stream_s, parent=SCENE),
    layer("stream right", stream_shapes(1), face_p(FX + 52, EYE_Y + 10), s=stream_s, parent=SCENE),
    layer("wail", wail_shapes(), face_p(FX, FY + 54), s=wail_s, parent=SCENE),
    layer("smile", smile_shapes(), face_p(FX, FY + 52), s=smile_s, o=smile_o, parent=SCENE),
    layer("face", face_shapes(), face_p(FX, FY), s=face_s, parent=SCENE),
]
ground = [
    layer("helmet", helmet_shapes(), static([GROUND["x"], GROUND["y"], 0]),
          r=static(GROUND["r"]), s=static([GROUND["s"], GROUND["s"], 100]), parent=SCENE),
    layer("helmet shadow", [group("shadow", [ellipse((0, 0), (170, 22)), fill("#000000")])],
          static([GROUND["x"], GROUND["y"] + 8, 0]), o=static(30), parent=SCENE),
    layer("face shadow", [group("shadow", [ellipse((0, 0), (190, 20)), fill("#000000")])],
          static([FX, 472, 0]), o=static(14), parent=SCENE),
]

scene = {"ddd": 0, "ind": SCENE, "ty": 3, "nm": "scene", "sr": 1, "ao": 0,
         "ks": {"o": static(100), "r": static(0), "p": static([256, SCENE_Y, 0]),
                "a": static([256, 512, 0]), "s": static([SCENE_S * 100, SCENE_S * 100, 100])},
         "ip": 0, "op": TOTAL, "st": 0, "bm": 0}

CLOUD_IND = 51
clouds = [
    layer("arrow", arrow_shapes(), static([6, 4, 0]), s=arrow_s, parent=CLOUD_IND),
    layer("cross", cross_shapes(), static([6, 6, 0]), s=cross_s, parent=CLOUD_IND),
    layer("blue cloud", cloud_shapes("#FFFFFF", "#C9DFFB", "#8FB6E6", "#5B7FAE"),
          static([0, 0, 0]), o=blue_o, parent=CLOUD_IND),
    layer("grey cloud", cloud_shapes("#F4F6F9", "#C7CDD6", "#A3ACB8", "#5E6672", shine=False),
          static([0, 0, 0]), o=grey_o, parent=CLOUD_IND),
]

# order (first = on top): tears, hand + face, helmet, splashes, clouds
layers = (tear_layers + character + ground + splash_layers + clouds
          + [null("cloud", CLOUD_IND, cloud_p, cloud_r), scene])

doc = {"v": "5.7.4", "fr": FPS, "ip": 0, "op": TOTAL, "w": W, "h": H,
       "nm": "download_failed", "ddd": 0, "assets": [], "layers": layers,
       "markers": [{"tm": 0, "cm": "turn", "dr": INTRO},
                   {"tm": INTRO, "cm": "first cry", "dr": CYCLE},
                   {"tm": LOOP_START, "cm": "loop", "dr": CYCLE}]}

out = sys.argv[1]
with open(out, "w") as fh:
    json.dump(doc, fh, separators=(",", ":"))
print(out, f"(loop: frames {LOOP_START}-{TOTAL})")
