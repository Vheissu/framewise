module Domain.LayerTime exposing
    ( cutAt
    , maxShift
    , minShift
    , moveEdgeTo
    , setSpan
    , shift
    , spanOf
    , trimEdge
    )

{-| Layer timing: in and out points and moving layers along the timeline.
Moving a layer carries its keyframes, and those of everything inside it,
so the animation plays the same, just earlier or later. Trimming only moves
an in or out point and leaves the keys where they are.

Keyframes never sit before frame 0. When a move pushes keys past it, each
track is cut at frame 0: the keys before are dropped and a key at 0 starts
the remaining part of the segment, with its easing split so every frame from
0 on keeps the same value. Springs cannot be split that way, so a move stops
before it would cut through one.

-}

import Dict
import Domain.Easing as Easing exposing (Easing(..))
import Domain.Interpolation as Interpolation
import Domain.Keyframe as Keyframe exposing (Track)
import Domain.Node exposing (Span)
import Domain.Property as Property
import Domain.Scene as Scene exposing (Scene)
import Shared.Ids exposing (NodeId)


{-| The layer's span, with no span meaning the whole scene.
-}
spanOf : Scene -> NodeId -> Span
spanOf scene id =
    Dict.get id scene.nodes
        |> Maybe.andThen .span
        |> Maybe.withDefault { inFrame = 0, outFrame = scene.durationFrames }


{-| Store a span, dropping it when it covers the whole scene so untouched
and restored layers look the same in the file.
-}
setSpan : NodeId -> Span -> Scene -> Scene
setSpan id span scene =
    let
        stored =
            if span.inFrame <= 0 && span.outFrame >= scene.durationFrames then
                Nothing

            else
                Just span
    in
    Scene.updateNode id (\n -> { n | span = stored }) scene


{-| The layers and everything inside them, each once.
-}
withDescendants : Scene -> List NodeId -> List NodeId
withDescendants scene ids =
    ids
        |> List.concatMap (\id -> id :: Scene.descendants id scene)
        |> List.foldl
            (\id acc ->
                if List.member id acc then
                    acc

                else
                    acc ++ [ id ]
            )
            []


{-| Move layers by a number of frames, keys included.
-}
shift : List NodeId -> Int -> Scene -> Scene
shift ids delta scene =
    let
        affected =
            withDescendants scene ids

        moveSpan id s =
            case Dict.get id s.nodes |> Maybe.andThen .span of
                Just span ->
                    Scene.updateNode id (\n -> { n | span = Just { inFrame = span.inFrame + delta, outFrame = span.outFrame + delta } }) s

                Nothing ->
                    s

        moveTracks id s =
            List.foldl
                (\track acc -> Scene.upsertTrack (shiftTrack delta track) acc)
                s
                (Scene.tracksFor id scene)

        -- a top-level layer without a span gets one, so it can move
        explicit =
            List.foldl
                (\id s ->
                    case Dict.get id s.nodes |> Maybe.andThen .span of
                        Just _ ->
                            s

                        Nothing ->
                            Scene.updateNode id (\n -> { n | span = Just (spanOf scene id) }) s
                )
                scene
                ids
    in
    if delta == 0 then
        scene

    else
        List.foldl (\id s -> moveTracks id (moveSpan id s)) explicit affected
            |> (\s -> List.foldl (\id acc -> setSpan id (spanOf acc id) acc) s ids)


{-| The furthest left the layers can move: nothing may start before frame 0.
-}
minShift : List NodeId -> Scene -> Int
minShift ids scene =
    let
        affected =
            withDescendants scene ids

        -- keys may be cut at frame 0, but never through a spring segment
        springStarts track =
            List.map2
                (\k next ->
                    if Property.isDiscrete track.target.property || tailEasing k.easing 0.5 /= Nothing then
                        Nothing

                    else
                        Just (min k.frame next.frame)
                )
                track.keyframes
                (List.drop 1 track.keyframes)
                |> List.filterMap identity

        starts =
            List.map (\id -> (spanOf scene id).inFrame) ids
                ++ List.concatMap (\id -> Scene.tracksFor id scene |> List.concatMap springStarts) affected
    in
    starts |> List.minimum |> Maybe.map negate |> Maybe.withDefault 0


{-| Move every key of a track, cutting it at frame 0 if keys pass it.
-}
shiftTrack : Int -> Track -> Track
shiftTrack delta track =
    let
        moved =
            { track | keyframes = List.map (\k -> { k | frame = k.frame + delta }) track.keyframes }
    in
    if List.any (\k -> k.frame < 0) moved.keyframes then
        cutAt 0 moved |> Maybe.withDefault (Keyframe.shift (List.map .id track.keyframes) delta track)

    else
        moved


{-| Drop the keys before a frame without changing the value at that frame or
any later one. Fails when the segment through the cut has an easing whose
remainder is not itself an easing (a spring).
-}
cutAt : Int -> Track -> Maybe Track
cutAt cut track =
    let
        ( before, rest ) =
            List.partition (\k -> k.frame < cut) track.keyframes
    in
    case ( List.reverse before, rest ) of
        ( [], _ ) ->
            Just track

        ( b :: _, a :: _ ) ->
            if a.frame == cut then
                Just { track | keyframes = rest }

            else
                let
                    u0 =
                        toFloat (cut - b.frame) / toFloat (a.frame - b.frame)

                    startKey easing progress =
                        { b | frame = cut, easing = easing, value = Interpolation.interpolateValue b.value a.value progress }
                in
                if Property.isDiscrete track.target.property then
                    Just { track | keyframes = { b | frame = cut } :: rest }

                else
                    tailEasing b.easing u0
                        |> Maybe.map (\( easing, progress ) -> { track | keyframes = startKey easing progress :: rest })

        ( b :: _, [] ) ->
            -- past the last key the value holds
            Just { track | keyframes = [ { b | frame = cut } ] }


{-| The easing for the rest of a segment cut at progress `u0`, and how far
the value has already moved by then. Cubic Bézier curves are split exactly
(de Casteljau) and rescaled to the unit square.
-}
tailEasing : Easing -> Float -> Maybe ( Easing, Float )
tailEasing easing u0 =
    case easing of
        Hold ->
            Just ( Hold, 0 )

        Linear ->
            Just ( Linear, u0 )

        CubicBezier x1 y1 x2 y2 ->
            Just (splitBezier x1 y1 x2 y2 u0)

        Preset p ->
            Easing.presetToCubic p |> Maybe.map (\c -> splitBezier c.x1 c.y1 c.x2 c.y2 u0)

        Spring _ ->
            Nothing


splitBezier : Float -> Float -> Float -> Float -> Float -> ( Easing, Float )
splitBezier x1 y1 x2 y2 u0 =
    let
        -- the evaluator clamps the x handles, so split the curve it draws
        cx1 =
            clamp 0 1 x1

        cx2 =
            clamp 0 1 x2

        t =
            Easing.solveBezierX cx1 cx2 u0

        lerp a b =
            { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }

        p1 =
            { x = cx1, y = y1 }

        p2 =
            { x = cx2, y = y2 }

        p3 =
            { x = 1, y = 1 }

        p12 =
            lerp p1 p2

        p23 =
            lerp p2 p3

        p123 =
            lerp p12 p23

        p01 =
            lerp { x = 0, y = 0 } p1

        p012 =
            lerp p01 p12

        start =
            lerp p012 p123

        nx p =
            (p.x - start.x) / max 1.0e-9 (1 - start.x)

        ny p =
            (p.y - start.y) / (1 - start.y)
    in
    if abs (1 - start.y) < 1.0e-9 then
        ( Linear, start.y )

    else
        ( CubicBezier (nx p123) (ny p123) (nx p23) (ny p23), start.y )


{-| The furthest right the layers can move: each keeps at least one frame
inside the scene.
-}
maxShift : List NodeId -> Scene -> Int
maxShift ids scene =
    ids
        |> List.map (\id -> scene.durationFrames - 1 - (spanOf scene id).inFrame)
        |> List.minimum
        |> Maybe.withDefault 0


{-| Move the in point (`True`) or out point of a layer by a number of frames,
keeping at least one frame between them and the in point at or after 0.
-}
trimEdge : Bool -> Int -> NodeId -> Scene -> Scene
trimEdge isIn delta id scene =
    let
        span =
            spanOf scene id
    in
    if isIn then
        setSpan id { span | inFrame = clamp 0 (span.outFrame - 1) (span.inFrame + delta) } scene

    else
        setSpan id { span | outFrame = max (span.inFrame + 1) (span.outFrame + delta) } scene


{-| Move a layer so its in point (`True`) or out point lands on a frame, as
After Effects does with [ and ]. Keys move with the layer.
-}
moveEdgeTo : Bool -> Int -> NodeId -> Scene -> Scene
moveEdgeTo isIn frame id scene =
    let
        span =
            spanOf scene id

        wanted =
            if isIn then
                frame - span.inFrame

            else
                frame - span.outFrame
    in
    shift [ id ] (clamp (minShift [ id ] scene) (max 0 (maxShift [ id ] scene)) wanted) scene
