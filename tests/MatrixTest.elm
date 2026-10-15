module MatrixTest exposing (suite)

import Domain.Matrix as Matrix
import Domain.Transform as Transform
import Domain.Vec2 exposing (Vec2)
import Expect
import Fuzz
import Test exposing (..)


closeVec : Vec2 -> Vec2 -> Expect.Expectation
closeVec a b =
    Expect.all
        [ \_ -> Expect.within (Expect.Absolute 1.0e-6) a.x b.x
        , \_ -> Expect.within (Expect.Absolute 1.0e-6) a.y b.y
        ]
        ()


suite : Test
suite =
    describe "Domain.Matrix"
        [ test "translation moves a point" <|
            \_ -> closeVec (Matrix.apply (Matrix.translation 10 -5) { x = 1, y = 1 }) { x = 11, y = -4 }
        , test "multiply applies the right operand first" <|
            \_ ->
                -- translate(10,0) * scale(2,2) : scale first, then translate
                closeVec (Matrix.apply (Matrix.multiply (Matrix.translation 10 0) (Matrix.scaling 2 2)) { x = 1, y = 1 }) { x = 12, y = 2 }
        , test "compose applies matrices in list order" <|
            \_ ->
                closeVec (Matrix.apply (Matrix.compose [ Matrix.scaling 2 2, Matrix.translation 10 0 ]) { x = 1, y = 1 }) { x = 12, y = 2 }
        , test "rotation of 90 degrees maps x axis to y axis (screen space)" <|
            \_ -> closeVec (Matrix.apply (Matrix.rotation 90) { x = 1, y = 0 }) { x = 0, y = 1 }
        , test "inverse undoes the matrix" <|
            \_ ->
                let
                    m =
                        Matrix.fromComponents { translation = { x = 30, y = -12 }, scale = { x = 2, y = 0.5 }, rotation = 33, skew = { x = 10, y = 0 }, pivot = { x = 5, y = 7 } }

                    p =
                        { x = 3, y = 9 }
                in
                case Matrix.invert m of
                    Just inv ->
                        closeVec (Matrix.apply inv (Matrix.apply m p)) p

                    Nothing ->
                        Expect.fail "matrix should be invertible"
        , test "singular matrices are not inverted" <|
            \_ -> Expect.equal Nothing (Matrix.invert (Matrix.scaling 0 1))
        , test "pivot is the fixed point of rotation" <|
            \_ ->
                let
                    pivot =
                        { x = 50, y = 20 }

                    m =
                        Matrix.fromComponents { translation = { x = 0, y = 0 }, scale = { x = 3, y = 3 }, rotation = 45, skew = { x = 0, y = 0 }, pivot = pivot }
                in
                closeVec (Matrix.apply m pivot) pivot
        , test "translation moves the pivot too" <|
            \_ ->
                let
                    m =
                        Matrix.fromComponents { translation = { x = 100, y = 10 }, scale = { x = 1, y = 1 }, rotation = 90, skew = { x = 0, y = 0 }, pivot = { x = 10, y = 10 } }
                in
                closeVec (Matrix.apply m { x = 10, y = 10 }) { x = 110, y = 20 }
        , test "reflection survives decompose and rebuild" <|
            \_ ->
                let
                    t =
                        { translation = { x = 5, y = 5 }, scale = { x = -1, y = 2 }, rotation = 0, skew = { x = 0, y = 0 }, pivot = { x = 0, y = 0 } }

                    m =
                        Matrix.fromComponents t

                    rebuilt =
                        Matrix.fromComponents (Matrix.decompose t.pivot m)
                in
                closeVec (Matrix.apply rebuilt { x = 3, y = 4 }) (Matrix.apply m { x = 3, y = 4 })
        , fuzz3 (Fuzz.floatRange -200 200) (Fuzz.floatRange 0.2 4) (Fuzz.floatRange -170 170) "decompose round-trips through fromComponents" <|
            \tx s rot ->
                let
                    t =
                        { translation = { x = tx, y = tx / 2 }, scale = { x = s, y = s * 0.5 }, rotation = rot, skew = { x = 12, y = 0 }, pivot = { x = 7, y = -3 } }

                    m =
                        Matrix.fromComponents t

                    rebuilt =
                        Matrix.fromComponents (Matrix.decompose t.pivot m)

                    p =
                        { x = 13, y = -4 }
                in
                closeVec (Matrix.apply rebuilt p) (Matrix.apply m p)
        , test "motion contribution is applied between pivot and translation" <|
            \_ ->
                let
                    base =
                        Transform.identity

                    m =
                        Matrix.fromComponentsWithMotion base (Just { offset = { x = 40, y = 0 }, angle = 90 })
                in
                closeVec (Matrix.apply m { x = 1, y = 0 }) { x = 40, y = 1 }
        , test "toSvgTransform formats compact numbers" <|
            \_ -> Expect.equal "matrix(1 0 0 1 10 -2.5)" (Matrix.toSvgTransform (Matrix.translation 10 -2.5))
        ]
