module Export.Timing exposing
    ( Sample
    , SegmentPlan(..)
    , Spline
    , bake
    , cubicSpline
    , linearSpline
    , plan
    , planTrack
    )

{-| Shared keyframe planning for the declarative exporters (SMIL and CSS).

A track is either expressible natively (every segment has a cubic-Bézier-
representable easing) or must be baked: sampled at every integer frame.

-}

import Domain.Easing as Easing exposing (Easing(..))
import Domain.Interpolation as Interpolation
import Domain.Keyframe exposing (Keyframe, Track)
import Domain.Property exposing (PropertyValue)


type alias Sample =
    { frame : Int, value : PropertyValue }


type alias Spline =
    { x1 : Float, y1 : Float, x2 : Float, y2 : Float }


linearSpline : Spline
linearSpline =
    { x1 = 0, y1 = 0, x2 = 1, y2 = 1 }


type SegmentPlan
    = Native (List { frame : Int, value : PropertyValue, spline : Maybe Spline })
    | BakedPlan (List Sample) String


{-| Cubic Bézier control points for an easing, if representable. SMIL and CSS
both need all control values in `[0,1]` for X; SMIL also requires Y in `[0,1]`.
-}
cubicSpline : Bool -> Easing -> Maybe Spline
cubicSpline requireUnitY easing =
    let
        check c =
            if requireUnitY && (c.y1 < 0 || c.y1 > 1 || c.y2 < 0 || c.y2 > 1) then
                Nothing

            else
                Just c
    in
    case easing of
        Linear ->
            Just linearSpline

        Preset p ->
            Easing.presetToCubic p |> Maybe.andThen check

        CubicBezier x1 y1 x2 y2 ->
            check { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }

        Hold ->
            Nothing

        Spring _ ->
            Nothing


{-| Plan a track over `[0, duration]`. Keys beyond the duration are dropped.
The resulting list always starts at frame 0 and ends at `duration`.
-}
planTrack : Bool -> Int -> Track -> SegmentPlan
planTrack requireUnitY duration track =
    let
        inRange =
            List.filter (\k -> k.frame <= duration) track.keyframes
    in
    case inRange of
        [] ->
            BakedPlan [] "All keyframes are beyond the scene duration"

        _ ->
            let
                nativeSegments =
                    List.map (\k -> ( k, cubicSpline requireUnitY k.easing )) inRange

                lastIsFine ( k, spline ) =
                    -- the final key's easing has no outgoing segment
                    k.frame == maxFrame || spline /= Nothing

                maxFrame =
                    List.map .frame inRange |> List.maximum |> Maybe.withDefault 0
            in
            if List.all lastIsFine nativeSegments then
                Native (pad duration (List.map (\( k, spline ) -> { frame = k.frame, value = k.value, spline = spline }) nativeSegments))

            else
                BakedPlan (bake duration track) (bakeReason inRange)


bakeReason : List Keyframe -> String
bakeReason keys =
    let
        kinds =
            keys
                |> List.filterMap
                    (\k ->
                        case k.easing of
                            Hold ->
                                Just "hold"

                            Spring _ ->
                                Just "spring"

                            Preset p ->
                                case Easing.presetToCubic p of
                                    Nothing ->
                                        Just (Easing.presetToCode p)

                                    Just _ ->
                                        Nothing

                            CubicBezier _ y1 _ y2 ->
                                if y1 < 0 || y1 > 1 || y2 < 0 || y2 > 1 then
                                    Just "overshooting bezier"

                                else
                                    Nothing

                            Linear ->
                                Nothing
                    )
                |> unique
    in
    "Easing (" ++ String.join ", " kinds ++ ") is not representable natively; sampled every frame"


unique : List String -> List String
unique =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []


pad : Int -> List { frame : Int, value : PropertyValue, spline : Maybe Spline } -> List { frame : Int, value : PropertyValue, spline : Maybe Spline }
pad duration keys =
    case ( List.head keys, List.head (List.reverse keys) ) of
        ( Just first, Just last ) ->
            let
                prefix =
                    if first.frame > 0 then
                        [ { frame = 0, value = first.value, spline = Just linearSpline } ]

                    else
                        []

                suffix =
                    if last.frame < duration then
                        [ { frame = duration, value = last.value, spline = Nothing } ]

                    else
                        []

                fixedLast =
                    if last.frame < duration then
                        -- the former final key now has an outgoing (constant) segment
                        List.take (List.length keys - 1) keys ++ [ { last | spline = Just linearSpline } ]

                    else
                        keys
            in
            prefix ++ fixedLast ++ suffix

        _ ->
            keys


{-| Sample a track at every integer frame in `[0, duration]`.
-}
bake : Int -> Track -> List Sample
bake duration track =
    List.range 0 duration
        |> List.filterMap
            (\f ->
                Interpolation.evaluateTrack (toFloat f) track
                    |> Maybe.map (\v -> { frame = f, value = v })
            )


{-| Convenience for callers that just want (frame, value, spline) triples.
-}
plan : Bool -> Int -> Track -> List { frame : Int, value : PropertyValue, spline : Maybe Spline }
plan requireUnitY duration track =
    case planTrack requireUnitY duration track of
        Native keys ->
            keys

        BakedPlan samples _ ->
            List.map (\s -> { frame = s.frame, value = s.value, spline = Just linearSpline }) samples
