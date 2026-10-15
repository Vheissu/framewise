module PathTest exposing (suite)

import Domain.Matrix as Matrix
import Domain.Path as Path exposing (Segment(..))
import Expect
import Test exposing (..)


suite : Test
suite =
    describe "Domain.Path"
        [ test "parses absolute and relative commands into normalised segments" <|
            \_ ->
                case Path.parse "M10 10 l 20 0 L 30 30 h -20 v -10 z" of
                    Ok g ->
                        Expect.equal
                            [ { start = { x = 10, y = 10 }, closed = True, segments = [ LineTo { x = 30, y = 10 }, LineTo { x = 30, y = 30 }, LineTo { x = 10, y = 30 }, LineTo { x = 10, y = 20 } ] } ]
                            g.subpaths

                    Err e ->
                        Expect.fail e
        , test "converts quadratic curves to cubics exactly" <|
            \_ ->
                case Path.parse "M0 0 Q 30 60 60 0" of
                    Ok g ->
                        Expect.equal (Just [ CubicTo { x = 20, y = 40 } { x = 40, y = 40 } { x = 60, y = 0 } ]) (List.head g.subpaths |> Maybe.map .segments)

                    Err e ->
                        Expect.fail e
        , test "smooth shorthand reflects the previous control point" <|
            \_ ->
                case Path.parse "M0 0 C 0 10 10 10 10 0 S 20 -10 20 0" of
                    Ok g ->
                        case List.head g.subpaths |> Maybe.map .segments of
                            Just [ _, CubicTo c1 _ _ ] ->
                                Expect.equal { x = 10, y = -10 } c1

                            _ ->
                                Expect.fail "expected two cubics"

                    Err e ->
                        Expect.fail e
        , test "arcs become cubic segments that end at the right point" <|
            \_ ->
                case Path.parse "M0 0 A 10 10 0 0 1 20 0" of
                    Ok g ->
                        let
                            segs =
                                List.head g.subpaths |> Maybe.map .segments |> Maybe.withDefault []

                            endPoint =
                                List.reverse segs |> List.head
                        in
                        case endPoint of
                            Just (CubicTo _ _ p) ->
                                Expect.all
                                    [ \_ -> Expect.within (Expect.Absolute 1.0e-6) 20 p.x
                                    , \_ -> Expect.within (Expect.Absolute 1.0e-6) 0 p.y
                                    , \_ -> Expect.equal 2 (List.length segs)
                                    ]
                                    ()

                            _ ->
                                Expect.fail "expected cubic segments"

                    Err e ->
                        Expect.fail e
        , test "rejects malformed data" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.err (Path.parse "M 1")
                    , \_ -> Expect.err (Path.parse "M 1 1 X 2 2")
                    , \_ -> Expect.err (Path.parse "M 1 1 L 2 foo")
                    ]
                    ()
        , test "handles compact number runs like 1.5.5 and 3-4" <|
            \_ ->
                case Path.parse "M1.5.5L3-4" of
                    Ok g ->
                        Expect.equal (Just { start = { x = 1.5, y = 0.5 }, closed = False, segments = [ LineTo { x = 3, y = -4 } ] }) (List.head g.subpaths)

                    Err e ->
                        Expect.fail e
        , test "serialize then parse is stable" <|
            \_ ->
                case Path.parse "M0 0 C 10 20 30 40 50 60 L 70 80 Z M 5 5 L 6 6" of
                    Ok g ->
                        Expect.equal (Ok g) (Path.parse (Path.serialize g))

                    Err e ->
                        Expect.fail e
        , test "bounds include bezier extrema" <|
            \_ ->
                case Path.parse "M0 0 C 0 100 100 100 100 0" of
                    Ok g ->
                        case Path.bounds g of
                            Just b ->
                                Expect.within (Expect.Absolute 1.0e-6) 75 b.maxY

                            Nothing ->
                                Expect.fail "no bounds"

                    Err e ->
                        Expect.fail e
        , test "arc length of a unit square outline is 4 and progress maps to distance" <|
            \_ ->
                let
                    g =
                        Path.fromPolyline [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 }, { x = 0, y = 1 } ] True

                    table =
                        Path.arcTable 4 g

                    mid =
                        Path.pointAtLength table 2
                in
                Expect.all
                    [ \_ -> Expect.within (Expect.Absolute 1.0e-9) 4 (Path.totalLength table)
                    , \_ -> Expect.within (Expect.Absolute 1.0e-9) 1 mid.point.x
                    , \_ -> Expect.within (Expect.Absolute 1.0e-9) 1 mid.point.y
                    ]
                    ()
        , test "zero-length paths return a safe tangent" <|
            \_ ->
                let
                    table =
                        Path.arcTable 4 (Path.fromPolyline [ { x = 5, y = 5 }, { x = 5, y = 5 } ] False)

                    s =
                        Path.pointAtLength table 0.5
                in
                Expect.equal ( { x = 5, y = 5 }, { x = 1, y = 0 } ) ( s.point, s.tangent )
        , test "compatible paths interpolate pointwise" <|
            \_ ->
                let
                    a =
                        Path.fromPolyline [ { x = 0, y = 0 }, { x = 10, y = 0 } ] False

                    b =
                        Path.fromPolyline [ { x = 0, y = 10 }, { x = 10, y = 10 } ] False
                in
                Expect.all
                    [ \_ -> Expect.equal True (Path.isCompatible a b)
                    , \_ -> Expect.equal (Path.fromPolyline [ { x = 0, y = 5 }, { x = 10, y = 5 } ] False) (Path.interpolate a b 0.5)
                    ]
                    ()
        , test "paths with different structure are incompatible" <|
            \_ ->
                Expect.equal False (Path.isCompatible (Path.fromPolyline [ { x = 0, y = 0 }, { x = 1, y = 1 } ] False) (Path.fromPolyline [ { x = 0, y = 0 }, { x = 1, y = 1 }, { x = 2, y = 2 } ] False))
        , test "transformGeometry moves every point" <|
            \_ ->
                let
                    g =
                        Path.fromPolyline [ { x = 0, y = 0 }, { x = 1, y = 0 } ] False
                in
                Expect.equal (Path.fromPolyline [ { x = 10, y = 5 }, { x = 11, y = 5 } ] False) (Path.transformGeometry (Matrix.translation 10 5) g)
        , test "moveAnchor shifts the anchor and attached handles" <|
            \_ ->
                let
                    g =
                        { subpaths = [ { start = { x = 0, y = 0 }, closed = False, segments = [ CubicTo { x = 1, y = 1 } { x = 9, y = 1 } { x = 10, y = 0 } ] } ] }

                    moved =
                        Path.moveAnchor 0 1 { x = 0, y = 5 } g
                in
                Expect.equal (Just [ CubicTo { x = 1, y = 1 } { x = 9, y = 6 } { x = 10, y = 5 } ]) (List.head moved.subpaths |> Maybe.map .segments)
        ]
