module Domain.Fps exposing
    ( Fps
    , equal
    , fps
    , framesToSeconds
    , isValid
    , presets
    , secondsToFrames
    , toFloat
    , toLabel
    , toTimecode
    )

{-| Frame rates are exact rationals so that 30000/1001 (29.97) is representable.
Timecode is non-drop-frame: `HH:MM:SS:FF`, where FF is the whole frame index
within the second computed from exact rational arithmetic.
-}


type alias Fps =
    { numerator : Int, denominator : Int }


fps : Int -> Int -> Fps
fps n d =
    { numerator = max 1 n, denominator = max 1 d }


isValid : Fps -> Bool
isValid r =
    r.numerator > 0 && r.denominator > 0 && r.numerator <= 240 * r.denominator


equal : Fps -> Fps -> Bool
equal a b =
    a.numerator * b.denominator == b.numerator * a.denominator


toFloat : Fps -> Float
toFloat r =
    Basics.toFloat r.numerator / Basics.toFloat r.denominator


toLabel : Fps -> String
toLabel r =
    if r.denominator == 1 then
        String.fromInt r.numerator

    else
        let
            v =
                toFloat r

            rounded =
                Basics.toFloat (round (v * 100)) / 100
        in
        String.fromFloat rounded


presets : List ( String, Fps )
presets =
    [ ( "12", fps 12 1 )
    , ( "24", fps 24 1 )
    , ( "25", fps 25 1 )
    , ( "29.97", fps 30000 1001 )
    , ( "30", fps 30 1 )
    , ( "50", fps 50 1 )
    , ( "60", fps 60 1 )
    ]


{-| `frames * denominator / numerator`.
-}
framesToSeconds : Fps -> Float -> Float
framesToSeconds r frames =
    frames * Basics.toFloat r.denominator / Basics.toFloat r.numerator


{-| `seconds * numerator / denominator`.
-}
secondsToFrames : Fps -> Float -> Float
secondsToFrames r seconds =
    seconds * Basics.toFloat r.numerator / Basics.toFloat r.denominator


{-| Non-drop-frame timecode for an integer frame index.
-}
toTimecode : Fps -> Int -> String
toTimecode r frame =
    let
        -- whole seconds = floor(frame * den / num)
        totalSeconds =
            (frame * r.denominator) // r.numerator

        -- frames into the current second
        framesIntoSecond =
            frame - ((totalSeconds * r.numerator) // r.denominator)

        -- For fractional rates the frames-in-second count can hit ceil(fps);
        -- compute remainder exactly and clamp display.
        ff =
            max 0 framesIntoSecond

        hh =
            totalSeconds // 3600

        mm =
            modBy 60 (totalSeconds // 60)

        ss =
            modBy 60 totalSeconds

        pad2 n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    pad2 hh ++ ":" ++ pad2 mm ++ ":" ++ pad2 ss ++ ":" ++ pad2 ff
