/*
 * Framewise Player — standalone runtime for animations exported from Framewise.
 *
 * Plain script, no dependencies, no eval, no network. Defines a global
 * `FramewisePlayer` with `create(container, animation, options)` and a pure
 * `evaluate(animation, frame)` used by the test-suite to keep this runtime in
 * lock-step with the editor's evaluator through shared golden fixtures.
 *
 * Licence: MIT (same as Framewise).
 */
(function (root) {
  "use strict";

  // ---------- easing ----------

  var PRESETS = {
    "ease": [0.25, 0.1, 0.25, 1],
    "ease-in": [0.42, 0, 1, 1],
    "ease-out": [0, 0, 0.58, 1],
    "ease-in-out": [0.42, 0, 0.58, 1]
  };

  function bezierComponent(p1, p2, t) {
    var mt = 1 - t;
    return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t;
  }

  function bezierDerivative(p1, p2, t) {
    var mt = 1 - t;
    return 3 * mt * mt * p1 + 6 * mt * t * (p2 - p1) + 3 * t * t * (1 - p2);
  }

  function solveBezierX(x1, x2, x) {
    var cx1 = clamp(x1, 0, 1), cx2 = clamp(x2, 0, 1);
    var t = x;
    for (var i = 0; i < 12; i++) {
      var fx = bezierComponent(cx1, cx2, t) - x;
      if (Math.abs(fx) < 1e-7) return t;
      var dx = bezierDerivative(cx1, cx2, t);
      if (Math.abs(dx) < 1e-6) return bisect(cx1, cx2, x);
      var next = t - fx / dx;
      if (next < 0 || next > 1) return bisect(cx1, cx2, x);
      t = next;
    }
    return t;
  }

  function bisect(x1, x2, x) {
    var lo = 0, hi = 1, mid = 0.5;
    for (var i = 0; i < 40; i++) {
      mid = (lo + hi) / 2;
      var fx = bezierComponent(x1, x2, mid) - x;
      if (Math.abs(fx) < 1e-7) return mid;
      if (fx > 0) hi = mid; else lo = mid;
    }
    return mid;
  }

  function cubicBezierAt(x1, y1, x2, y2, x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return bezierComponent(y1, y2, solveBezierX(x1, x2, x));
  }

  function backIn(u) { var c1 = 1.70158, c3 = c1 + 1; return c3 * u * u * u - c1 * u * u; }

  function elasticIn(u) {
    if (u <= 0) return 0;
    if (u >= 1) return 1;
    var c4 = (2 * Math.PI) / 3;
    return -Math.pow(2, 10 * u - 10) * Math.sin((u * 10 - 10.75) * c4);
  }

  function bounceOut(u) {
    var n1 = 7.5625, d1 = 2.75, v;
    if (u < 1 / d1) return n1 * u * u;
    if (u < 2 / d1) { v = u - 1.5 / d1; return n1 * v * v + 0.75; }
    if (u < 2.5 / d1) { v = u - 2.25 / d1; return n1 * v * v + 0.9375; }
    v = u - 2.625 / d1; return n1 * v * v + 0.984375;
  }

  function spring(p, u) {
    if (u <= 0) return 0;
    if (u >= 1) return 1;
    var m = Math.max(0.001, p.mass), k = Math.max(0.001, p.stiffness), c = Math.max(0, p.damping), v0 = p.velocity || 0;
    var t = u, w0 = Math.sqrt(k / m), zeta = c / (2 * Math.sqrt(k * m)), x0 = -1, disp;
    if (zeta < 1) {
      var wd = w0 * Math.sqrt(1 - zeta * zeta);
      var a = x0, b = (zeta * w0 * x0 + v0) / wd;
      disp = Math.exp(-zeta * w0 * t) * (a * Math.cos(wd * t) + b * Math.sin(wd * t));
    } else if (zeta === 1) {
      disp = (x0 + (v0 + w0 * x0) * t) * Math.exp(-w0 * t);
    } else {
      var s1 = -w0 * (zeta - Math.sqrt(zeta * zeta - 1));
      var s2 = -w0 * (zeta + Math.sqrt(zeta * zeta - 1));
      var c2 = (v0 - s1 * x0) / (s2 - s1), c1 = x0 - c2;
      disp = c1 * Math.exp(s1 * t) + c2 * Math.exp(s2 * t);
    }
    return 1 + disp;
  }

  function evaluateEasing(easing, u) {
    var uc = clamp(u, 0, 1);
    switch (easing.type) {
      case "hold": return uc >= 1 ? 1 : 0;
      case "linear": return uc;
      case "cubicBezier": return cubicBezierAt(easing.x1, easing.y1, easing.x2, easing.y2, uc);
      case "spring": return spring(easing, uc);
      case "preset": {
        var c = PRESETS[easing.name];
        if (c) return cubicBezierAt(c[0], c[1], c[2], c[3], uc);
        switch (easing.name) {
          case "back-in": return backIn(uc);
          case "back-out": return 1 - backIn(1 - uc);
          case "elastic-in": return elasticIn(uc);
          case "elastic-out": return 1 - elasticIn(1 - uc);
          case "bounce-in": return 1 - bounceOut(1 - uc);
          case "bounce-out": return bounceOut(uc);
          default: return uc;
        }
      }
      default: return uc;
    }
  }

  // ---------- values ----------

  var DISCRETE = { "compositing.visible": true, "text.content": true };

  function lerp(a, b, t) { return a + (b - a) * t; }

  function lerpPoint(a, b, t) { return { x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t) }; }

  function lerpColor(a, b, t) {
    var tc = clamp(t, 0, 1);
    return { r: clamp(lerp(a.r, b.r, tc), 0, 1), g: clamp(lerp(a.g, b.g, tc), 0, 1), b: clamp(lerp(a.b, b.b, tc), 0, 1), a: clamp(lerp(a.a, b.a, tc), 0, 1) };
  }

  function pathsCompatible(a, b) {
    if (a.subpaths.length !== b.subpaths.length) return false;
    for (var i = 0; i < a.subpaths.length; i++) {
      if (a.subpaths[i].segments.length !== b.subpaths[i].segments.length) return false;
      if (!!a.subpaths[i].closed !== !!b.subpaths[i].closed) return false;
    }
    return true;
  }

  function segEnd(seg) { return seg.to; }

  function asCubic(start, seg) {
    if (seg.type === "line") return { c1: lerpPoint(start, seg.to, 1 / 3), c2: lerpPoint(start, seg.to, 2 / 3), to: seg.to };
    return { c1: seg.c1, c2: seg.c2, to: seg.to };
  }

  function lerpPath(a, b, t) {
    var subpaths = [];
    for (var i = 0; i < a.subpaths.length; i++) {
      var sa = a.subpaths[i], sb = b.subpaths[i];
      var segments = [], prevA = sa.start, prevB = sb.start;
      for (var j = 0; j < sa.segments.length; j++) {
        var ga = sa.segments[j], gb = sb.segments[j];
        if (ga.type === "line" && gb.type === "line") {
          segments.push({ type: "line", to: lerpPoint(ga.to, gb.to, t) });
        } else {
          var ca = asCubic(prevA, ga), cb = asCubic(prevB, gb);
          segments.push({ type: "cubic", c1: lerpPoint(ca.c1, cb.c1, t), c2: lerpPoint(ca.c2, cb.c2, t), to: lerpPoint(ca.to, cb.to, t) });
        }
        prevA = segEnd(ga); prevB = segEnd(gb);
      }
      subpaths.push({ start: lerpPoint(sa.start, sb.start, t), closed: sa.closed, segments: segments });
    }
    return { subpaths: subpaths };
  }

  function interpolateValue(va, vb, t) {
    if (va.type !== vb.type) return t >= 1 ? vb : va;
    switch (va.type) {
      case "scalar":
      case "angle": return { type: va.type, value: lerp(va.value, vb.value, t) };
      case "point":
      case "size": return { type: va.type, value: lerpPoint(va.value, vb.value, t) };
      case "color": return { type: "color", value: lerpColor(va.value, vb.value, t) };
      case "numbers":
        if (va.value.length !== vb.value.length) return t >= 1 ? vb : va;
        return { type: "numbers", value: va.value.map(function (x, i) { return lerp(x, vb.value[i], t); }) };
      case "path":
        if (!pathsCompatible(va.value, vb.value)) return t >= 1 ? vb : va;
        return { type: "path", value: lerpPath(va.value, vb.value, t) };
      default: return t >= 1 ? vb : va;
    }
  }

  function evaluateTrack(track, frame) {
    var keys = track.keyframes;
    if (!keys || keys.length === 0) return null;
    if (keys.length === 1) return keys[0].value;
    var before = null, after = null;
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      if (k.frame <= frame) before = k; else if (!after) after = k;
    }
    if (!before) return after.value;
    if (!after) return before.value;
    var span = after.frame - before.frame;
    var u = span <= 0 ? 1 : clamp((frame - before.frame) / span, 0, 1);
    if (DISCRETE[track.target.property]) return u >= 1 ? after.value : before.value;
    return interpolateValue(before.value, after.value, evaluateEasing(before.easing || { type: "linear" }, u));
  }

  // ---------- geometry ----------

  function mul(m, n) {
    return { a: m.a * n.a + m.c * n.b, b: m.b * n.a + m.d * n.b, c: m.a * n.c + m.c * n.d, d: m.b * n.c + m.d * n.d, e: m.a * n.e + m.c * n.f + m.e, f: m.b * n.e + m.d * n.f + m.f };
  }
  var I = { a: 1, b: 0, c: 0, d: 1, e: 0, f: 0 };
  function translation(x, y) { return { a: 1, b: 0, c: 0, d: 1, e: x, f: y }; }
  function scaling(x, y) { return { a: x, b: 0, c: 0, d: y, e: 0, f: 0 }; }
  function rotation(deg) { var r = deg * Math.PI / 180, cs = Math.cos(r), sn = Math.sin(r); return { a: cs, b: sn, c: -sn, d: cs, e: 0, f: 0 }; }
  function skewing(sx, sy) {
    var tx = Math.tan(sx * Math.PI / 180), ty = Math.tan(sy * Math.PI / 180);
    return mul({ a: 1, b: 0, c: tx, d: 1, e: 0, f: 0 }, { a: 1, b: ty, c: 0, d: 1, e: 0, f: 0 });
  }
  function compose(list) { var m = I; for (var i = 0; i < list.length; i++) m = mul(list[i], m); return m; }

  function localMatrix(t, motion) {
    var parts = [translation(-t.pivot.x, -t.pivot.y), scaling(t.scale.x, t.scale.y), skewing(t.skew.x, t.skew.y), rotation(t.rotation), translation(t.pivot.x, t.pivot.y)];
    if (motion) parts.push(rotation(motion.angle), translation(motion.offset.x, motion.offset.y));
    parts.push(translation(t.translation.x, t.translation.y));
    return compose(parts);
  }

  function num(v) {
    var r = Math.round(v * 100000) / 100000;
    if (!isFinite(r)) return "0";
    return String(r);
  }

  function matrixString(m) { return "matrix(" + [m.a, m.b, m.c, m.d, m.e, m.f].map(num).join(" ") + ")"; }

  function pnum(v) { var r = Math.round(v * 1000) / 1000; return String(r); }

  function serializePath(g) {
    return g.subpaths.map(function (s) {
      var parts = ["M" + pnum(s.start.x) + " " + pnum(s.start.y)];
      s.segments.forEach(function (seg) {
        if (seg.type === "line") parts.push("L" + pnum(seg.to.x) + " " + pnum(seg.to.y));
        else parts.push("C" + pnum(seg.c1.x) + " " + pnum(seg.c1.y) + " " + pnum(seg.c2.x) + " " + pnum(seg.c2.y) + " " + pnum(seg.to.x) + " " + pnum(seg.to.y));
      });
      return parts.join(" ") + (s.closed ? " Z" : "");
    }).join(" ");
  }

  function cubicPoint(p0, p1, p2, p3, t) {
    var mt = 1 - t, a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t;
    return { x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y };
  }
  function cubicTangent(p0, p1, p2, p3, t) {
    var mt = 1 - t;
    return { x: 3 * mt * mt * (p1.x - p0.x) + 6 * mt * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x), y: 3 * mt * mt * (p1.y - p0.y) + 6 * mt * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y) };
  }

  // arc-length table matching Domain.Path.arcTable with 16 subdivisions
  function arcTable(g) {
    var n = 16, samples = [], total = 0, prev = null;
    g.subpaths.forEach(function (s) {
      var segs = s.segments.slice();
      if (s.closed) segs.push({ type: "line", to: s.start });
      var pts = [];
      var start = s.start;
      segs.forEach(function (seg) {
        for (var i = 1; i <= n; i++) {
          var t = i / n;
          if (seg.type === "line") pts.push({ p: lerpPoint(start, seg.to, t), tg: { x: seg.to.x - start.x, y: seg.to.y - start.y } });
          else pts.push({ p: cubicPoint(start, seg.c1, seg.c2, seg.to, t), tg: cubicTangent(start, seg.c1, seg.c2, seg.to, t) });
        }
        start = seg.to;
      });
      var firstTangent = pts.length ? pts[0].tg : { x: 1, y: 0 };
      pts.unshift({ p: s.start, tg: firstTangent });
      pts.forEach(function (pt) {
        var d = prev ? Math.hypot(pt.p.x - prev.x, pt.p.y - prev.y) : 0;
        total += d;
        samples.push({ length: total, point: pt.p, tangent: pt.tg });
        prev = pt.p;
      });
    });
    return { samples: samples, total: total };
  }

  function safeTangent(t) {
    var l = Math.hypot(t.x, t.y);
    if (l === 0) return { x: 1, y: 0 };
    return { x: t.x / l, y: t.y / l };
  }

  function pointAtLength(table, dist) {
    if (table.samples.length === 0) return { point: { x: 0, y: 0 }, tangent: { x: 1, y: 0 } };
    var first = table.samples[0];
    if (table.total <= 0) return { point: first.point, tangent: safeTangent(first.tangent) };
    var d = clamp(dist, 0, table.total), prev = first;
    for (var i = 0; i < table.samples.length; i++) {
      var s = table.samples[i];
      if (s.length >= d) {
        var span = s.length - prev.length, t = span <= 0 ? 1 : (d - prev.length) / span;
        return { point: lerpPoint(prev.point, s.point, t), tangent: safeTangent(s.tangent) };
      }
      prev = s;
    }
    return { point: prev.point, tangent: safeTangent(prev.tangent) };
  }

  // ---------- evaluation ----------

  function indexTracks(animation) {
    var byNode = {};
    (animation.tracks || []).forEach(function (t) {
      if (t.enabled === false || !t.keyframes || t.keyframes.length === 0) return;
      var id = t.target.nodeId;
      (byNode[id] = byNode[id] || {})[t.target.property] = t;
    });
    return byNode;
  }

  function valueOf(tracks, prop, frame) {
    var t = tracks && tracks[prop];
    return t ? evaluateTrack(t, frame) : null;
  }

  /** Evaluate every node at `frame`. Returns a map nodeId -> resolved state. */
  function evaluate(animation, frame) {
    var byNode = indexTracks(animation);
    var motionPaths = {};
    (animation.motionPaths || []).forEach(function (mp) { motionPaths[mp.id] = mp; });
    var result = {};
    var f = isFinite(frame) ? frame : 0;
    (animation.nodes || []).forEach(function (node) {
      var tr = byNode[node.id];
      var base = node.transform;
      var pt = function (prop, def) { var v = valueOf(tr, prop, f); return v && (v.type === "point" || v.type === "size") ? v.value : def; };
      var sc = function (prop, def) { var v = valueOf(tr, prop, f); return v && (v.type === "scalar" || v.type === "angle") ? v.value : def; };
      var transform = {
        translation: pt("transform.position", base.translation),
        scale: pt("transform.scale", base.scale),
        rotation: sc("transform.rotation", base.rotation),
        skew: pt("transform.skew", base.skew || { x: 0, y: 0 }),
        pivot: pt("transform.pivot", base.pivot || { x: 0, y: 0 })
      };
      var motion = null;
      if (node.motion && motionPaths[node.motion.pathId]) {
        var mp = motionPaths[node.motion.pathId];
        var table = arcTable(mp.geometry);
        var progress = clamp(sc("motion.progress", 0), 0, 1);
        var sample = pointAtLength(table, progress * table.total);
        motion = { offset: sample.point, angle: node.motion.orient === false ? 0 : Math.atan2(sample.tangent.y, sample.tangent.x) * 180 / Math.PI };
      }
      var visible = valueOf(tr, "compositing.visible", f);
      var fillColor = valueOf(tr, "style.fill.color", f);
      var strokeColor = valueOf(tr, "style.stroke.color", f);
      var pathValue = valueOf(tr, "shape.path.geometry", f);
      var textValue = valueOf(tr, "text.content", f);
      var state = {
        matrix: localMatrix(transform, motion),
        transform: transform,
        opacity: clamp(sc("compositing.opacity", node.opacity), 0, 1),
        hidden: visible && visible.type === "bool" ? !visible.value : !!node.hidden,
        fill: fillColor && fillColor.type === "color" ? fillColor.value : (node.fill && node.fill.type === "solid" ? node.fill.color : null),
        stroke: strokeColor && strokeColor.type === "color" ? strokeColor.value : (node.stroke && node.stroke.paint && node.stroke.paint.type === "solid" ? node.stroke.paint.color : null),
        strokeWidth: Math.max(0, sc("style.stroke.width", node.stroke ? node.stroke.width : 0)),
        dashOffset: sc("style.stroke.dashOffset", node.stroke ? node.stroke.dashOffset : 0),
        rectSize: node.kind === "rect" ? pt("shape.rect.size", node.geometry.size) : null,
        cornerRadius: node.kind === "rect" ? Math.max(0, sc("shape.rect.cornerRadius", node.geometry.cornerRadius)) : null,
        radii: node.kind === "ellipse" ? pt("shape.ellipse.radii", node.geometry.radii) : null,
        path: node.kind === "path" ? (pathValue && pathValue.type === "path" ? pathValue.value : node.geometry) : null,
        fontSize: node.kind === "text" ? Math.max(0.1, sc("text.fontSize", node.geometry.fontSize)) : null,
        text: node.kind === "text" ? (textValue && textValue.type === "string" ? textValue.value : node.geometry.content) : null,
        blur: sc("effects.blur.radius", null)
      };
      result[node.id] = state;
    });
    return result;
  }

  // ---------- DOM application ----------

  function hex(c) {
    var h = function (v) { var n = Math.round(clamp(v, 0, 1) * 255); return (n < 16 ? "0" : "") + n.toString(16); };
    return "#" + h(c.r) + h(c.g) + h(c.b);
  }

  function findNodeElement(container, id) {
    var all = container.querySelectorAll("g[id$='-node-" + id + "']");
    return all.length ? all[0] : null;
  }

  function applyState(container, animation, states, cache) {
    (animation.nodes || []).forEach(function (node) {
      var st = states[node.id];
      if (!st) return;
      var el = cache[node.id];
      if (el === undefined) { el = findNodeElement(container, node.id); cache[node.id] = el; }
      if (!el) return;
      el.setAttribute("transform", matrixString(st.matrix));
      if (st.opacity < 1) el.setAttribute("opacity", num(st.opacity)); else el.removeAttribute("opacity");
      el.setAttribute("visibility", st.hidden ? "hidden" : "visible");
      var shape = el.firstElementChild;
      if (!shape || node.kind === "group" || node.kind === "clipGroup") return;
      if (shape.tagName === "g") return;
      if (st.fill) { shape.setAttribute("fill", hex(st.fill)); if (st.fill.a < 1) shape.setAttribute("fill-opacity", num(st.fill.a)); else shape.removeAttribute("fill-opacity"); }
      if (st.stroke) { shape.setAttribute("stroke", hex(st.stroke)); if (st.stroke.a < 1) shape.setAttribute("stroke-opacity", num(st.stroke.a)); else shape.removeAttribute("stroke-opacity"); shape.setAttribute("stroke-width", num(st.strokeWidth)); if (shape.hasAttribute("stroke-dasharray")) shape.setAttribute("stroke-dashoffset", num(st.dashOffset)); }
      if (st.rectSize) { shape.setAttribute("width", num(st.rectSize.x)); shape.setAttribute("height", num(st.rectSize.y)); if (st.cornerRadius > 0) shape.setAttribute("rx", num(st.cornerRadius)); else shape.removeAttribute("rx"); }
      if (st.radii) { shape.setAttribute("rx", num(st.radii.x)); shape.setAttribute("ry", num(st.radii.y)); }
      if (st.path) shape.setAttribute("d", serializePath(st.path));
      if (st.fontSize !== null) { shape.setAttribute("font-size", num(st.fontSize)); if (shape.textContent !== st.text) shape.textContent = st.text; }
      if (st.blur !== null) {
        var filterId = el.getAttribute("filter");
        var m = filterId && /url\(#([^)]+)\)/.exec(filterId);
        if (m) { var blur = container.querySelector("#" + cssEscape(m[1]) + " feGaussianBlur"); if (blur) blur.setAttribute("stdDeviation", num(st.blur)); }
      }
    });
  }

  function cssEscape(s) { return s.replace(/([^\w-])/g, "\\$1"); }

  // ---------- loop mapping ----------

  function fmod(a, b) { return a - b * Math.floor(a / b); }

  function mapFrame(mode, n, frame) {
    var nf = Math.max(1, n);
    if (mode === "once") return clamp(frame, 0, nf);
    if (mode === "pingpong") { var period = 2 * nf, m = fmod(frame, period); return m <= nf ? m : period - m; }
    return fmod(frame, nf);
  }

  // ---------- player ----------

  function create(container, animation, options) {
    options = options || {};
    var scene = animation.scene;
    var fps = scene.fps.numerator / scene.fps.denominator;
    var duration = scene.durationFrames;
    var loop = scene.playbackMode || "repeat";
    var speed = 1, playing = false, startTime = 0, startFrame = 0, current = 0, raf = 0, destroyed = false;
    var cache = {};
    var controls = options.controls || null;
    var ui = {};

    function render(frame) {
      current = frame;
      applyState(container, animation, evaluate(animation, frame), cache);
      if (ui.seek) ui.seek.value = String(Math.round(frame));
      if (ui.time) ui.time.textContent = Math.round(frame) + " / " + duration;
    }

    function tick(now) {
      if (!playing || destroyed) return;
      if (startTime === 0) startTime = now;
      var elapsed = (now - startTime) / 1000;
      var raw = startFrame + elapsed * fps * speed;
      var mapped = mapFrame(loop, duration, raw);
      render(mapped);
      if (loop === "once" && raw >= duration) { playing = false; updateToggle(); return; }
      raf = root.requestAnimationFrame(tick);
    }

    function updateToggle() { if (ui.toggle) { ui.toggle.textContent = playing ? "Pause" : "Play"; ui.toggle.setAttribute("aria-pressed", playing ? "true" : "false"); } }

    var player = {
      play: function () { if (destroyed || playing) return; if (loop === "once" && current >= duration) current = 0; playing = true; startTime = 0; startFrame = current; updateToggle(); raf = root.requestAnimationFrame(tick); },
      pause: function () { playing = false; root.cancelAnimationFrame(raf); updateToggle(); },
      stop: function () { player.pause(); render(0); },
      seekFrame: function (frame) { var f = clamp(Number(frame) || 0, 0, duration); startFrame = f; startTime = 0; render(f); },
      seekSeconds: function (seconds) { player.seekFrame((Number(seconds) || 0) * fps); },
      setSpeed: function (s) { var v = Number(s); if (!(v > 0)) return; startFrame = current; startTime = 0; speed = v; },
      setLoop: function (mode) { if (mode === "none") loop = "once"; else if (mode === "repeat" || mode === "pingpong") loop = mode; startFrame = current; startTime = 0; },
      getCurrentFrame: function () { return current; },
      getDurationSeconds: function () { return duration / fps; },
      destroy: function () { destroyed = true; player.pause(); if (controls) controls.removeEventListener("click", onControl); }
    };

    function onControl(event) {
      var target = event.target.closest ? event.target.closest("[data-fw]") : null;
      if (!target) return;
      var action = target.getAttribute("data-fw");
      if (action === "toggle") { if (playing) player.pause(); else player.play(); }
      else if (action === "restart") { player.seekFrame(0); if (!playing) player.play(); }
    }

    if (controls) {
      ui.toggle = controls.querySelector("[data-fw=toggle]");
      ui.seek = controls.querySelector("[data-fw=seek]");
      ui.time = controls.querySelector("[data-fw=time]");
      var loopBox = controls.querySelector("[data-fw=loop]");
      var speedSel = controls.querySelector("[data-fw=speed]");
      if (ui.seek) { ui.seek.max = String(duration); ui.seek.addEventListener("input", function () { player.pause(); player.seekFrame(Number(ui.seek.value)); }); }
      if (loopBox) loopBox.addEventListener("change", function () { player.setLoop(loopBox.checked ? (scene.playbackMode === "pingpong" ? "pingpong" : "repeat") : "none"); });
      if (speedSel) speedSel.addEventListener("change", function () { player.setSpeed(speedSel.value); });
      controls.addEventListener("click", onControl);
    }

    render(0);
    updateToggle();
    return player;
  }

  function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }

  root.FramewisePlayer = {
    version: 1,
    create: create,
    evaluate: evaluate,
    evaluateEasing: evaluateEasing,
    evaluateTrack: evaluateTrack,
    mapFrame: mapFrame,
    localMatrix: localMatrix,
    serializePath: serializePath,
    arcTable: arcTable,
    pointAtLength: pointAtLength
  };
})(typeof globalThis !== "undefined" ? globalThis : typeof window !== "undefined" ? window : this);
