module EasingTest exposing (suite)

import Domain.Easing as Easing exposing (Easing(..), Preset(..))
import Expect
import Fuzz
import Test exposing (..)


close : Float -> Float -> Expect.Expectation
close =
    Expect.within (Expect.Absolute 1.0e-6)


suite : Test
suite =
    describe "Domain.Easing"
        [ test "every easing is exactly 0 at 0 and 1 at 1" <|
            \_ ->
                let
                    easings =
                        [ Hold, Linear, CubicBezier 0.42 0 0.58 1, CubicBezier 0.3 -0.5 0.7 1.5, Spring Easing.defaultSpring ]
                            ++ List.map Preset Easing.allPresets
                in
                Expect.all
                    (List.concatMap (\e -> [ \_ -> close 0 (Easing.evaluate e 0), \_ -> close 1 (Easing.evaluate e 1) ]) easings)
                    ()
        , test "hold steps only at the end" <|
            \_ -> Expect.all [ \_ -> close 0 (Easing.evaluate Hold 0.999), \_ -> close 1 (Easing.evaluate Hold 1) ] ()
        , test "linear is identity" <|
            \_ -> close 0.37 (Easing.evaluate Linear 0.37)
        , test "ease-in-out is symmetric around the midpoint" <|
            \_ ->
                let
                    e =
                        Preset EaseInOut
                in
                Expect.all
                    [ \_ -> close 0.5 (Easing.evaluate e 0.5)
                    , \_ -> close (1 - Easing.evaluate e 0.25) (Easing.evaluate e 0.75)
                    ]
                    ()
        , test "ease-in starts slow" <|
            \_ -> Expect.lessThan 0.25 (Easing.evaluate (Preset EaseIn) 0.25)
        , test "cubic bezier solves x with Newton iterations to tolerance" <|
            \_ ->
                let
                    t =
                        Easing.solveBezierX 0.42 0.58 0.3
                in
                -- B_x(t) must equal 0.3
                close 0.3 (3 * (1 - t) * (1 - t) * t * 0.42 + 3 * (1 - t) * t * t * 0.58 + t * t * t)
        , test "degenerate bezier handles still return monotone values" <|
            \_ ->
                let
                    e =
                        CubicBezier 0 0 0 0

                    samples =
                        List.map (\i -> Easing.evaluate e (toFloat i / 10)) (List.range 0 10)
                in
                Expect.equal samples (List.sort samples)
        , test "clamps input outside [0,1]" <|
            \_ -> Expect.all [ \_ -> close 0 (Easing.evaluate Linear -2), \_ -> close 1 (Easing.evaluate Linear 7) ] ()
        , test "spring is deterministic and overshoots with low damping" <|
            \_ ->
                let
                    s =
                        Spring { mass = 1, stiffness = 200, damping = 3, velocity = 0 }

                    a =
                        Easing.evaluate s 0.4

                    b =
                        Easing.evaluate s 0.4
                in
                Expect.all [ \_ -> close a b, \_ -> Expect.greaterThan 1 (List.maximum (List.map (\i -> Easing.evaluate s (toFloat i / 50)) (List.range 1 49)) |> Maybe.withDefault 0) ] ()
        , test "back-out overshoots past the target" <|
            \_ -> Expect.greaterThan 1 (Easing.evaluate (Preset BackOut) 0.7)
        , test "bounce-out ends exactly at 1 and bounce-in starts at 0" <|
            \_ -> Expect.all [ \_ -> close 1 (Easing.evaluate (Preset BounceOut) 1), \_ -> close 0 (Easing.evaluate (Preset BounceIn) 0) ] ()
        , test "preset codes round trip" <|
            \_ -> Expect.equal (List.map Just Easing.allPresets) (List.map (Easing.presetToCode >> Easing.presetFromCode) Easing.allPresets)
        , fuzz (Fuzz.floatRange 0 1) "cubic ease is monotone non-decreasing" <|
            \u ->
                let
                    e =
                        Preset Ease

                    u2 =
                        min 1 (u + 0.05)
                in
                Expect.atMost (Easing.evaluate e u2 + 1.0e-9) (Easing.evaluate e u)
        ]
