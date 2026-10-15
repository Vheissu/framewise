module TimeModelTest exposing (suite)

import Domain.Fps as Fps
import Domain.Loop as Loop
import Domain.Scene exposing (PlaybackMode(..))
import Expect
import Test exposing (..)


near : Float -> Float -> Expect.Expectation
near expected actual =
    Expect.within (Expect.Absolute 1.0e-9) expected actual


suite : Test
suite =
    describe "time model"
        [ describe "Fps"
            [ test "frames to seconds for integer rates" <|
                \_ -> Expect.within (Expect.Absolute 1.0e-9) 2 (Fps.framesToSeconds (Fps.fps 30 1) 60)
            , test "29.97 is exact as a rational" <|
                \_ ->
                    let
                        r =
                            Fps.fps 30000 1001
                    in
                    Expect.all
                        [ \_ -> Expect.within (Expect.Absolute 1.0e-12) (1001 / 1000) (Fps.framesToSeconds r 30)
                        , \_ -> Expect.equal "29.97" (Fps.toLabel r)
                        , \_ -> Expect.within (Expect.Absolute 1.0e-9) 30 (Fps.secondsToFrames r 1.001)
                        ]
                        ()
            , test "timecode for 24, 25, 30 and 60 fps" <|
                \_ ->
                    Expect.all
                        [ \_ -> Expect.equal "00:00:01:00" (Fps.toTimecode (Fps.fps 24 1) 24)
                        , \_ -> Expect.equal "00:00:00:23" (Fps.toTimecode (Fps.fps 24 1) 23)
                        , \_ -> Expect.equal "00:01:00:05" (Fps.toTimecode (Fps.fps 25 1) 1505)
                        , \_ -> Expect.equal "00:00:02:00" (Fps.toTimecode (Fps.fps 30 1) 60)
                        , \_ -> Expect.equal "01:00:00:00" (Fps.toTimecode (Fps.fps 60 1) 216000)
                        ]
                        ()
            , test "timecode for a fractional rate is non-drop-frame" <|
                \_ ->
                    -- after 30000 frames at 30000/1001 fps, 1001 seconds have elapsed
                    Expect.equal "00:16:41:00" (Fps.toTimecode (Fps.fps 30000 1001) 30000)
            , test "validity bounds" <|
                \_ ->
                    Expect.all
                        [ \_ -> Expect.equal True (Fps.isValid (Fps.fps 240 1))
                        , \_ -> Expect.equal False (Fps.isValid (Fps.fps 241 1))
                        , \_ -> Expect.equal True (Fps.isValid (Fps.fps 1 1))
                        ]
                        ()
            , test "equal compares rationals" <|
                \_ -> Expect.equal True (Fps.equal (Fps.fps 30 1) (Fps.fps 60 2))
            ]
        , describe "Loop.mapFrame"
            [ test "once clamps to the endpoint" <|
                \_ -> Expect.all [ \_ -> Expect.equal 60 (Loop.mapFrame PlayOnce 60 75), \_ -> Expect.equal 0 (Loop.mapFrame PlayOnce 60 -3) ] ()
            , test "repeat wraps and never reaches the endpoint" <|
                \_ -> Expect.all [ \_ -> near 0 (Loop.mapFrame Repeat 60 60), \_ -> near 15 (Loop.mapFrame Repeat 60 75), \_ -> near 59.5 (Loop.mapFrame Repeat 60 119.5) ] ()
            , test "repeat handles negative (reverse) time with a true modulo" <|
                \_ -> near 50 (Loop.mapFrame Repeat 60 -10)
            , test "ping-pong mirrors and reaches the endpoint once per cycle" <|
                \_ ->
                    Expect.all
                        [ \_ -> near 60 (Loop.mapFrame PingPong 60 60)
                        , \_ -> near 45 (Loop.mapFrame PingPong 60 75)
                        , \_ -> near 0 (Loop.mapFrame PingPong 60 120)
                        , \_ -> near 10 (Loop.mapFrame PingPong 60 130)
                        , \_ -> near 10 (Loop.mapFrame PingPong 60 -10)
                        ]
                        ()
            ]
        ]
