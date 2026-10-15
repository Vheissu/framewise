module Domain.Matrix exposing
    ( Matrix
    , apply
    , applyVector
    , compose
    , decompose
    , determinant
    , fromComponents
    , fromComponentsWithMotion
    , identity
    , invert
    , isFinite
    , multiply
    , rotation
    , scaling
    , skewing
    , toSvgTransform
    , translation
    )

{-| 2D affine matrices.

Convention: column vectors. A point `p` is transformed as `M * p`. `multiply a b`
is the matrix product `a * b`, which applies `b` first and then `a`. A node's
world matrix is `parentWorld * local`, i.e. `multiply parentWorld local`.

The matrix stores the six SVG `matrix(a b c d e f)` coefficients:

    | a c e |
    | b d f |
    | 0 0 1 |

Examples:

    apply (translation 10 0) { x = 1, y = 1 } == { x = 11, y = 1 }

    apply (multiply (translation 10 0) (scaling 2 2)) { x = 1, y = 1 } == { x = 12, y = 2 }

-}

import Domain.Vec2 exposing (Vec2)


type alias Matrix =
    { a : Float, b : Float, c : Float, d : Float, e : Float, f : Float }


identity : Matrix
identity =
    { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }


translation : Float -> Float -> Matrix
translation tx ty =
    { a = 1, b = 0, c = 0, d = 1, e = tx, f = ty }


scaling : Float -> Float -> Matrix
scaling sx sy =
    { a = sx, b = 0, c = 0, d = sy, e = 0, f = 0 }


{-| Rotation in degrees, clockwise on screen (SVG convention, y down).
-}
rotation : Float -> Matrix
rotation degrees =
    let
        r =
            degrees * pi / 180

        cs =
            cos r

        sn =
            sin r
    in
    { a = cs, b = sn, c = -sn, d = cs, e = 0, f = 0 }


{-| Skew in degrees: `skewX(x) * skewY(y)`, i.e. skewY is applied first.
This matches the nested `<g transform="skewX"><g transform="skewY">`
structure used by the SVG exporters.
-}
skewing : Float -> Float -> Matrix
skewing skewX skewY =
    let
        tx =
            tan (skewX * pi / 180)

        ty =
            tan (skewY * pi / 180)
    in
    multiply { a = 1, b = 0, c = tx, d = 1, e = 0, f = 0 } { a = 1, b = ty, c = 0, d = 1, e = 0, f = 0 }


multiply : Matrix -> Matrix -> Matrix
multiply m n =
    { a = m.a * n.a + m.c * n.b
    , b = m.b * n.a + m.d * n.b
    , c = m.a * n.c + m.c * n.d
    , d = m.b * n.c + m.d * n.d
    , e = m.a * n.e + m.c * n.f + m.e
    , f = m.b * n.e + m.d * n.f + m.f
    }


{-| Compose a list of matrices, applying them in list order (first element is
applied first to the point).
-}
compose : List Matrix -> Matrix
compose ms =
    List.foldl (\m acc -> multiply m acc) identity ms


{-| Build a node-local matrix from decomposed components.

Order (applied to a point): translate by `-pivot`, scale, skew, rotate,
translate by `pivot`, then translate by `translation`. This means the pivot is
the fixed point of scale/rotate/skew in the node's own geometry space.

-}
fromComponents :
    { translation : Vec2, scale : Vec2, rotation : Float, skew : Vec2, pivot : Vec2 }
    -> Matrix
fromComponents t =
    fromComponentsWithMotion t Nothing


{-| Like `fromComponents`, with an optional motion-path contribution applied
between the pivot translate and the node translation: `rotate(angle)` then
`translate(offset)`. This is exactly the supplemental transform SMIL's
`animateMotion` (with `rotate="auto"`) applies to an element.
-}
fromComponentsWithMotion :
    { translation : Vec2, scale : Vec2, rotation : Float, skew : Vec2, pivot : Vec2 }
    -> Maybe { offset : Vec2, angle : Float }
    -> Matrix
fromComponentsWithMotion t motion =
    compose
        ([ translation -t.pivot.x -t.pivot.y
         , scaling t.scale.x t.scale.y
         , skewing t.skew.x t.skew.y
         , rotation t.rotation
         , translation t.pivot.x t.pivot.y
         ]
            ++ (case motion of
                    Just m ->
                        [ rotation m.angle, translation m.offset.x m.offset.y ]

                    Nothing ->
                        []
               )
            ++ [ translation t.translation.x t.translation.y ]
        )


apply : Matrix -> Vec2 -> Vec2
apply m p =
    { x = m.a * p.x + m.c * p.y + m.e
    , y = m.b * p.x + m.d * p.y + m.f
    }


{-| Transform a direction (ignores translation).
-}
applyVector : Matrix -> Vec2 -> Vec2
applyVector m v =
    { x = m.a * v.x + m.c * v.y
    , y = m.b * v.x + m.d * v.y
    }


determinant : Matrix -> Float
determinant m =
    m.a * m.d - m.b * m.c


invert : Matrix -> Maybe Matrix
invert m =
    let
        det =
            determinant m
    in
    if det == 0 || isNaN det || isInfinite det || abs det < 1.0e-12 then
        Nothing

    else
        let
            ia =
                m.d / det

            ib =
                -m.b / det

            ic =
                -m.c / det

            id =
                m.a / det
        in
        Just
            { a = ia
            , b = ib
            , c = ic
            , d = id
            , e = -(ia * m.e + ic * m.f)
            , f = -(ib * m.e + id * m.f)
            }


isFinite : Matrix -> Bool
isFinite m =
    List.all (\v -> not (isNaN v || isInfinite v)) [ m.a, m.b, m.c, m.d, m.e, m.f ]


toSvgTransform : Matrix -> String
toSvgTransform m =
    "matrix("
        ++ String.join " " (List.map fmt [ m.a, m.b, m.c, m.d, m.e, m.f ])
        ++ ")"


fmt : Float -> String
fmt v =
    let
        rounded =
            toFloat (round (v * 100000)) / 100000
    in
    if rounded == toFloat (round rounded) then
        String.fromInt (round rounded)

    else
        String.fromFloat rounded


{-| Decompose a matrix into transform components with a fixed pivot, such
that `fromComponents result == m` (up to floating point). Skew is expressed on
the X axis only; the Y skew component is always 0.

    decompose pivot (fromComponents t) ≈ t -- when t.skew.y == 0

-}
decompose : Vec2 -> Matrix -> { translation : Vec2, scale : Vec2, rotation : Float, skew : Vec2, pivot : Vec2 }
decompose pivot m =
    let
        sx =
            sqrt (m.a * m.a + m.b * m.b)

        det =
            determinant m

        theta =
            atan2 m.b m.a

        sxSafe =
            if sx == 0 then
                1.0e-9

            else
                sx

        sy =
            det / sxSafe

        -- rotate second column by -theta
        cosT =
            cos theta

        sinT =
            sin theta

        cPrime =
            cosT * m.c + sinT * m.d

        skewX =
            if sy == 0 then
                0

            else
                atan (cPrime / sy) * 180 / pi

        rotationDeg =
            theta * 180 / pi

        -- M = T(translation + pivot) * L * T(-pivot)  =>  translation = e,f - pivot + L*pivot
        lp =
            applyVector m pivot
    in
    { translation = { x = m.e - pivot.x + lp.x, y = m.f - pivot.y + lp.y }
    , scale = { x = sx, y = sy }
    , rotation = rotationDeg
    , skew = { x = skewX, y = 0 }
    , pivot = pivot
    }
