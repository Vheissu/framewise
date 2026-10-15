module Domain.Paint exposing
    ( Gradient
    , GradientKind(..)
    , GradientStop
    , LineCap(..)
    , LineJoin(..)
    , Paint(..)
    , Stroke
    , capFromCode
    , capToCode
    , defaultStroke
    , isValid
    , joinFromCode
    , joinToCode
    , noStroke
    , paintColor
    , setPaintColor
    )

import Domain.Color as Color exposing (Rgba)
import Domain.Vec2 exposing (Vec2)


type Paint
    = NoPaint
    | Solid Rgba
    | GradientPaint Gradient


type GradientKind
    = LinearGradient { start : Vec2, end : Vec2 }
    | RadialGradient { center : Vec2, radius : Float }


type alias GradientStop =
    { offset : Float, color : Rgba }


type alias Gradient =
    { kind : GradientKind
    , stops : List GradientStop
    }


type LineCap
    = CapButt
    | CapRound
    | CapSquare


type LineJoin
    = JoinMiter
    | JoinRound
    | JoinBevel


type alias Stroke =
    { paint : Paint
    , width : Float
    , cap : LineCap
    , join : LineJoin
    , miterLimit : Float
    , dashArray : List Float
    , dashOffset : Float
    }


defaultStroke : Stroke
defaultStroke =
    { paint = NoPaint
    , width = 2
    , cap = CapButt
    , join = JoinMiter
    , miterLimit = 4
    , dashArray = []
    , dashOffset = 0
    }


noStroke : Stroke
noStroke =
    defaultStroke


{-| The solid colour of a paint, if any. Gradients report their first stop so
colour controls have something sensible to show.
-}
paintColor : Paint -> Maybe Rgba
paintColor p =
    case p of
        NoPaint ->
            Nothing

        Solid c ->
            Just c

        GradientPaint g ->
            List.head g.stops |> Maybe.map .color


setPaintColor : Rgba -> Paint -> Paint
setPaintColor c p =
    case p of
        GradientPaint _ ->
            p

        _ ->
            Solid c


isValid : Paint -> Bool
isValid p =
    case p of
        NoPaint ->
            True

        Solid c ->
            Color.isValid c

        GradientPaint g ->
            not (List.isEmpty g.stops)
                && List.all (\s -> s.offset >= 0 && s.offset <= 1 && Color.isValid s.color) g.stops


capToCode : LineCap -> String
capToCode c =
    case c of
        CapButt ->
            "butt"

        CapRound ->
            "round"

        CapSquare ->
            "square"


capFromCode : String -> Maybe LineCap
capFromCode s =
    case s of
        "butt" ->
            Just CapButt

        "round" ->
            Just CapRound

        "square" ->
            Just CapSquare

        _ ->
            Nothing


joinToCode : LineJoin -> String
joinToCode j =
    case j of
        JoinMiter ->
            "miter"

        JoinRound ->
            "round"

        JoinBevel ->
            "bevel"


joinFromCode : String -> Maybe LineJoin
joinFromCode s =
    case s of
        "miter" ->
            Just JoinMiter

        "round" ->
            Just JoinRound

        "bevel" ->
            Just JoinBevel

        _ ->
            Nothing
