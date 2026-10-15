"""Writes the golden fixture JSON files. Expected values are computed here with an
independent implementation of the easing maths so Elm and the player are both
checked against a third source. Run: python3 tests/golden/make-fixtures.py
"""
import json, math, os

def node(id, kind, geometry, transform=None, opacity=1.0, fill=None, stroke=None, motion=None):
    t = transform or {}
    return {
        "id": id, "name": id, "kind": kind, "parentId": None, "childIds": [], "hidden": False, "locked": False,
        "opacity": opacity,
        "transform": {"translation": t.get("translation", {"x": 0, "y": 0}), "scale": t.get("scale", {"x": 1, "y": 1}),
                      "rotation": t.get("rotation", 0), "skew": {"x": 0, "y": 0}, "pivot": t.get("pivot", {"x": 0, "y": 0})},
        "geometry": geometry,
        "fill": fill or {"type": "solid", "color": {"r": 0.2, "g": 0.5, "b": 0.95, "a": 1}},
        "stroke": stroke or {"paint": {"type": "none"}, "width": 2, "cap": "butt", "join": "miter", "miterLimit": 4, "dashArray": [], "dashOffset": 0},
        "effects": [], "motion": motion, "metadata": {"importedElementId": None}}

def scene(name, dur=60, mode="repeat"):
    return {"id": "scene", "name": name, "width": 400, "height": 400, "fps": {"numerator": 30, "denominator": 1}, "durationFrames": dur, "playbackMode": mode}

def track(id, nodeId, prop, keys):
    return {"id": id, "target": {"nodeId": nodeId, "property": prop}, "enabled": True, "locked": False, "keyframes": keys}

def k(id, frame, value, easing):
    return {"id": id, "frame": frame, "value": value, "easing": easing}

LIN = {"type": "linear"}; HOLD = {"type": "hold"}; EIO = {"type": "preset", "name": "ease-in-out"}; EIN = {"type": "preset", "name": "ease-in"}
def bez(x1, y1, x2, y2): return {"type": "cubicBezier", "x1": x1, "y1": y1, "x2": x2, "y2": y2}
def spring(m, k_, c, v=0): return {"type": "spring", "mass": m, "stiffness": k_, "damping": c, "velocity": v}

def cubic_at(x1, y1, x2, y2, x):
    if x <= 0: return 0.0
    if x >= 1: return 1.0
    lo, hi = 0.0, 1.0
    for _ in range(80):
        mid = (lo + hi) / 2
        bx = 3 * (1 - mid) ** 2 * mid * x1 + 3 * (1 - mid) * mid ** 2 * x2 + mid ** 3
        if bx < x: lo = mid
        else: hi = mid
    t = (lo + hi) / 2
    return 3 * (1 - t) ** 2 * t * y1 + 3 * (1 - t) * t ** 2 * y2 + t ** 3

def spring_at(m, k_, c, v0, u):
    if u <= 0: return 0.0
    if u >= 1: return 1.0
    w0 = math.sqrt(k_ / m); zeta = c / (2 * math.sqrt(k_ * m)); x0 = -1.0; t = u
    if zeta < 1:
        wd = w0 * math.sqrt(1 - zeta * zeta); a = x0; b = (zeta * w0 * x0 + v0) / wd
        disp = math.exp(-zeta * w0 * t) * (a * math.cos(wd * t) + b * math.sin(wd * t))
    elif zeta == 1:
        disp = (x0 + (v0 + w0 * x0) * t) * math.exp(-w0 * t)
    else:
        s1 = -w0 * (zeta - math.sqrt(zeta * zeta - 1)); s2 = -w0 * (zeta + math.sqrt(zeta * zeta - 1))
        c2 = (v0 - s1 * x0) / (s2 - s1); c1 = x0 - c2
        disp = c1 * math.exp(s1 * t) + c2 * math.exp(s2 * t)
    return 1 + disp

goldens = []

anim = {"version": 1, "scene": scene("basic"), "nodes": [node("box", "rect", {"size": {"x": 100, "y": 50}, "cornerRadius": 0}, {"translation": {"x": 10, "y": 20}})],
        "tracks": [track("t1", "box", "transform.position", [k("a", 0, {"type": "point", "value": {"x": 10, "y": 20}}, LIN), k("b", 30, {"type": "point", "value": {"x": 110, "y": 20}}, EIO), k("c", 60, {"type": "point", "value": {"x": 110, "y": 220}}, LIN)]),
                   track("t2", "box", "compositing.opacity", [k("d", 10, {"type": "scalar", "value": 1}, LIN), k("e", 50, {"type": "scalar", "value": 0.2}, LIN)])],
        "motionPaths": []}
exp = []
for f in [0, 15, 30, 45, 60, 75]:
    if f <= 30: x = 10 + 100 * (f / 30); y = 20
    else:
        u = (f - 30) / 30 if f <= 60 else 1.0
        x = 110; y = 20 + 200 * cubic_at(0.42, 0, 0.58, 1, u)
    exp.append({"frame": f, "nodeId": "box", "property": "position", "value": [x, y]})
for f in [0, 10, 30, 50, 60]:
    o = 1 if f <= 10 else (0.2 if f >= 50 else 1 + (0.2 - 1) * ((f - 10) / 40))
    exp.append({"frame": f, "nodeId": "box", "property": "opacity", "value": o})
goldens.append({"name": "basic-transform-opacity", "animation": anim, "expectations": exp})

anim = {"version": 1, "scene": scene("easing"), "nodes": [node("n", "ellipse", {"radii": {"x": 20, "y": 20}}, {"translation": {"x": 100, "y": 100}, "pivot": {"x": 10, "y": 0}})],
        "tracks": [track("r", "n", "transform.rotation", [k("a", 0, {"type": "angle", "value": 0}, HOLD), k("b", 20, {"type": "angle", "value": 90}, EIN), k("c", 40, {"type": "angle", "value": 180}, bez(0.3, -0.4, 0.6, 1.5)), k("d", 60, {"type": "angle", "value": 360}, LIN)])],
        "motionPaths": []}
exp = []
for f in [0, 10, 19, 20, 30, 40, 50, 60]:
    if f < 20: r = 0.0
    elif f < 40: r = 90 + 90 * cubic_at(0.42, 0, 1, 1, (f - 20) / 20)
    elif f < 60: r = 180 + 180 * cubic_at(0.3, -0.4, 0.6, 1.5, (f - 40) / 20)
    else: r = 360.0
    exp.append({"frame": f, "nodeId": "n", "property": "rotation", "value": r, "tolerance": 1e-5})
    rad = math.radians(r)
    px = 10 - (10 * math.cos(rad)); py = -(10 * math.sin(rad))
    exp.append({"frame": f, "nodeId": "n", "property": "position", "value": [100 + px, 100 + py], "tolerance": 1e-4})
goldens.append({"name": "easing-hold-bezier-rotation-pivot", "animation": anim, "expectations": exp})

anim = {"version": 1, "scene": scene("spring"), "nodes": [node("s", "rect", {"size": {"x": 10, "y": 10}, "cornerRadius": 0}, fill={"type": "solid", "color": {"r": 1, "g": 0, "b": 0, "a": 1}})],
        "tracks": [track("sc", "s", "transform.scale", [k("a", 0, {"type": "point", "value": {"x": 1, "y": 1}}, spring(1, 200, 3)), k("b", 50, {"type": "point", "value": {"x": 2, "y": 0.5}}, LIN)]),
                   track("fc", "s", "style.fill.color", [k("c", 0, {"type": "color", "value": {"r": 1, "g": 0, "b": 0, "a": 1}}, LIN), k("d", 40, {"type": "color", "value": {"r": 0, "g": 0, "b": 1, "a": 0.2}}, LIN)]),
                   track("rw", "s", "shape.rect.size", [k("e", 0, {"type": "size", "value": {"x": 10, "y": 10}}, EIO), k("f", 20, {"type": "size", "value": {"x": 30, "y": 10}}, LIN)])],
        "motionPaths": []}
exp = []
for f in [0, 5, 12, 25, 40, 50]:
    t = spring_at(1, 200, 3, 0, f / 50)
    exp.append({"frame": f, "nodeId": "s", "property": "scale", "value": [1 + (2 - 1) * t, 1 + (0.5 - 1) * t], "tolerance": 1e-6})
for f in [0, 10, 40, 45]:
    u = min(1, f / 40); exp.append({"frame": f, "nodeId": "s", "property": "fill", "value": [1 - u, 1 - 0.8 * u]})
for f in [0, 10, 20]:
    u = cubic_at(0.42, 0, 0.58, 1, f / 20); exp.append({"frame": f, "nodeId": "s", "property": "rectWidth", "value": 10 + 20 * u, "tolerance": 1e-6})
goldens.append({"name": "spring-colour-size", "animation": anim, "expectations": exp})

path = {"subpaths": [{"start": {"x": 0, "y": 0}, "closed": False, "segments": [{"type": "line", "to": {"x": 100, "y": 0}}, {"type": "line", "to": {"x": 100, "y": 100}}]}]}
anim = {"version": 1, "scene": scene("motion", dur=40), "nodes": [node("m", "polygon", {"sides": 3, "radius": 5, "innerRadius": None}, {"translation": {"x": 50, "y": 50}}, motion={"pathId": "mp", "orient": True})],
        "tracks": [track("p", "m", "motion.progress", [k("a", 0, {"type": "scalar", "value": 0}, LIN), k("b", 40, {"type": "scalar", "value": 1}, LIN)])],
        "motionPaths": [{"id": "mp", "geometry": path}]}
exp = []
for f, (x, y) in {0: (0, 0), 10: (50, 0), 20: (100, 0), 30: (100, 50), 40: (100, 100)}.items():
    exp.append({"frame": f, "nodeId": "m", "property": "position", "value": [50 + x, 50 + y], "tolerance": 1e-6})
goldens.append({"name": "motion-path-polyline", "animation": anim, "expectations": exp})

here = os.path.dirname(os.path.abspath(__file__))
for g in goldens:
    with open(os.path.join(here, f"{g['name']}.json"), "w") as fh:
        json.dump(g, fh, indent=2)
        fh.write("\n")
print("written", len(goldens))
