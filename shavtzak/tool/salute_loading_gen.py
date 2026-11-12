"""Generates assets/animations/salute_loading.json, the Lottie loading
animation for the app refresh (when a member has to fetch the new version).

Run from shavtzak/ (Python 3, no packages needed):
    python3 tool/salute_loading_gen.py assets/animations/salute_loading.json
The JSON is generated: change this script, never hand-edit the JSON.

The animation: 512x512, 30 fps, 240 frames (8 s), transparent, seamless loop.
  0-0.6 s   saluting face (own emoji-style vectors, no emoji font), helmet on
            the ground; a cloud at the top streams blue data packets down
  0.6-2.4   hand picks the helmet up and puts it on (squash on landing)
  2.4-3.9   salute snap, wink
  3.9-4.8   wind-up: helmet pulled down beside the chin, tremble
  4.8-5.0   fast throw, the helmet bonks the cloud (frame IMPACT)
  5.0-7.3   cloud bursts + pours 150 particles (packets + gold stars) that land
            on the ground; star eyes, big grin, happy hops the whole time;
            helmet bounces off and lands on the ground
  7.3-7.6   all particles fade together (FADE), then the face goes back to
            normal (JOY_END) and salutes = frame 0
Tunables are the constants near the top (poses, IMPACT, FADE, JOY_END,
SCENE_S, CLOUD, particle counts in the shower section).

Where it plays: the download screen of the in-app refresh, drawn by
web/app_refresh.js with lottie-web 5.12.2 (web/lottie/lottie_light.min.js,
the SVG-only build), not by Flutter. Listed under flutter: assets: in
pubspec.yaml only so the build ships it (served at
assets/assets/animations/salute_loading.json). To look at it: open the app
with ?refreshdemo in the address.
Verified only with lottie-web 5.12.2 so far; uses shape layers, a null
parent layer, polystars, a gradient fill and split x/y positions.

Character motion is computed per frame and baked as linear keyframes (so the
hand carrying the helmet stays in sync); the falling particles use exact
gravity bezier easing so 150 of them stay small (~320 KB total).
"""
import json
import math
import sys

FPS = 30
TOTAL = 240  # 8 s
W = H = 512

# ---------- easing ----------
def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))

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

def lerp(a, b, t):
    return a + (b - a) * t

def prog(f, a, b):
    return clamp((f - a) / (b - a))

# ---------- key poses ----------
FACE = (256, 250)
SALUTE = dict(x=162, y=182, r=-32)
HEAD = dict(x=256, y=162, r=0, s=80)       # helmet worn
GROUND = dict(x=386, y=462, r=14, s=54)     # helmet lying on the ground
GRIP = (8, -112)                            # hand on the dome, helmet coords


def helmet_hand(hx, hy, hr, hs, extra_r=0):
    """World pose of the hand gripping the dome of a helmet at (hx,hy,hr,hs)."""
    a = math.radians(hr)
    ox, oy = GRIP[0] * hs / 100, GRIP[1] * hs / 100
    return dict(x=hx + ox * math.cos(a) - oy * math.sin(a),
                y=hy + ox * math.sin(a) + oy * math.cos(a),
                r=hr + extra_r)


DOME_MID = 55
HIT_X = 262
SCENE_S, SCENE_Y = 0.74, 506   # character scene: scale + where its bottom sits on the canvas
CLOUD_BOTTOM = 110            # canvas y of the cloud's underside
# dome centre at impact (scene coords): its top just touches the cloud
HIT_CY = 512 + (CLOUD_BOTTOM - SCENE_Y) / SCENE_S + (118 - DOME_MID) * 0.8
IMPACT = 149
FADE = (218, 228)        # every particle has landed by 218, then they all fade together
JOY_END = 226            # stars + grin until the ground is clear
WIND = dict(x=372, y=372, r=-32, s=80)   # helmet held low beside the chin before the throw


def hop(f):
    """Happy hops after the bonk (scene units, negative = up)."""
    if 153 <= f < 223:
        u = (f - 153) / 10
        return -15 * abs(math.sin(math.pi * u)) * (1 - 0.4 * (u >= 2))
    return 0


def joy(f):
    """0..1: how much the star eyes + big smile are showing."""
    if f < 151:
        return 0
    if f < 155:
        return ease_out_back(prog(f, 151, 155), 2.2)
    if f < JOY_END:
        return 1
    return 1 - ease_io(prog(f, JOY_END, JOY_END + 7))  # height of the dome's centre above the brim, helmet coords


def centre_of(h):
    a = math.radians(h["r"])
    d = DOME_MID * h["s"] / 100
    return (h["x"] + d * math.sin(a), h["y"] - d * math.cos(a))


def brim_from_centre(cx, cy, r, s):
    a = math.radians(r)
    d = DOME_MID * s / 100
    return dict(x=cx - d * math.sin(a), y=cy + d * math.cos(a), r=r, s=s)


def mix(p, q, t):
    return {k: lerp(p[k], q[k], t) for k in p}


def pose(f):
    """Returns (helmet, hand, extras) for frame f."""
    hel = dict(GROUND)
    sq = (100, 100)  # helmet squash
    hand = dict(SALUTE)
    eye_r = 100      # right-eye vertical scale (wink)
    mouth = 100

    # 0-18 salute, helmet on the ground
    if f < 18:
        pass
    # 18-40 hand reaches down to the helmet
    elif f < 40:
        hand = mix(SALUTE, helmet_hand(GROUND["x"], GROUND["y"], GROUND["r"], GROUND["s"]),
                   ease_io(prog(f, 18, 40)))
    # 40-44 grip
    elif f < 44:
        hand = helmet_hand(GROUND["x"], GROUND["y"], GROUND["r"], GROUND["s"])
        hel = dict(GROUND, y=GROUND["y"] - 3 * math.sin(math.pi * prog(f, 40, 44)))
    # 44-72 lift the helmet in an arc onto the head
    elif f < 72:
        t = ease_io(prog(f, 44, 72))
        hel = dict(x=lerp(GROUND["x"], HEAD["x"], t),
                   y=lerp(GROUND["y"], HEAD["y"], t) - 150 * 4 * t * (1 - t),
                   r=lerp(GROUND["r"], HEAD["r"], t) - 18 * math.sin(math.pi * t),
                   s=lerp(GROUND["s"], HEAD["s"], t))
        hand = helmet_hand(hel["x"], hel["y"], hel["r"], hel["s"])
    # 72-96 helmet lands (squash), hand returns to salute
    elif f < 96:
        hel = dict(HEAD)
        land = prog(f, 72, 82)
        k = math.sin(math.pi * land) * (1 - land * 0.3)
        sq = (100 + 8 * k, 100 - 10 * k)
        on_top = helmet_hand(HEAD["x"], HEAD["y"], 0, HEAD["s"])
        on_top["y"] += 10 * k
        if f < 80:
            hand = on_top
        else:
            hand = mix(on_top, SALUTE, ease_io(prog(f, 80, 96)))
    # 96-122 salute snap + wink
    elif f < 122:
        hel = dict(HEAD)
        snap = math.sin(math.pi * prog(f, 96, 102))
        hand = dict(SALUTE, r=SALUTE["r"] - 7 * snap, x=SALUTE["x"] - 3 * snap)
        w = prog(f, 104, 108) if f < 110 else 1 - prog(f, 114, 118)
        eye_r = lerp(100, 8, ease_io(w))
        mouth = lerp(100, 118, ease_io(w))
    # 118-128 hand goes up to the helmet
    elif f < 128:
        hel = dict(HEAD)
        hand = mix(SALUTE, helmet_hand(HEAD["x"], HEAD["y"], 0, HEAD["s"]), ease_io(prog(f, 118, 128)))
    # 128-141 wind-up: lift it off and pull it down beside the chin, tilted back
    elif f < 144:
        t = ease_io(prog(f, 128, 141))
        hel = dict(x=lerp(HEAD["x"], WIND["x"], t),
                   y=lerp(HEAD["y"], WIND["y"], t) - 40 * math.sin(math.pi * t),
                   r=lerp(0, WIND["r"], t), s=HEAD["s"])
        if f >= 139:  # charging: a little tremble
            hel["x"] += 2.5 * math.sin(f * 2.6)
            hel["y"] += 1.5 * math.cos(f * 3.1)
        hand = helmet_hand(hel["x"], hel["y"], hel["r"], hel["s"])
    # 144-149 THROW (fast, stretched), 149-151 bonk, 151-168 fall spinning
    else:
        c0 = centre_of(WIND)
        hit = (HIT_X, HIT_CY)
        if f < 149:
            t = ease_out(prog(f, 144, 149), ) ** 0.8
            hel = brim_from_centre(lerp(c0[0], hit[0], t), lerp(c0[1], hit[1], t),
                                   lerp(WIND["r"], 6, t), HEAD["s"])
            sq = (90, 116)
        elif f < 151:
            hel = brim_from_centre(hit[0], hit[1] + 2 * (f - 149), 6, HEAD["s"])
            sq = (116, 82)
        elif f < 168:
            t = prog(f, 151, 168)
            c1 = centre_of(GROUND)
            cx = lerp(hit[0], c1[0], ease_out(t)) + 46 * math.sin(math.pi * t)
            cy = lerp(hit[1] + 4, c1[1], ease_in(t))
            r = lerp(6, GROUND["r"] + 360, ease_in(t) * 0.4 + t * 0.6)
            hel = brim_from_centre(cx, cy, r, lerp(HEAD["s"], GROUND["s"], t))
        else:
            bb = prog(f, 168, 177)
            hel = dict(GROUND, y=GROUND["y"] - 20 * math.sin(math.pi * bb) * (1 - bb * 0.2),
                       r=GROUND["r"] + 360 + 8 * math.sin(math.pi * bb))
            k = math.sin(math.pi * prog(f, 168, 173))
            sq = (100 + 6 * k, 100 - 8 * k)
        # hand: whips up with the throw (follow-through), then back to salute
        release = helmet_hand(WIND["x"], WIND["y"], WIND["r"], WIND["s"])
        follow = dict(x=HEAD["x"] + 40, y=HEAD["y"] - 80, r=-70)
        if f < 148:
            hand = mix(release, follow, ease_out(prog(f, 144, 148)))
        elif f < 151:
            hand = follow
        elif f < 163:
            hand = mix(follow, SALUTE, ease_io(prog(f, 151, 163)))
        else:
            snap = math.sin(math.pi * prog(f, 163, 169))
            hand = dict(SALUTE, r=SALUTE["r"] - 7 * snap, x=SALUTE["x"] - 3 * snap)
        hand = dict(hand, y=hand["y"] + hop(f))

    return hel, sq, hand, eye_r, mouth


# ---------- lottie helpers ----------
def static(v):
    return {"a": 0, "k": v}

def anim(values):
    """values: list of (frame, list) — linear keyframes, holds deduplicated."""
    keep = [values[0]]
    for idx in range(1, len(values) - 1):
        a, b, c = keep[-1], values[idx], values[idx + 1]
        span = c[0] - a[0]
        u = (b[0] - a[0]) / span
        # a keyframe is needed if dropping it moves the curve, or at a jump
        if any(abs(av + (cv - av) * u - bv) > 0.25 for av, bv, cv in zip(a[1], b[1], c[1])):
            keep.append(b)
    keep.append(values[-1])
    values = keep
    kfs = []
    n = len(values)
    for idx, (f, v) in enumerate(values):
        if 0 < idx < n - 1 and values[idx - 1][1] == v == values[idx + 1][1]:
            continue
        d = len(v)
        kfs.append({"t": f, "s": v,
                    "i": {"x": [1] * d, "y": [1] * d},
                    "o": {"x": [0] * d, "y": [0] * d}})
    kfs[-1] = {"t": kfs[-1]["t"], "s": kfs[-1]["s"]}
    if all(k["s"] == kfs[0]["s"] for k in kfs):
        return static(kfs[0]["s"])
    return {"a": 1, "k": kfs}

def rgb(h, a=1):
    h = h.lstrip("#")
    return [round(int(h[i:i + 2], 16) / 255, 4) for i in (0, 2, 4)] + [a]

def fill(c, o=100):
    return {"ty": "fl", "c": static(rgb(c)), "o": static(o), "r": 1, "nm": "fill"}

def stroke(c, w, o=100):
    return {"ty": "st", "c": static(rgb(c)), "o": static(o), "w": static(w),
            "lc": 2, "lj": 2, "ml": 4, "nm": "stroke"}

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

def layer(ind, nm, shapes, p, r=None, s=None, o=None, parent=None):
    ks = {"o": o or static(100), "r": r or static(0), "p": p,
          "a": static([0, 0, 0]), "s": s or static([100, 100, 100])}
    lyr = {"ddd": 0, "ind": ind, "ty": 4, "nm": nm, "sr": 1, "ks": ks, "ao": 0,
           "shapes": shapes, "ip": 0, "op": TOTAL, "st": 0, "bm": 0}
    if parent:
        lyr["parent"] = parent
    return lyr

K = 0.5523

# ---------- drawings (local coordinates) ----------
def helmet_shapes():
    rx, ry = 138, 118
    dome = path(
        v=[[-rx, 0], [0, -ry], [rx, 0]],
        i=[[0, 0], [-rx * K, 0], [0, -ry * K]],
        o=[[0, -ry * K], [rx * K, 0], [0, 0]],
        closed=True)
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
    # fingers point to +x, palm centred at (0,0)
    lines = [path(v=[[14, y], [56, y]], i=[[0, 0], [0, 0]], o=[[0, 0], [0, 0]], closed=False)
             for y in (-10, 4)]
    return [
        group("finger lines", lines + [stroke("#D98F12", 4)]),
        group("thumb", [rect((-6, 22), (52, 20), 10), fill("#FFB83A"), stroke("#D98F12", 4)]),
        group("palm", [rect((0, 0), (128, 50), 25), fill("#FFC341"), stroke("#D98F12", 4)]),
    ]

def mouth_shapes():
    m = path(v=[[-40, 0], [40, 0]], i=[[0, 0], [-22, 24]], o=[[22, 24], [0, 0]], closed=False)
    return [group("mouth", [m, stroke("#5A3B1C", 10)])]

def eye_shapes():
    return [group("eye", [ellipse((0, 0), (26, 40)), fill("#5A3B1C")]),
            group("glint", [ellipse((4, -9), (8, 10)), fill("#FFFFFF", 80)])]

def face_shapes():
    return [
        group("blush L", [ellipse((-72, 30), (40, 20)), fill("#FF9E7A", 45)]),
        group("blush R", [ellipse((72, 30), (40, 20)), fill("#FF9E7A", 45)]),
        group("face", [ellipse((0, 0), (244, 244)), fill("#FFCC4D"), stroke("#F0AE2C", 5)]),
    ]

# ---------- build ----------
frames = [pose(f) for f in range(TOTAL + 1)]
R = lambda x: round(x, 2)

hp = anim([(f, [R(h["x"]), R(h["y"]), 0]) for f, (h, *_ ) in enumerate(frames)])
hr = anim([(f, [R(h["r"])]) for f, (h, *_ ) in enumerate(frames)])
hs = anim([(f, [R(h["s"] * sq[0] / 100), R(h["s"] * sq[1] / 100), 100])
           for f, (h, sq, *_ ) in enumerate(frames)])

np_ = anim([(f, [R(n["x"]), R(n["y"]), 0]) for f, (_, _, n, *_ ) in enumerate(frames)])
nr = anim([(f, [R(n["r"])]) for f, (_, _, n, *_ ) in enumerate(frames)])

def eye_hide(f):
    return clamp(1 - joy(f) * 1.6) if f >= 151 else 1
eye_s = anim([(f, [R(100 * eye_hide(f)), R(min(e, 100) * eye_hide(f)), 100])
              for f, (_, _, _, e, _) in enumerate(frames)])
eyel_s = anim([(f, [R(100 * eye_hide(f)), R(100 * eye_hide(f)), 100]) for f in range(TOTAL + 1)])
mouth_s = anim([(f, [R(m * eye_hide(f)), R(m * eye_hide(f)), 100]) for f, (*_, m) in enumerate(frames)])

def shadow_op(h):
    d = math.hypot(h["x"] - GROUND["x"], h["y"] - GROUND["y"])
    return R(30 * clamp(1 - d / 140))
shadow_o = anim([(f, [shadow_op(h)]) for f, (h, *_ ) in enumerate(frames)])

FX, FY = FACE


def look_up(f):
    """Eyes follow the helmet up to the cloud and back down."""
    if 141 <= f < 151:
        return -7 * ease_io(prog(f, 141, 147))
    return 0


def hop_pos(x, y):
    return anim([(f, [x, R(y + hop(f)), 0]) for f in range(TOTAL + 1)])


def star(points=5, outer=27, inner=11):
    return {"ty": "sr", "sy": 1, "d": 1, "pt": static(points), "p": static([0, 0]),
            "r": static(0), "ir": static(inner), "is": static(0), "or": static(outer), "os": static(0)}


def star_eye_shapes():
    return [group("glint", [ellipse((-5, -7), (6, 6)), fill("#FFFFFF", 90)]),
            group("star", [star(), fill("#FFB703"), stroke("#E07B00", 3.5)])]


def grin_shapes():
    grin = path(v=[[-46, -6], [46, -6], [0, 40]],
                i=[[0, 0], [0, 0], [30, 0]], o=[[0, 0], [0, 26], [-30, 0]], closed=True)
    tongue = path(v=[[-20, 26], [20, 26], [0, 38]],
                  i=[[0, 0], [0, -14], [12, 0]], o=[[0, -14], [0, 8], [-12, 0]], closed=True)
    return [group("tongue", [tongue, fill("#FF7A7A")]),
            group("grin", [grin, fill("#5A3B1C"), stroke("#5A3B1C", 4)])]


def blush_shapes():
    return [group("blush", [ellipse((-74, 32), (50, 26)), ellipse((74, 32), (50, 26)), fill("#FF7F66")])]


joy_s = anim([(f, [R(100 * joy(f))] * 2 + [100]) for f in range(TOTAL + 1)])
star_spin = anim([(f, [R(18 * math.sin(2 * math.pi * (f - 151) / 14)) if 151 <= f < JOY_END + 7 else 0])
                  for f in range(TOTAL + 1)])
blush_o = anim([(f, [R(55 * clamp(joy(f)))]) for f in range(TOTAL + 1)])


def eye_pos(x):
    return anim([(f, [x, R(FY - 12 + look_up(f) + hop(f)), 0]) for f in range(TOTAL + 1)])

layers = [
    layer(1, "hand", hand_shapes(), np_, r=nr),
    layer(2, "helmet", helmet_shapes(), hp, r=hr, s=hs),
    layer(12, "star eye right", star_eye_shapes(), eye_pos(FX + 46), s=joy_s, r=star_spin),
    layer(13, "star eye left", star_eye_shapes(), eye_pos(FX - 46), s=joy_s, r=star_spin),
    layer(14, "big grin", grin_shapes(), hop_pos(FX, FY + 44), s=joy_s),
    layer(3, "mouth", mouth_shapes(), hop_pos(FX, FY + 52), s=mouth_s),
    layer(4, "eye right (wink)", eye_shapes(), eye_pos(FX + 46), s=eye_s),
    layer(5, "eye left", eye_shapes(), eye_pos(FX - 46), s=eyel_s),
    layer(15, "happy blush", blush_shapes(), hop_pos(FX, FY), o=blush_o),
    layer(6, "face", face_shapes(), hop_pos(FX, FY)),
    layer(7, "ground shadow", [group("shadow", [ellipse((0, 0), (170, 22)), fill("#000000")])],
          static([GROUND["x"], GROUND["y"] + 8, 0]), o=shadow_o),
]
# face shadow is constant
layers.append(layer(8, "face shadow",
                    [group("shadow", [ellipse((0, 0), (190, 20)), fill("#000000")])],
                    static([FX, 472, 0]), o=static(14)))

SCENE = 9
for lyr in layers:
    lyr["parent"] = SCENE
scene = {"ddd": 0, "ind": SCENE, "ty": 3, "nm": "scene", "sr": 1, "ao": 0,
         "ks": {"o": static(100), "r": static(0), "p": static([256, SCENE_Y, 0]),
                "a": static([256, 512, 0]), "s": static([SCENE_S * 100, SCENE_S * 100, 100])},
         "ip": 0, "op": TOTAL, "st": 0, "bm": 0}

CLOUD = (256, 66)
BLUE = "#3D7BD9"
CANVAS_HIT = (256 + SCENE_S * (HIT_X - 256), CLOUD_BOTTOM - 10)   # where the helmet bonks the cloud


def cloud_lobes():
    return [ellipse((-52, 12), (68, 56)), ellipse((-16, -12), (86, 82)),
            ellipse((32, -2), (72, 66)), ellipse((64, 16), (50, 42)),
            rect((6, 24), (156, 40), 20)]


def gfill(stops, s, e):
    """Linear gradient fill; stops = [(pos, '#hex'), ...]."""
    k = []
    for p, c in stops:
        k += [p] + rgb(c)[:3]
    return {"ty": "gf", "nm": "gradient", "o": static(100), "r": 1, "t": 1,
            "s": static(list(s)), "e": static(list(e)),
            "g": {"p": len(stops), "k": static(k)}}


def cloud_shapes():
    shine = path(v=[[-46, -26], [-12, -46]], i=[[0, 0], [-18, 2]], o=[[6, -12], [0, 0]], closed=False)
    return [
        group("shine", [shine, stroke("#FFFFFF", 7, 90)]),
        group("body", cloud_lobes() + [gfill([(0, "#FFFFFF"), (1, "#C9DFFB")], (0, -50), (0, 44))]),
        # same lobes, stroked and drawn underneath: one clean outline, no inner seams
        group("outline", cloud_lobes() + [stroke("#8FB6E6", 9)]),
        group("drop shadow", [rect((8, 40), (150, 18), 9), fill("#5B7FAE", 18)]),
    ]


def arrow_shapes():
    shaft = path(v=[[0, -13], [0, 9]], i=[[0, 0]] * 2, o=[[0, 0]] * 2, closed=False)
    head = path(v=[[-10, 0], [0, 11], [10, 0]], i=[[0, 0]] * 3, o=[[0, 0]] * 3, closed=False)
    return [group("arrow", [shaft, head, stroke(BLUE, 6)]),
            group("badge", [ellipse((0, -1), (40, 40)), fill("#E3EFFF")])]


def cloud_react(f):
    """(dx, dy, sx, sy, rot) of the cloud after the bonk."""
    if f < IMPACT:
        return 0, 0, 100, 100, 0
    t = (f - IMPACT) / 22
    if t >= 1:
        return 0, 0, 100, 100, 0
    decay = (1 - t) ** 2
    wob = math.sin(t * math.pi * 5)
    return (0, -10 * decay * max(0.0, math.cos(t * math.pi * 2.5)),
            100 + 12 * decay * wob, 100 - 14 * decay * wob, 7 * decay * math.sin(t * math.pi * 6))


reacts = [cloud_react(f) for f in range(TOTAL + 1)]
cloud_p = anim([(f, [CLOUD[0] + r[0], R(CLOUD[1] + r[1]), 0]) for f, r in enumerate(reacts)])
cloud_s = anim([(f, [R(r[2]), R(r[3]), 100]) for f, r in enumerate(reacts)])
cloud_r = anim([(f, [R(r[4])]) for f, r in enumerate(reacts)])

PERIOD = 30  # divides TOTAL, so the stream loops seamlessly
arrow_p = anim([(f, [6, R(4 + 3 * math.sin(2 * math.pi * f / PERIOD)), 0]) for f in range(TOTAL + 1)])

CLOUD_IND = 11
fx_layers = []

# steady stream of data packets (exact gravity easing: a few keyframes per drop)
def stream_layer(k, dx, delay):
    def lin(t, v):
        return {"t": R(t), "s": [R(v)], "o": {"x": [0], "y": [0]}, "i": {"x": [1], "y": [1]}}
    top, drop = CLOUD[1] + 40, 80
    ys, ops, scs = [], [], []
    op_pts = [0, 0.2, 0.5, 0.8, 1]
    op_val = lambda u: 100 * math.sin(math.pi * u) ** 0.7
    n = -1
    while True:
        c = delay + n * PERIOD
        if c >= TOTAL:
            break
        u0 = max(0.0, (0 - c) / PERIOD)          # first drop may start mid-way at frame 0
        t0 = c + u0 * PERIOD
        end = c + PERIOD
        if end > 0:
            a_ = 2 * u0 / (1 + u0)
            ys.append({"t": R(t0), "s": [R(top + drop * u0 * u0)],
                       "o": {"x": [0.3333], "y": [round(a_ / 3, 4)]},
                       "i": {"x": [0.6667], "y": [round((1 + a_) / 3, 4)]}})
            ys.append({"t": R(end - 0.01), "s": [R(top + drop)], "h": 1})
            pts = [u0] + [p for p in op_pts if p > u0]
            for p in pts[:-1]:
                ops.append(lin(c + p * PERIOD, op_val(p)))
            ops.append({"t": R(end - 0.01), "s": [0], "h": 1})
            scs.append({"t": R(t0), "s": [R(100 - 35 * u0)] * 2 + [100],
                        "o": {"x": [0] * 3, "y": [0] * 3}, "i": {"x": [1] * 3, "y": [1] * 3}})
            scs.append({"t": R(end - 0.01), "s": [65, 65, 100], "h": 1})
        n += 1
    ys.append({"t": TOTAL, "s": [R(top)]})
    ops.append({"t": TOTAL, "s": [0]})
    scs.append({"t": TOTAL, "s": [100, 100, 100]})
    x = CLOUD[0] + 6 + dx
    return layer(20 + k, f"data packet {k + 1}",
                 [group("packet", [rect((0, 0), (13, 13), 4), fill(BLUE)])],
                 {"s": True, "x": static(x), "y": {"a": 1, "k": ys}},
                 s={"a": 1, "k": scs}, o={"a": 1, "k": ops})


for k, (dx, delay) in enumerate([(-14, 0), (10, 10), (-2, 20)]):
    fx_layers.append(stream_layer(k, dx, delay))

# the bonk knocks a burst of packets out of the cloud
import random
rng = random.Random(7)
G = 0.6   # gravity, px / frame^2


def seg(t, v, a=None, hold=False):
    """Keyframe; `a` = normalised start slope of a gravity (quadratic) segment."""
    k = {"t": R(t), "s": [R(v)]}
    if hold:
        k["h"] = 1
    elif a is not None:
        k["o"] = {"x": [0.3333], "y": [round(a / 3, 4)]}
        k["i"] = {"x": [0.6667], "y": [round((1 + a) / 3, 4)]}
    return k


def lin(t, v):
    return {"t": R(t), "s": [R(v)], "o": {"x": [0], "y": [0]}, "i": {"x": [1], "y": [1]}}


def particle(ind, t0, x0, y0, vx, vy, land_y, kind, size, col):
    # vertical: up to the apex (if thrown up), then fall to land_y
    ys = [seg(0, y0, hold=True)]
    if vy < 0:
        ta = -vy / G
        apex = y0 - vy * vy / (2 * G)
        ys.append(seg(t0, y0, a=2))
        t1 = t0 + ta
        tf = math.sqrt(2 * (land_y - apex) / G)
        ys.append(seg(t1, apex, a=0))
        t_land = t1 + tf
    else:
        tf = (-vy + math.sqrt(vy * vy + 2 * G * (land_y - y0))) / G
        ys.append(seg(t0, y0, a=(vy * tf) / (land_y - y0)))
        t_land = t0 + tf
    ys.append({"t": R(t_land), "s": [R(land_y)]})
    x_land = x0 + vx * (t_land - t0)
    if x_land < 24:          # would fly off the canvas: land near the edge instead
        x_land = rng.uniform(24, 70)
    elif x_land > W - 24:
        x_land = rng.uniform(W - 70, W - 24)
    xs = [seg(0, x0, hold=True), lin(t0, x0), {"t": R(t_land), "s": [R(x_land)]}]
    spin = rng.uniform(300, 700) * (1 if vx >= 0 else -1) * (t_land - t0) / FPS
    rot = {"a": 1, "k": [seg(0, 0, hold=True), lin(t0, 0), {"t": R(t_land), "s": [R(spin)]}]}
    op = {"a": 1, "k": [seg(0, 0, hold=True), seg(t0, 100, hold=True), lin(FADE[0], 100),
                        {"t": FADE[1], "s": [0]}]}
    assert t_land < FADE[0], t_land
    if kind == "star":
        shape = [group("star", [star(5, 9 * size, 4 * size), fill("#FFC233"), stroke("#E08A00", 2)])]
    else:
        shape = [group("packet", [rect((0, 0), (12 * size, 12 * size), 3), fill(col)])]
    lyr = layer(ind, f"{kind} {ind}", shape, {"s": True, "x": {"a": 1, "k": xs}, "y": {"a": 1, "k": ys}},
                r=rot, o=op)
    return lyr


def pick_kind(k):
    return ("star" if k % 4 == 1 else "packet", rng.uniform(0.7, 1.3),
            rng.choice([BLUE, "#6FA3EF", "#2F5FB3", "#8FC1FF"]))


ind = 100
# 1) the bonk: a wide fountain out of the cloud
for k in range(40):
    ang = math.radians(lerp(-175, -5, k / 39) + rng.uniform(-5, 5))
    sp = rng.uniform(4, 11)
    vx, vy = sp * math.cos(ang), sp * math.sin(ang) * 0.85
    fx_layers.append(particle(ind, IMPACT + rng.uniform(0, 2), CANVAS_HIT[0] + rng.uniform(-20, 20),
                              CANVAS_HIT[1] + rng.uniform(-6, 6), vx, vy,
                              rng.uniform(456, 496), *pick_kind(k)))
    ind += 1
# 2) then the cloud pours: a heavy shower from its whole underside
for k in range(110):
    t0 = 151 + 30 * (k / 109) ** 1.4 + rng.uniform(0, 2)
    x0 = rng.uniform(176, 342)
    fx_layers.append(particle(ind, t0, x0, rng.uniform(100, 110), rng.uniform(-3.2, 3.2),
                              rng.uniform(0.2, 2.2), rng.uniform(456, 496), *pick_kind(k + 2)))
    ind += 1

# impact sparks
spark_items = []
for ang in (-165, -135, -105, -75, -45, -15, 195, 160, 20):
    a_ = math.radians(ang)
    spark_items.append(path(v=[[20 * math.cos(a_), 20 * math.sin(a_)], [42 * math.cos(a_), 42 * math.sin(a_)]],
                            i=[[0, 0]] * 2, o=[[0, 0]] * 2, closed=False))
spark_s = anim([(f, [R(lerp(60, 140, ease_out(prog(f, IMPACT, IMPACT + 8))))] * 2 + [100])
               for f in range(TOTAL + 1)])
spark_o = anim([(f, [100 if IMPACT <= f < IMPACT + 3 else
                     (R(100 * (1 - prog(f, IMPACT + 3, IMPACT + 9))) if IMPACT <= f < IMPACT + 9 else 0)])
                for f in range(TOTAL + 1)])
fx_layers.insert(0, layer(40, "impact sparks", [group("sparks", spark_items + [stroke("#FFB020", 5)])],
                          static([CANVAS_HIT[0], CANVAS_HIT[1] + 6, 0]), s=spark_s, o=spark_o))

arrow = layer(10, "download arrow", arrow_shapes(), arrow_p, parent=CLOUD_IND)
cloud = layer(CLOUD_IND, "cloud", cloud_shapes(), cloud_p, r=cloud_r, s=cloud_s)

# order (first = on top): sparks, burst, character, cloud, stream
layers = ([fx_layers[0]] + fx_layers[4:] + layers + [arrow, cloud] + fx_layers[1:4] + [scene])

doc = {"v": "5.7.4", "fr": FPS, "ip": 0, "op": TOTAL, "w": W, "h": H,
       "nm": "salute_loading", "ddd": 0, "assets": [], "layers": layers}

out = sys.argv[1]
with open(out, "w") as fh:
    json.dump(doc, fh, separators=(",", ":"))
print(out)
