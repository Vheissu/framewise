module Domain.Color exposing
    ( Hsl
    , Rgba
    , black
    , clamp01
    , fromHex
    , fromHsl
    , interpolate
    , isValid
    , rgba
    , toCss
    , toHex
    , toHsl
    , transparent
    , white
    )

{-| Colours are stored as RGBA with channels in `[0,1]` and explicit alpha.
Interpolation is straight (non-premultiplied) sRGB component interpolation,
which matches how SVG `<animate>` interpolates `fill`/`stroke` colours in
browsers and keeps editor, exports and player consistent.
-}


type alias Rgba =
    { r : Float, g : Float, b : Float, a : Float }


type alias Hsl =
    { h : Float, s : Float, l : Float }


rgba : Float -> Float -> Float -> Float -> Rgba
rgba r g b a =
    { r = clamp01 r, g = clamp01 g, b = clamp01 b, a = clamp01 a }


black : Rgba
black =
    rgba 0 0 0 1


white : Rgba
white =
    rgba 1 1 1 1


transparent : Rgba
transparent =
    rgba 0 0 0 0


clamp01 : Float -> Float
clamp01 v =
    if isNaN v then
        0

    else
        clamp 0 1 v


isValid : Rgba -> Bool
isValid c =
    List.all (\v -> not (isNaN v || isInfinite v) && v >= 0 && v <= 1) [ c.r, c.g, c.b, c.a ]


interpolate : Rgba -> Rgba -> Float -> Rgba
interpolate c1 c2 t =
    { r = clamp01 (c1.r + (c2.r - c1.r) * t)
    , g = clamp01 (c1.g + (c2.g - c1.g) * t)
    , b = clamp01 (c1.b + (c2.b - c1.b) * t)
    , a = clamp01 (c1.a + (c2.a - c1.a) * t)
    }


channelTo255 : Float -> Int
channelTo255 v =
    round (clamp01 v * 255)


{-| `#rrggbb` when opaque, otherwise `#rrggbbaa`.
-}
toHex : Rgba -> String
toHex c =
    let
        base =
            "#" ++ hex2 c.r ++ hex2 c.g ++ hex2 c.b
    in
    if channelTo255 c.a == 255 then
        base

    else
        base ++ hex2 c.a


hex2 : Float -> String
hex2 v =
    let
        n =
            channelTo255 v

        digit d =
            String.slice d (d + 1) "0123456789abcdef"
    in
    digit (n // 16) ++ digit (modBy 16 n)


{-| Accepts `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, with or without `#`.
-}
fromHex : String -> Maybe Rgba
fromHex raw =
    let
        s =
            String.toLower (String.trim raw)

        body =
            if String.startsWith "#" s then
                String.dropLeft 1 s

            else
                s

        chars =
            String.toList body

        expand =
            List.concatMap (\c -> [ c, c ])
    in
    case List.length chars of
        3 ->
            parsePairs (expand chars ++ [ 'f', 'f' ])

        4 ->
            parsePairs (expand chars)

        6 ->
            parsePairs (chars ++ [ 'f', 'f' ])

        8 ->
            parsePairs chars

        _ ->
            Nothing


parsePairs : List Char -> Maybe Rgba
parsePairs chars =
    case chars of
        [ r1, r2, g1, g2, b1, b2, a1, a2 ] ->
            Maybe.map4
                (\r g b a -> rgba (toFloat r / 255) (toFloat g / 255) (toFloat b / 255) (toFloat a / 255))
                (hexByte r1 r2)
                (hexByte g1 g2)
                (hexByte b1 b2)
                (hexByte a1 a2)

        _ ->
            Nothing


hexByte : Char -> Char -> Maybe Int
hexByte hi lo =
    Maybe.map2 (\h l -> h * 16 + l) (hexDigit hi) (hexDigit lo)


hexDigit : Char -> Maybe Int
hexDigit c =
    let
        code =
            Char.toCode c
    in
    if code >= 48 && code <= 57 then
        Just (code - 48)

    else if code >= 97 && code <= 102 then
        Just (code - 87)

    else
        Nothing


toCss : Rgba -> String
toCss c =
    "rgba("
        ++ String.fromInt (channelTo255 c.r)
        ++ ","
        ++ String.fromInt (channelTo255 c.g)
        ++ ","
        ++ String.fromInt (channelTo255 c.b)
        ++ ","
        ++ String.fromFloat (toFloat (round (c.a * 1000)) / 1000)
        ++ ")"


toHsl : Rgba -> Hsl
toHsl c =
    let
        mx =
            max c.r (max c.g c.b)

        mn =
            min c.r (min c.g c.b)

        l =
            (mx + mn) / 2

        d =
            mx - mn

        s =
            if d == 0 then
                0

            else
                d / (1 - abs (2 * l - 1))

        h =
            if d == 0 then
                0

            else if mx == c.r then
                60 * fmod ((c.g - c.b) / d) 6

            else if mx == c.g then
                60 * ((c.b - c.r) / d + 2)

            else
                60 * ((c.r - c.g) / d + 4)
    in
    { h = h, s = clamp01 s, l = clamp01 l }


fmod : Float -> Float -> Float
fmod a b =
    a - b * toFloat (floor (a / b))


fromHsl : Hsl -> Float -> Rgba
fromHsl hsl alpha =
    let
        h =
            fmod hsl.h 360

        c =
            (1 - abs (2 * hsl.l - 1)) * hsl.s

        x =
            c * (1 - abs (fmod (h / 60) 2 - 1))

        m =
            hsl.l - c / 2

        ( r1, g1, b1 ) =
            if h < 60 then
                ( c, x, 0 )

            else if h < 120 then
                ( x, c, 0 )

            else if h < 180 then
                ( 0, c, x )

            else if h < 240 then
                ( 0, x, c )

            else if h < 300 then
                ( x, 0, c )

            else
                ( c, 0, x )
    in
    rgba (r1 + m) (g1 + m) (b1 + m) alpha
