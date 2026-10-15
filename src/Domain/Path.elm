module Domain.Path exposing
    ( Anchor
    , ArcTable
    , PathGeometry
    , Segment(..)
    , Subpath
    , anchorCount
    , anchors
    , arcTable
    , bounds
    , empty
    , fromPolyline
    , interpolate
    , isCompatible
    , isFinite
    , moveAnchor
    , parse
    , pointAtLength
    , segmentCount
    , serialize
    , setAnchorHandles
    , toggleClosed
    , totalLength
    , transformGeometry
    )

{-| Editable path geometry. SVG path data is normalised into subpaths made of
line and cubic Bézier segments. Quadratics, smooth shorthands, and arcs are
converted on parse; the conversion is recorded by the importer as an
"approximated" diagnostic for arcs.
-}

import Domain.Matrix as Matrix exposing (Matrix)
import Domain.Vec2 as Vec2 exposing (Vec2)


type Segment
    = LineTo Vec2
    | CubicTo Vec2 Vec2 Vec2


type alias Subpath =
    { start : Vec2
    , segments : List Segment
    , closed : Bool
    }


type alias PathGeometry =
    { subpaths : List Subpath }


type alias Anchor =
    { subpath : Int
    , index : Int
    , point : Vec2
    , handleIn : Maybe Vec2
    , handleOut : Maybe Vec2
    }


empty : PathGeometry
empty =
    { subpaths = [] }


fromPolyline : List Vec2 -> Bool -> PathGeometry
fromPolyline points closed =
    case points of
        [] ->
            empty

        first :: rest ->
            { subpaths = [ { start = first, segments = List.map LineTo rest, closed = closed } ] }


segmentCount : PathGeometry -> Int
segmentCount g =
    List.sum (List.map (\s -> List.length s.segments) g.subpaths)


anchorCount : PathGeometry -> Int
anchorCount g =
    List.sum (List.map (\s -> 1 + List.length s.segments) g.subpaths)


isFinite : PathGeometry -> Bool
isFinite g =
    List.all
        (\s ->
            Vec2.isFinite s.start
                && List.all
                    (\seg ->
                        case seg of
                            LineTo p ->
                                Vec2.isFinite p

                            CubicTo a b c ->
                                Vec2.isFinite a && Vec2.isFinite b && Vec2.isFinite c
                    )
                    s.segments
        )
        g.subpaths



-- SERIALISATION


serialize : PathGeometry -> String
serialize g =
    String.join " " (List.map serializeSubpath g.subpaths)


serializeSubpath : Subpath -> String
serializeSubpath s =
    let
        segs =
            List.map
                (\seg ->
                    case seg of
                        LineTo p ->
                            "L" ++ pt p

                        CubicTo a b c ->
                            "C" ++ pt a ++ " " ++ pt b ++ " " ++ pt c
                )
                s.segments
    in
    String.join " " (("M" ++ pt s.start) :: segs)
        ++ (if s.closed then
                " Z"

            else
                ""
           )


pt : Vec2 -> String
pt p =
    num p.x ++ " " ++ num p.y


num : Float -> String
num v =
    let
        r =
            toFloat (round (v * 1000)) / 1000
    in
    if r == toFloat (round r) then
        String.fromInt (round r)

    else
        String.fromFloat r



-- PARSING


type alias ParseState =
    { subpaths : List Subpath
    , current : Maybe Subpath
    , pos : Vec2
    , subpathStart : Vec2
    , lastControl : Maybe Vec2
    , lastQuadControl : Maybe Vec2
    , lastCommand : Char
    }


{-| Parse SVG path data. Returns Err with a short reason on malformed input.
-}
parse : String -> Result String PathGeometry
parse input =
    case tokenize input of
        Err e ->
            Err e

        Ok tokens ->
            run tokens
                { subpaths = []
                , current = Nothing
                , pos = Vec2.zero
                , subpathStart = Vec2.zero
                , lastControl = Nothing
                , lastQuadControl = Nothing
                , lastCommand = 'M'
                }
                |> Result.map finish


type Token
    = Cmd Char
    | Num Float


tokenize : String -> Result String (List Token)
tokenize s =
    tokenizeHelp (String.toList s) [] []


tokenizeHelp : List Char -> List Char -> List Token -> Result String (List Token)
tokenizeHelp chars numBuf acc =
    let
        flush () =
            if List.isEmpty numBuf then
                Ok acc

            else
                case String.toFloat (String.fromList (List.reverse numBuf)) of
                    Just v ->
                        Ok (Num v :: acc)

                    Nothing ->
                        Err ("Invalid number: " ++ String.fromList (List.reverse numBuf))
    in
    case chars of
        [] ->
            flush () |> Result.map List.reverse

        c :: rest ->
            if Char.isAlpha c then
                if c == 'e' || c == 'E' then
                    -- exponent inside a number
                    if List.isEmpty numBuf then
                        Err "Unexpected exponent"

                    else
                        tokenizeHelp rest (c :: numBuf) acc

                else
                    case flush () of
                        Ok acc2 ->
                            tokenizeHelp rest [] (Cmd c :: acc2)

                        Err e ->
                            Err e

            else if Char.isDigit c || c == '.' then
                -- a second '.' starts a new number (e.g. "1.5.5")
                if c == '.' && List.member '.' numBuf && not (List.member 'e' numBuf) then
                    case flush () of
                        Ok acc2 ->
                            tokenizeHelp rest [ c ] acc2

                        Err e ->
                            Err e

                else
                    tokenizeHelp rest (c :: numBuf) acc

            else if c == '-' || c == '+' then
                case numBuf of
                    [] ->
                        tokenizeHelp rest [ c ] acc

                    prev :: _ ->
                        if prev == 'e' || prev == 'E' then
                            tokenizeHelp rest (c :: numBuf) acc

                        else
                            case flush () of
                                Ok acc2 ->
                                    tokenizeHelp rest [ c ] acc2

                                Err e ->
                                    Err e

            else if c == ' ' || c == ',' || c == '\n' || c == '\t' || c == '\u{000D}' then
                case flush () of
                    Ok acc2 ->
                        tokenizeHelp rest [] acc2

                    Err e ->
                        Err e

            else
                Err ("Unexpected character: " ++ String.fromChar c)


run : List Token -> ParseState -> Result String ParseState
run tokens state =
    case tokens of
        [] ->
            Ok state

        (Cmd c) :: rest ->
            command c rest state

        (Num _) :: _ ->
            -- implicit repeat of last command
            let
                c =
                    state.lastCommand

                repeatCmd =
                    if c == 'M' then
                        'L'

                    else if c == 'm' then
                        'l'

                    else
                        c
            in
            if c == 'Z' || c == 'z' then
                Err "Numbers after Z"

            else
                command repeatCmd tokens state


takeNums : Int -> List Token -> Maybe ( List Float, List Token )
takeNums n tokens =
    takeNumsHelp n tokens []


takeNumsHelp : Int -> List Token -> List Float -> Maybe ( List Float, List Token )
takeNumsHelp n tokens acc =
    if n == 0 then
        Just ( List.reverse acc, tokens )

    else
        case tokens of
            (Num v) :: rest ->
                takeNumsHelp (n - 1) rest (v :: acc)

            _ ->
                Nothing


command : Char -> List Token -> ParseState -> Result String ParseState
command c tokens state =
    let
        rel p =
            if Char.isLower c then
                Vec2.add state.pos p

            else
                p

        st =
            { state | lastCommand = c }

        next newState rest =
            run rest newState
    in
    case Char.toUpper c of
        'M' ->
            case takeNums 2 tokens of
                Just ( [ x, y ], rest ) ->
                    let
                        p =
                            rel { x = x, y = y }

                        closedState =
                            closeCurrent st
                    in
                    next
                        { closedState
                            | current = Just { start = p, segments = [], closed = False }
                            , pos = p
                            , subpathStart = p
                            , lastControl = Nothing
                            , lastQuadControl = Nothing
                        }
                        rest

                _ ->
                    Err "M needs 2 numbers"

        'L' ->
            case takeNums 2 tokens of
                Just ( [ x, y ], rest ) ->
                    lineTo (rel { x = x, y = y }) st rest

                _ ->
                    Err "L needs 2 numbers"

        'H' ->
            case takeNums 1 tokens of
                Just ( [ x ], rest ) ->
                    let
                        p =
                            if Char.isLower c then
                                { x = state.pos.x + x, y = state.pos.y }

                            else
                                { x = x, y = state.pos.y }
                    in
                    lineTo p st rest

                _ ->
                    Err "H needs 1 number"

        'V' ->
            case takeNums 1 tokens of
                Just ( [ y ], rest ) ->
                    let
                        p =
                            if Char.isLower c then
                                { x = state.pos.x, y = state.pos.y + y }

                            else
                                { x = state.pos.x, y = y }
                    in
                    lineTo p st rest

                _ ->
                    Err "V needs 1 number"

        'C' ->
            case takeNums 6 tokens of
                Just ( [ x1, y1, x2, y2, x, y ], rest ) ->
                    cubicTo (rel { x = x1, y = y1 }) (rel { x = x2, y = y2 }) (rel { x = x, y = y }) st rest

                _ ->
                    Err "C needs 6 numbers"

        'S' ->
            case takeNums 4 tokens of
                Just ( [ x2, y2, x, y ], rest ) ->
                    let
                        c1 =
                            case state.lastControl of
                                Just lc ->
                                    Vec2.sub (Vec2.scale 2 state.pos) lc

                                Nothing ->
                                    state.pos
                    in
                    cubicTo c1 (rel { x = x2, y = y2 }) (rel { x = x, y = y }) st rest

                _ ->
                    Err "S needs 4 numbers"

        'Q' ->
            case takeNums 4 tokens of
                Just ( [ qx, qy, x, y ], rest ) ->
                    quadTo (rel { x = qx, y = qy }) (rel { x = x, y = y }) st rest

                _ ->
                    Err "Q needs 4 numbers"

        'T' ->
            case takeNums 2 tokens of
                Just ( [ x, y ], rest ) ->
                    let
                        q =
                            case state.lastQuadControl of
                                Just lq ->
                                    Vec2.sub (Vec2.scale 2 state.pos) lq

                                Nothing ->
                                    state.pos
                    in
                    quadTo q (rel { x = x, y = y }) st rest

                _ ->
                    Err "T needs 2 numbers"

        'A' ->
            case takeNums 7 tokens of
                Just ( [ rx, ry, rot, large, sweep, x, y ], rest ) ->
                    let
                        end =
                            rel { x = x, y = y }

                        cubics =
                            arcToCubics state.pos rx ry rot (large /= 0) (sweep /= 0) end

                        newState =
                            List.foldl
                                (\( c1, c2, p ) s -> appendSegment (CubicTo c1 c2 p) p s)
                                st
                                cubics
                    in
                    next { newState | lastControl = Nothing, lastQuadControl = Nothing } rest

                _ ->
                    Err "A needs 7 numbers"

        'Z' ->
            let
                closed =
                    closeCurrentExplicit st
            in
            next { closed | pos = state.subpathStart, lastControl = Nothing, lastQuadControl = Nothing } tokens

        _ ->
            Err ("Unknown command: " ++ String.fromChar c)


lineTo : Vec2 -> ParseState -> List Token -> Result String ParseState
lineTo p st rest =
    run rest ({ st | lastControl = Nothing, lastQuadControl = Nothing } |> appendSegment (LineTo p) p)


cubicTo : Vec2 -> Vec2 -> Vec2 -> ParseState -> List Token -> Result String ParseState
cubicTo c1 c2 p st rest =
    let
        s =
            appendSegment (CubicTo c1 c2 p) p st
    in
    run rest { s | lastControl = Just c2, lastQuadControl = Nothing }


quadTo : Vec2 -> Vec2 -> ParseState -> List Token -> Result String ParseState
quadTo q p st rest =
    let
        p0 =
            st.pos

        c1 =
            Vec2.add p0 (Vec2.scale (2 / 3) (Vec2.sub q p0))

        c2 =
            Vec2.add p (Vec2.scale (2 / 3) (Vec2.sub q p))

        s =
            appendSegment (CubicTo c1 c2 p) p st
    in
    run rest { s | lastQuadControl = Just q, lastControl = Nothing }


appendSegment : Segment -> Vec2 -> ParseState -> ParseState
appendSegment seg newPos st =
    case st.current of
        Just cur ->
            { st | current = Just { cur | segments = cur.segments ++ [ seg ] }, pos = newPos }

        Nothing ->
            -- implicit subpath start at current position
            { st
                | current = Just { start = st.pos, segments = [ seg ], closed = False }
                , subpathStart = st.pos
                , pos = newPos
            }


closeCurrent : ParseState -> ParseState
closeCurrent st =
    case st.current of
        Just cur ->
            { st | subpaths = st.subpaths ++ [ cur ], current = Nothing }

        Nothing ->
            st


closeCurrentExplicit : ParseState -> ParseState
closeCurrentExplicit st =
    case st.current of
        Just cur ->
            { st | subpaths = st.subpaths ++ [ { cur | closed = True } ], current = Nothing }

        Nothing ->
            st


finish : ParseState -> PathGeometry
finish st =
    { subpaths = (closeCurrent st).subpaths }


{-| Convert an SVG elliptical arc into cubic Bézier segments (max 90° each).
Follows the SVG implementation notes (F.6.5 and F.6.6).
-}
arcToCubics : Vec2 -> Float -> Float -> Float -> Bool -> Bool -> Vec2 -> List ( Vec2, Vec2, Vec2 )
arcToCubics p0 rxIn ryIn rotDeg largeArc sweep p1 =
    if (p0.x == p1.x && p0.y == p1.y) || rxIn == 0 || ryIn == 0 then
        if rxIn == 0 || ryIn == 0 then
            [ ( p0, p1, p1 ) ]

        else
            []

    else
        let
            phi =
                rotDeg * pi / 180

            cosPhi =
                cos phi

            sinPhi =
                sin phi

            dx2 =
                (p0.x - p1.x) / 2

            dy2 =
                (p0.y - p1.y) / 2

            x1p =
                cosPhi * dx2 + sinPhi * dy2

            y1p =
                -sinPhi * dx2 + cosPhi * dy2

            rx0 =
                abs rxIn

            ry0 =
                abs ryIn

            lambda =
                (x1p * x1p) / (rx0 * rx0) + (y1p * y1p) / (ry0 * ry0)

            ( rx, ry ) =
                if lambda > 1 then
                    ( rx0 * sqrt lambda, ry0 * sqrt lambda )

                else
                    ( rx0, ry0 )

            sign =
                if largeArc == sweep then
                    -1

                else
                    1

            numer =
                rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p

            denom =
                rx * rx * y1p * y1p + ry * ry * x1p * x1p

            coef =
                sign * sqrt (max 0 (numer / denom))

            cxp =
                coef * (rx * y1p / ry)

            cyp =
                coef * -(ry * x1p / rx)

            cx =
                cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2

            cy =
                sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

            theta1 =
                angleOf ((x1p - cxp) / rx) ((y1p - cyp) / ry)

            dthetaRaw =
                angleBetween ((x1p - cxp) / rx) ((y1p - cyp) / ry) ((-x1p - cxp) / rx) ((-y1p - cyp) / ry)

            dtheta =
                if not sweep && dthetaRaw > 0 then
                    dthetaRaw - 2 * pi

                else if sweep && dthetaRaw < 0 then
                    dthetaRaw + 2 * pi

                else
                    dthetaRaw

            segments =
                max 1 (ceiling (abs dtheta / (pi / 2) - 1.0e-9))

            delta =
                dtheta / toFloat segments

            t =
                4 / 3 * tan (delta / 4)

            pointAt ang =
                { x = cx + rx * cosPhi * cos ang - ry * sinPhi * sin ang
                , y = cy + rx * sinPhi * cos ang + ry * cosPhi * sin ang
                }

            derivAt ang =
                { x = -rx * cosPhi * sin ang - ry * sinPhi * cos ang
                , y = -rx * sinPhi * sin ang + ry * cosPhi * cos ang
                }

            seg i =
                let
                    a1 =
                        theta1 + toFloat i * delta

                    a2 =
                        a1 + delta

                    s =
                        pointAt a1

                    e =
                        pointAt a2

                    d1 =
                        derivAt a1

                    d2 =
                        derivAt a2
                in
                ( Vec2.add s (Vec2.scale t d1), Vec2.sub e (Vec2.scale t d2), e )
        in
        List.map seg (List.range 0 (segments - 1))


angleOf : Float -> Float -> Float
angleOf ux uy =
    atan2 uy ux


angleBetween : Float -> Float -> Float -> Float -> Float
angleBetween ux uy vx vy =
    let
        dot =
            ux * vx + uy * vy

        len =
            sqrt (ux * ux + uy * uy) * sqrt (vx * vx + vy * vy)

        ang =
            acos (clamp -1 1 (dot / len))
    in
    if ux * vy - uy * vx < 0 then
        -ang

    else
        ang



-- BOUNDS


type alias Bounds =
    { minX : Float, minY : Float, maxX : Float, maxY : Float }


{-| Exact bounding box including Bézier extrema.
-}
bounds : PathGeometry -> Maybe Bounds
bounds g =
    let
        points =
            List.concatMap subpathExtrema g.subpaths
    in
    case points of
        [] ->
            Nothing

        first :: rest ->
            Just
                (List.foldl
                    (\p b ->
                        { minX = min b.minX p.x
                        , minY = min b.minY p.y
                        , maxX = max b.maxX p.x
                        , maxY = max b.maxY p.y
                        }
                    )
                    { minX = first.x, minY = first.y, maxX = first.x, maxY = first.y }
                    rest
                )


subpathExtrema : Subpath -> List Vec2
subpathExtrema s =
    let
        step seg ( prev, acc ) =
            case seg of
                LineTo p ->
                    ( p, p :: acc )

                CubicTo c1 c2 p ->
                    ( p, p :: cubicExtrema prev c1 c2 p ++ acc )
    in
    s.start :: Tuple.second (List.foldl step ( s.start, [] ) s.segments)


cubicExtrema : Vec2 -> Vec2 -> Vec2 -> Vec2 -> List Vec2
cubicExtrema p0 p1 p2 p3 =
    let
        roots f0 f1 f2 f3 =
            -- derivative of cubic: 3[(f1-f0)(1-t)^2 + 2(f2-f1)(1-t)t + (f3-f2)t^2]
            let
                a =
                    -f0 + 3 * f1 - 3 * f2 + f3

                b =
                    2 * (f0 - 2 * f1 + f2)

                c =
                    f1 - f0
            in
            if abs a < 1.0e-12 then
                if abs b < 1.0e-12 then
                    []

                else
                    [ -c / b ]

            else
                let
                    disc =
                        b * b - 4 * a * c
                in
                if disc < 0 then
                    []

                else
                    let
                        sq =
                            sqrt disc
                    in
                    [ (-b + sq) / (2 * a), (-b - sq) / (2 * a) ]

        ts =
            (roots p0.x p1.x p2.x p3.x ++ roots p0.y p1.y p2.y p3.y)
                |> List.filter (\t -> t > 0 && t < 1)
    in
    List.map (cubicPoint p0 p1 p2 p3) ts


cubicPoint : Vec2 -> Vec2 -> Vec2 -> Vec2 -> Float -> Vec2
cubicPoint p0 p1 p2 p3 t =
    let
        mt =
            1 - t

        a =
            mt * mt * mt

        b =
            3 * mt * mt * t

        c =
            3 * mt * t * t

        d =
            t * t * t
    in
    { x = a * p0.x + b * p1.x + c * p2.x + d * p3.x
    , y = a * p0.y + b * p1.y + c * p2.y + d * p3.y
    }


cubicTangent : Vec2 -> Vec2 -> Vec2 -> Vec2 -> Float -> Vec2
cubicTangent p0 p1 p2 p3 t =
    let
        mt =
            1 - t
    in
    { x = 3 * mt * mt * (p1.x - p0.x) + 6 * mt * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x)
    , y = 3 * mt * mt * (p1.y - p0.y) + 6 * mt * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
    }



-- TRANSFORM


transformGeometry : Matrix -> PathGeometry -> PathGeometry
transformGeometry m g =
    let
        tp =
            Matrix.apply m
    in
    { subpaths =
        List.map
            (\s ->
                { s
                    | start = tp s.start
                    , segments =
                        List.map
                            (\seg ->
                                case seg of
                                    LineTo p ->
                                        LineTo (tp p)

                                    CubicTo a b c ->
                                        CubicTo (tp a) (tp b) (tp c)
                            )
                            s.segments
                }
            )
            g.subpaths
    }



-- ANCHORS (direct selection)


anchors : PathGeometry -> List Anchor
anchors g =
    List.concat (List.indexedMap subpathAnchors g.subpaths)


subpathAnchors : Int -> Subpath -> List Anchor
subpathAnchors si s =
    let
        outHandle idx =
            case List.head (List.drop idx s.segments) of
                Just (CubicTo c1 _ _) ->
                    Just c1

                _ ->
                    Nothing

        inHandle idx =
            case List.head (List.drop (idx - 1) s.segments) of
                Just (CubicTo _ c2 _) ->
                    if idx > 0 then
                        Just c2

                    else
                        Nothing

                _ ->
                    Nothing

        endPoints =
            List.indexedMap
                (\i seg ->
                    let
                        idx =
                            i + 1

                        p =
                            case seg of
                                LineTo e ->
                                    e

                                CubicTo _ _ e ->
                                    e
                    in
                    { subpath = si, index = idx, point = p, handleIn = inHandle idx, handleOut = outHandle idx }
                )
                s.segments
    in
    { subpath = si, index = 0, point = s.start, handleIn = Nothing, handleOut = outHandle 0 } :: endPoints


{-| Move an anchor (and its attached handles) by a delta.
-}
moveAnchor : Int -> Int -> Vec2 -> PathGeometry -> PathGeometry
moveAnchor si idx delta g =
    { subpaths =
        List.indexedMap
            (\i s ->
                if i /= si then
                    s

                else
                    let
                        start =
                            if idx == 0 then
                                Vec2.add s.start delta

                            else
                                s.start

                        segments =
                            List.indexedMap
                                (\j seg ->
                                    let
                                        segEndIdx =
                                            j + 1
                                    in
                                    case seg of
                                        LineTo p ->
                                            if segEndIdx == idx then
                                                LineTo (Vec2.add p delta)

                                            else
                                                seg

                                        CubicTo c1 c2 p ->
                                            let
                                                nc1 =
                                                    if j == idx then
                                                        Vec2.add c1 delta

                                                    else
                                                        c1

                                                ( nc2, np ) =
                                                    if segEndIdx == idx then
                                                        ( Vec2.add c2 delta, Vec2.add p delta )

                                                    else
                                                        ( c2, p )
                                            in
                                            CubicTo nc1 nc2 np
                                )
                                s.segments
                    in
                    { s | start = start, segments = segments }
            )
            g.subpaths
    }


{-| Set the outgoing handle of an anchor (and mirror into the incoming one when
`mirror` is true). Converts adjacent line segments into cubics as needed.
-}
setAnchorHandles : Int -> Int -> Vec2 -> Bool -> PathGeometry -> PathGeometry
setAnchorHandles si idx handleOut mirror g =
    { subpaths =
        List.indexedMap
            (\i s ->
                if i /= si then
                    s

                else
                    let
                        anchorPoint =
                            anchorPointAt idx s

                        mirrored =
                            Vec2.sub (Vec2.scale 2 anchorPoint) handleOut

                        segments =
                            List.indexedMap
                                (\j seg ->
                                    let
                                        segEndIdx =
                                            j + 1

                                        segStart =
                                            anchorPointAt j s

                                        ( c1, c2, p ) =
                                            case seg of
                                                LineTo e ->
                                                    ( segStart, e, e )

                                                CubicTo a b e ->
                                                    ( a, b, e )
                                    in
                                    if j == idx then
                                        CubicTo handleOut c2 p

                                    else if segEndIdx == idx && mirror then
                                        CubicTo c1 mirrored p

                                    else
                                        seg
                                )
                                s.segments
                    in
                    { s | segments = segments }
            )
            g.subpaths
    }


anchorPointAt : Int -> Subpath -> Vec2
anchorPointAt idx s =
    if idx == 0 then
        s.start

    else
        case List.head (List.drop (idx - 1) s.segments) of
            Just (LineTo p) ->
                p

            Just (CubicTo _ _ p) ->
                p

            Nothing ->
                s.start


toggleClosed : PathGeometry -> PathGeometry
toggleClosed g =
    { subpaths = List.map (\s -> { s | closed = not s.closed }) g.subpaths }



-- MORPH


{-| Two paths are morph-compatible when they have the same subpath count,
each pair has the same segment count and closed flag.
-}
isCompatible : PathGeometry -> PathGeometry -> Bool
isCompatible a b =
    List.length a.subpaths
        == List.length b.subpaths
        && List.all identity
            (List.map2
                (\sa sb -> List.length sa.segments == List.length sb.segments && sa.closed == sb.closed)
                a.subpaths
                b.subpaths
            )


{-| Pointwise interpolation. Line segments paired with cubics are promoted to
cubics with collinear handles so handles interpolate sensibly.
-}
interpolate : PathGeometry -> PathGeometry -> Float -> PathGeometry
interpolate a b t =
    { subpaths =
        List.map2
            (\sa sb ->
                { start = Vec2.lerp sa.start sb.start t
                , closed = sa.closed
                , segments =
                    List.map3
                        (\( pa, sega ) ( pb, segb ) _ -> interpolateSegment pa sega pb segb t)
                        (withStarts sa)
                        (withStarts sb)
                        sa.segments
                }
            )
            a.subpaths
            b.subpaths
    }


withStarts : Subpath -> List ( Vec2, Segment )
withStarts s =
    let
        step seg ( prev, acc ) =
            ( segmentEnd seg, ( prev, seg ) :: acc )
    in
    List.reverse (Tuple.second (List.foldl step ( s.start, [] ) s.segments))


segmentEnd : Segment -> Vec2
segmentEnd seg =
    case seg of
        LineTo p ->
            p

        CubicTo _ _ p ->
            p


interpolateSegment : Vec2 -> Segment -> Vec2 -> Segment -> Float -> Segment
interpolateSegment startA sa startB sb t =
    case ( sa, sb ) of
        ( LineTo pa, LineTo pb ) ->
            LineTo (Vec2.lerp pa pb t)

        _ ->
            let
                ( a1, a2, ae ) =
                    asCubic startA sa

                ( b1, b2, be ) =
                    asCubic startB sb
            in
            CubicTo (Vec2.lerp a1 b1 t) (Vec2.lerp a2 b2 t) (Vec2.lerp ae be t)


asCubic : Vec2 -> Segment -> ( Vec2, Vec2, Vec2 )
asCubic start seg =
    case seg of
        LineTo p ->
            ( Vec2.lerp start p (1 / 3), Vec2.lerp start p (2 / 3), p )

        CubicTo a b p ->
            ( a, b, p )



-- ARC LENGTH


type alias ArcSample =
    { length : Float, point : Vec2, tangent : Vec2 }


type alias ArcTable =
    { samples : List ArcSample, total : Float }


{-| Build an arc-length lookup table by uniform parametric sampling with the
given subdivisions per segment.
-}
arcTable : Int -> PathGeometry -> ArcTable
arcTable subdivisions g =
    let
        n =
            max 1 subdivisions

        sampleSegment start seg =
            case seg of
                LineTo p ->
                    List.map
                        (\i ->
                            let
                                t =
                                    toFloat i / toFloat n
                            in
                            ( Vec2.lerp start p t, Vec2.sub p start )
                        )
                        (List.range 1 n)

                CubicTo c1 c2 p ->
                    List.map
                        (\i ->
                            let
                                t =
                                    toFloat i / toFloat n
                            in
                            ( cubicPoint start c1 c2 p t, cubicTangent start c1 c2 p t )
                        )
                        (List.range 1 n)

        subpathSamples s =
            let
                segs =
                    if s.closed then
                        s.segments ++ [ LineTo s.start ]

                    else
                        s.segments

                step seg ( prev, acc ) =
                    ( segmentEnd seg, acc ++ sampleSegment prev seg )

                ( _, pts ) =
                    List.foldl step ( s.start, [] ) segs

                firstTangent =
                    case pts of
                        ( _, tg ) :: _ ->
                            tg

                        [] ->
                            { x = 1, y = 0 }
            in
            ( s.start, firstTangent ) :: pts

        allPoints =
            List.concatMap subpathSamples g.subpaths

        accumulate ( p, tg ) ( prevPoint, total, acc ) =
            let
                d =
                    case prevPoint of
                        Just pp ->
                            Vec2.distance pp p

                        Nothing ->
                            0

                newTotal =
                    total + d
            in
            ( Just p, newTotal, { length = newTotal, point = p, tangent = tg } :: acc )

        ( _, totalLen, samplesRev ) =
            List.foldl accumulate ( Nothing, 0, [] ) allPoints
    in
    { samples = List.reverse samplesRev, total = totalLen }


totalLength : ArcTable -> Float
totalLength t =
    t.total


{-| Point and unit tangent at a distance along the path. Zero-length paths
return the start point with a (1,0) tangent.
-}
pointAtLength : ArcTable -> Float -> { point : Vec2, tangent : Vec2 }
pointAtLength table dist =
    case table.samples of
        [] ->
            { point = Vec2.zero, tangent = { x = 1, y = 0 } }

        first :: _ ->
            if table.total <= 0 then
                { point = first.point, tangent = safeTangent first.tangent }

            else
                let
                    d =
                        clamp 0 table.total dist
                in
                findSample d first table.samples


findSample : Float -> ArcSample -> List ArcSample -> { point : Vec2, tangent : Vec2 }
findSample d prev samples =
    case samples of
        [] ->
            { point = prev.point, tangent = safeTangent prev.tangent }

        s :: rest ->
            if s.length >= d then
                let
                    span =
                        s.length - prev.length

                    t =
                        if span <= 0 then
                            1

                        else
                            (d - prev.length) / span
                in
                { point = Vec2.lerp prev.point s.point t
                , tangent = safeTangent s.tangent
                }

            else
                findSample d s rest


safeTangent : Vec2 -> Vec2
safeTangent t =
    let
        n =
            Vec2.normalize t
    in
    if n.x == 0 && n.y == 0 then
        { x = 1, y = 0 }

    else
        n
