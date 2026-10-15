module KeyframeTest exposing (suite)

import Domain.Easing exposing (Easing(..), Preset(..))
import Domain.Interpolation as Interpolation
import Domain.Keyframe as Keyframe
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Expect
import Test exposing (..)


key : String -> Int -> Float -> Easing -> Keyframe.Keyframe
key id frame v e =
    { id = id, frame = frame, value = Scalar v, easing = e }


track : List Keyframe.Keyframe -> Keyframe.Track
track keys =
    List.foldl Keyframe.insert (Keyframe.newTrack "t" "n" Opacity) keys


suite : Test
suite =
    describe "keyframes and interpolation"
        [ test "insert keeps keys sorted and overwrites same-frame keys" <|
            \_ ->
                let
                    t =
                        track [ key "a" 10 1 Linear, key "b" 0 0 Linear, key "c" 10 5 Linear ]
                in
                Expect.equal [ ( 0, "b" ), ( 10, "c" ) ] (List.map (\k -> ( k.frame, k.id )) t.keyframes)
        , test "setFrame moves a key and resolves collisions" <|
            \_ ->
                let
                    t =
                        track [ key "a" 0 0 Linear, key "b" 10 1 Linear, key "c" 20 2 Linear ]
                            |> Keyframe.setFrame "c" 10
                in
                Expect.equal [ "a", "c" ] (List.map .id t.keyframes)
        , test "shift clamps at frame 0" <|
            \_ ->
                let
                    t =
                        track [ key "a" 3 0 Linear, key "b" 10 1 Linear ] |> Keyframe.shift [ "a", "b" ] -5
                in
                Expect.equal [ 0, 5 ] (Keyframe.frames t)
        , test "scale timing around an anchor" <|
            \_ ->
                let
                    t =
                        track [ key "a" 10 0 Linear, key "b" 20 1 Linear, key "c" 30 2 Linear ] |> Keyframe.scale [ "a", "b", "c" ] 10 2
                in
                Expect.equal [ 10, 30, 50 ] (Keyframe.frames t)
        , test "segmentAt finds the surrounding keys" <|
            \_ ->
                let
                    t =
                        track [ key "a" 0 0 Linear, key "b" 10 1 Linear, key "c" 20 2 Linear ]

                    seg =
                        Keyframe.segmentAt 12 t
                in
                Expect.equal ( Just "b", Just "c" ) ( Maybe.map .id seg.before, Maybe.map .id seg.after )
        , test "linear interpolation at the midpoint" <|
            \_ -> Expect.equal (Just (Scalar 5)) (Interpolation.evaluateTrack 5 (track [ key "a" 0 0 Linear, key "b" 10 10 Linear ]))
        , test "hold keeps the earlier value until the next key" <|
            \_ ->
                let
                    t =
                        track [ key "a" 0 0 Hold, key "b" 10 10 Linear ]
                in
                Expect.all [ \_ -> Expect.equal (Just (Scalar 0)) (Interpolation.evaluateTrack 9.99 t), \_ -> Expect.equal (Just (Scalar 10)) (Interpolation.evaluateTrack 10 t) ] ()
        , test "before the first key and after the last key hold" <|
            \_ ->
                let
                    t =
                        track [ key "a" 10 3 Linear, key "b" 20 7 Linear ]
                in
                Expect.all [ \_ -> Expect.equal (Just (Scalar 3)) (Interpolation.evaluateTrack 0 t), \_ -> Expect.equal (Just (Scalar 7)) (Interpolation.evaluateTrack 99 t) ] ()
        , test "a single key is constant and no keys is Nothing" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal (Just (Scalar 4)) (Interpolation.evaluateTrack 50 (track [ key "a" 10 4 Linear ]))
                    , \_ -> Expect.equal Nothing (Interpolation.evaluateTrack 0 (track []))
                    ]
                    ()
        , test "ease-in-out midpoint is exactly halfway" <|
            \_ -> Expect.equal (Just (Scalar 50)) (Interpolation.evaluateTrack 5 (track [ key "a" 0 0 (Preset EaseInOut), key "b" 10 100 Linear ]))
        , test "colours interpolate per channel including alpha" <|
            \_ ->
                let
                    c =
                        Interpolation.interpolateValue (ColorValue { r = 0, g = 0, b = 1, a = 0 }) (ColorValue { r = 1, g = 0, b = 0, a = 1 }) 0.5
                in
                Expect.equal (ColorValue { r = 0.5, g = 0, b = 0.5, a = 0.5 }) c
        , test "mismatched value kinds step at the end of the segment" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal (Scalar 1) (Interpolation.interpolateValue (Scalar 1) (Angle 2) 0.9)
                    , \_ -> Expect.equal (Angle 2) (Interpolation.interpolateValue (Scalar 1) (Angle 2) 1)
                    ]
                    ()
        , test "discrete properties never interpolate" <|
            \_ ->
                let
                    t =
                        List.foldl Keyframe.insert (Keyframe.newTrack "t" "n" Visible) [ { id = "a", frame = 0, value = BoolValue True, easing = Linear }, { id = "b", frame = 10, value = BoolValue False, easing = Linear } ]
                in
                Expect.all [ \_ -> Expect.equal (Just (BoolValue True)) (Interpolation.evaluateTrack 9.9 t), \_ -> Expect.equal (Just (BoolValue False)) (Interpolation.evaluateTrack 10 t) ] ()
        ]
