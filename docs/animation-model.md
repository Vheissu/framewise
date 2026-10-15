# Animation model

## Time

Keyframes sit on integer frames from 0. A scene's frame rate is a rational `numerator/denominator`, so 29.97 is stored exactly as 30000/1001. `durationFrames` counts rendered intervals: a 60-frame scene at 30 fps lasts 2 seconds, renders frames 0 to 59 for video and has an endpoint at frame 60 used by loops and timeline editing. Keys may sit on the endpoint frame.

Playback derives the frame from the elapsed time since play started (`startFrame + seconds · fps · speed`), never by adding a delta each tick, so long runs do not drift. The playhead can hold a fractional frame during playback and scrubbing; typed values snap to integers.

Loop mapping for a scene of `N` frames: once clamps to `[0, N]`; repeat wraps into `[0, N)` with a true modulo (negative time wraps backwards); ping-pong mirrors over `[0, N]` with period `2N`.

## Tracks

A track targets one property of one node and holds sorted keys with unique frames. Inserting at an occupied frame overwrites. Each key's easing governs the segment that follows it. Before the first key the first value holds; after the last, the last. A track with no keys contributes nothing; a disabled track is ignored without losing its keys.

Values are typed: scalar, angle, point, size, colour, bool, string, path, number list. Interpolation is `va + (vb − va) · easing(u)` for numbers and vectors, straight RGBA interpolation for colours, pointwise for paths with the same structure, and stepping for discrete properties (visibility, text content) or mismatched kinds.

## Easing

Hold, linear, the CSS presets (`ease`, `ease-in`, `ease-out`, `ease-in-out`), overshoot presets (back, elastic, bounce) and cubic Bézier curves with editable handles. Bézier X is inverted with Newton iteration and a bisection fallback. Springs use the closed-form damped oscillator (mass, stiffness, damping, initial velocity) evaluated over the segment, so the result is the same at any frame rate.

## Auto-keyframe

With Auto-Keyframe on, editing an animatable value at a frame other than 0 records a key there; if the property had no track, a frame-0 key holding the previous value is added first so the start of the animation does not change. With it off, editing a value on an animated property follows the preference in Animation settings: edit the nearest key, or add one at the playhead.

## Motion paths

A motion path is a separate geometry attached to a node. The `motion.progress` track maps 0..1 to arc length, not curve parameter, using a cached lookup table. The resulting offset and tangent angle are applied between the node's pivot and its translation, which is the same transform `animateMotion` applies, so SMIL export is exact.
