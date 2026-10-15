module Domain.Vec2 exposing
    ( Vec2
    , add
    , distance
    , isFinite
    , length
    , lerp
    , normalize
    , scale
    , sub
    , vec2
    , zero
    )


type alias Vec2 =
    { x : Float, y : Float }


vec2 : Float -> Float -> Vec2
vec2 x y =
    { x = x, y = y }


zero : Vec2
zero =
    { x = 0, y = 0 }


add : Vec2 -> Vec2 -> Vec2
add a b =
    { x = a.x + b.x, y = a.y + b.y }


sub : Vec2 -> Vec2 -> Vec2
sub a b =
    { x = a.x - b.x, y = a.y - b.y }


scale : Float -> Vec2 -> Vec2
scale k v =
    { x = v.x * k, y = v.y * k }


length : Vec2 -> Float
length v =
    sqrt (v.x * v.x + v.y * v.y)


distance : Vec2 -> Vec2 -> Float
distance a b =
    length (sub a b)


normalize : Vec2 -> Vec2
normalize v =
    let
        l =
            length v
    in
    if l == 0 then
        zero

    else
        scale (1 / l) v


lerp : Vec2 -> Vec2 -> Float -> Vec2
lerp a b t =
    { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }


isFinite : Vec2 -> Bool
isFinite v =
    not (isNaN v.x || isInfinite v.x || isNaN v.y || isInfinite v.y)
