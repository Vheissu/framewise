module Domain.Transform exposing
    ( Transform
    , identity
    , isFinite
    , toMatrix
    , translated
    )

import Domain.Matrix as Matrix exposing (Matrix)
import Domain.Vec2 as Vec2 exposing (Vec2)


type alias Transform =
    { translation : Vec2
    , scale : Vec2
    , rotation : Float
    , skew : Vec2
    , pivot : Vec2
    }


identity : Transform
identity =
    { translation = Vec2.zero
    , scale = { x = 1, y = 1 }
    , rotation = 0
    , skew = Vec2.zero
    , pivot = Vec2.zero
    }


translated : Vec2 -> Transform
translated t =
    { identity | translation = t }


toMatrix : Transform -> Matrix
toMatrix =
    Matrix.fromComponents


isFinite : Transform -> Bool
isFinite t =
    Vec2.isFinite t.translation
        && Vec2.isFinite t.scale
        && Vec2.isFinite t.skew
        && Vec2.isFinite t.pivot
        && not (isNaN t.rotation || isInfinite t.rotation)
