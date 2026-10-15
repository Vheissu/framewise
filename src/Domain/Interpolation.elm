module Domain.Interpolation exposing
    ( AngleMode(..)
    , evaluateTrack
    , interpolateValue
    )

{-| Interpolation between keyframe values following the outgoing easing of
the earlier key. Pure and deterministic.
-}

import Domain.Color as Color
import Domain.Easing as Easing exposing (Easing)
import Domain.Keyframe as Keyframe exposing (Keyframe, Track)
import Domain.Path as Path
import Domain.Property as Property exposing (PropertyPath, PropertyValue(..))
import Domain.Vec2 as Vec2


type AngleMode
    = ShortestArc
    | Unbounded


{-| Evaluate a track at a continuous frame. Returns Nothing when the track has
no keys (caller uses the base value).
-}
evaluateTrack : Float -> Track -> Maybe PropertyValue
evaluateTrack frame track =
    case track.keyframes of
        [] ->
            Nothing

        [ only ] ->
            Just only.value

        _ ->
            let
                seg =
                    Keyframe.segmentAt frame track
            in
            case ( seg.before, seg.after ) of
                ( Nothing, Just after ) ->
                    Just after.value

                ( Just before, Nothing ) ->
                    Just before.value

                ( Just before, Just after ) ->
                    Just (interpolateKeys track.target.property before after frame)

                ( Nothing, Nothing ) ->
                    Nothing


interpolateKeys : PropertyPath -> Keyframe -> Keyframe -> Float -> PropertyValue
interpolateKeys property before after frame =
    let
        span =
            toFloat (after.frame - before.frame)

        u =
            if span <= 0 then
                1

            else
                clamp 0 1 ((frame - toFloat before.frame) / span)
    in
    if Property.isDiscrete property then
        if u >= 1 then
            after.value

        else
            before.value

    else
        let
            t =
                Easing.evaluate before.easing u
        in
        interpolateValue before.value after.value t


{-| Interpolate two typed values. Mismatched kinds step at the midpoint.
-}
interpolateValue : PropertyValue -> PropertyValue -> Float -> PropertyValue
interpolateValue va vb t =
    case ( va, vb ) of
        ( Scalar a, Scalar b ) ->
            Scalar (lerp a b t)

        ( Angle a, Angle b ) ->
            Angle (lerp a b t)

        ( PointValue a, PointValue b ) ->
            PointValue (Vec2.lerp a b t)

        ( SizeValue a, SizeValue b ) ->
            SizeValue (Vec2.lerp a b t)

        ( ColorValue a, ColorValue b ) ->
            ColorValue (Color.interpolate a b (clamp 0 1 t))

        ( NumberList a, NumberList b ) ->
            if List.length a == List.length b then
                NumberList (List.map2 (\x y -> lerp x y t) a b)

            else
                step va vb t

        ( PathValue a, PathValue b ) ->
            if Path.isCompatible a b then
                PathValue (Path.interpolate a b t)

            else
                step va vb t

        _ ->
            step va vb t


step : PropertyValue -> PropertyValue -> Float -> PropertyValue
step va vb t =
    if t >= 1 then
        vb

    else
        va


lerp : Float -> Float -> Float -> Float
lerp a b t =
    a + (b - a) * t
