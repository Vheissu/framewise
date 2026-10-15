module Domain.Easing exposing
    ( Easing(..)
    , Preset(..)
    , SpringParams
    , allPresets
    , cubicBezierAt
    , defaultSpring
    , evaluate
    , isStepped
    , label
    , presetFromCode
    , presetToCode
    , presetToCubic
    , solveBezierX
    )

{-| Easing functions map normalised segment progress `u` in `[0,1]` to a
progress value `t`. Springs and overshoot presets may leave `[0,1]`; callers
clamp only where a property domain requires it.

All functions are pure and deterministic. The spring is a closed-form damped
harmonic oscillator, so it does not depend on frame rate.

-}


type Easing
    = Hold
    | Linear
    | Preset Preset
    | CubicBezier Float Float Float Float
    | Spring SpringParams


type Preset
    = Ease
    | EaseIn
    | EaseOut
    | EaseInOut
    | BackIn
    | BackOut
    | ElasticIn
    | ElasticOut
    | BounceIn
    | BounceOut


type alias SpringParams =
    { mass : Float, stiffness : Float, damping : Float, velocity : Float }


defaultSpring : SpringParams
defaultSpring =
    { mass = 1, stiffness = 170, damping = 20, velocity = 0 }


allPresets : List Preset
allPresets =
    [ Ease, EaseIn, EaseOut, EaseInOut, BackIn, BackOut, ElasticIn, ElasticOut, BounceIn, BounceOut ]


presetToCode : Preset -> String
presetToCode p =
    case p of
        Ease ->
            "ease"

        EaseIn ->
            "ease-in"

        EaseOut ->
            "ease-out"

        EaseInOut ->
            "ease-in-out"

        BackIn ->
            "back-in"

        BackOut ->
            "back-out"

        ElasticIn ->
            "elastic-in"

        ElasticOut ->
            "elastic-out"

        BounceIn ->
            "bounce-in"

        BounceOut ->
            "bounce-out"


presetFromCode : String -> Maybe Preset
presetFromCode code =
    List.filter (\p -> presetToCode p == code) allPresets |> List.head


label : Easing -> String
label e =
    case e of
        Hold ->
            "Hold"

        Linear ->
            "Linear"

        Preset p ->
            presetLabel p

        CubicBezier _ _ _ _ ->
            "Cubic Bézier"

        Spring _ ->
            "Spring"


presetLabel : Preset -> String
presetLabel p =
    case p of
        Ease ->
            "Ease"

        EaseIn ->
            "Ease In"

        EaseOut ->
            "Ease Out"

        EaseInOut ->
            "Ease In Out"

        BackIn ->
            "Back In"

        BackOut ->
            "Back Out"

        ElasticIn ->
            "Elastic In"

        ElasticOut ->
            "Elastic Out"

        BounceIn ->
            "Bounce In"

        BounceOut ->
            "Bounce Out"


{-| CSS-equivalent cubic Bézier control points for the smooth presets.
Overshoot presets have no cubic equivalent and return Nothing.
-}
presetToCubic : Preset -> Maybe { x1 : Float, y1 : Float, x2 : Float, y2 : Float }
presetToCubic p =
    case p of
        Ease ->
            Just { x1 = 0.25, y1 = 0.1, x2 = 0.25, y2 = 1 }

        EaseIn ->
            Just { x1 = 0.42, y1 = 0, x2 = 1, y2 = 1 }

        EaseOut ->
            Just { x1 = 0, y1 = 0, x2 = 0.58, y2 = 1 }

        EaseInOut ->
            Just { x1 = 0.42, y1 = 0, x2 = 0.58, y2 = 1 }

        _ ->
            Nothing


isStepped : Easing -> Bool
isStepped e =
    e == Hold


evaluate : Easing -> Float -> Float
evaluate easing u =
    let
        uc =
            clamp 0 1 u
    in
    case easing of
        Hold ->
            if uc >= 1 then
                1

            else
                0

        Linear ->
            uc

        Preset p ->
            evaluatePreset p uc

        CubicBezier x1 y1 x2 y2 ->
            cubicBezierAt x1 y1 x2 y2 uc

        Spring params ->
            spring params uc


evaluatePreset : Preset -> Float -> Float
evaluatePreset p u =
    case presetToCubic p of
        Just c ->
            cubicBezierAt c.x1 c.y1 c.x2 c.y2 u

        Nothing ->
            case p of
                BackIn ->
                    backIn u

                BackOut ->
                    1 - backIn (1 - u)

                ElasticIn ->
                    elasticIn u

                ElasticOut ->
                    1 - elasticIn (1 - u)

                BounceIn ->
                    1 - bounceOut (1 - u)

                BounceOut ->
                    bounceOut u

                _ ->
                    u


backIn : Float -> Float
backIn u =
    let
        c1 =
            1.70158

        c3 =
            c1 + 1
    in
    c3 * u * u * u - c1 * u * u


elasticIn : Float -> Float
elasticIn u =
    if u <= 0 then
        0

    else if u >= 1 then
        1

    else
        let
            c4 =
                (2 * pi) / 3
        in
        -(2 ^ (10 * u - 10)) * sin ((u * 10 - 10.75) * c4)


bounceOut : Float -> Float
bounceOut u =
    let
        n1 =
            7.5625

        d1 =
            2.75
    in
    if u < 1 / d1 then
        n1 * u * u

    else if u < 2 / d1 then
        let
            v =
                u - 1.5 / d1
        in
        n1 * v * v + 0.75

    else if u < 2.5 / d1 then
        let
            v =
                u - 2.25 / d1
        in
        n1 * v * v + 0.9375

    else
        let
            v =
                u - 2.625 / d1
        in
        n1 * v * v + 0.984375


{-| Evaluate a CSS-style cubic Bézier timing function at time `x`.
Returns exactly 0 at x=0 and exactly 1 at x=1.
-}
cubicBezierAt : Float -> Float -> Float -> Float -> Float -> Float
cubicBezierAt x1 y1 x2 y2 x =
    if x <= 0 then
        0

    else if x >= 1 then
        1

    else
        let
            t =
                solveBezierX x1 x2 x
        in
        bezierComponent y1 y2 t


bezierComponent : Float -> Float -> Float -> Float
bezierComponent p1 p2 t =
    -- B(t) with P0=0, P3=1
    let
        mt =
            1 - t
    in
    3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t


bezierDerivative : Float -> Float -> Float -> Float
bezierDerivative p1 p2 t =
    let
        mt =
            1 - t
    in
    3 * mt * mt * p1 + 6 * mt * t * (p2 - p1) + 3 * t * t * (1 - p2)


{-| Solve for parameter `t` such that the X component equals `x`.
Newton iterations with a bisection fallback when the derivative degenerates.
-}
solveBezierX : Float -> Float -> Float -> Float
solveBezierX x1 x2 x =
    let
        cx1 =
            clamp 0 1 x1

        cx2 =
            clamp 0 1 x2

        newton t iter =
            if iter <= 0 then
                t

            else
                let
                    fx =
                        bezierComponent cx1 cx2 t - x

                    dx =
                        bezierDerivative cx1 cx2 t
                in
                if abs fx < 1.0e-7 then
                    t

                else if abs dx < 1.0e-6 then
                    bisect 0 1 40

                else
                    let
                        next =
                            t - fx / dx
                    in
                    if next < 0 || next > 1 then
                        bisect 0 1 40

                    else
                        newton next (iter - 1)

        bisect lo hi iter =
            let
                mid =
                    (lo + hi) / 2

                fx =
                    bezierComponent cx1 cx2 mid - x
            in
            if iter <= 0 || abs fx < 1.0e-7 then
                mid

            else if fx > 0 then
                bisect lo mid (iter - 1)

            else
                bisect mid hi (iter - 1)
    in
    newton x 12


{-| Closed-form damped spring from 0 to 1 over normalised time `u`.
The spring is evaluated over a fixed virtual duration so the result is
independent of frame rate. Values can overshoot 1 for low damping.
-}
spring : SpringParams -> Float -> Float
spring params u =
    if u <= 0 then
        0

    else if u >= 1 then
        1

    else
        let
            m =
                max 0.001 params.mass

            k =
                max 0.001 params.stiffness

            c =
                max 0 params.damping

            v0 =
                params.velocity

            -- virtual seconds covered by the segment
            duration =
                1.0

            t =
                u * duration

            w0 =
                sqrt (k / m)

            zeta =
                c / (2 * sqrt (k * m))

            -- displacement from rest, starting at -1 (position 0 relative to target 1)
            x0 =
                -1
        in
        if zeta < 1 then
            let
                wd =
                    w0 * sqrt (1 - zeta * zeta)

                a =
                    x0

                b =
                    (zeta * w0 * x0 + v0) / wd

                disp =
                    e ^ (-zeta * w0 * t) * (a * cos (wd * t) + b * sin (wd * t))
            in
            1 + disp

        else if zeta == 1 then
            let
                disp =
                    (x0 + (v0 + w0 * x0) * t) * e ^ (-w0 * t)
            in
            1 + disp

        else
            let
                s1 =
                    -w0 * (zeta - sqrt (zeta * zeta - 1))

                s2 =
                    -w0 * (zeta + sqrt (zeta * zeta - 1))

                c2 =
                    (v0 - s1 * x0) / (s2 - s1)

                c1 =
                    x0 - c2

                disp =
                    c1 * e ^ (s1 * t) + c2 * e ^ (s2 * t)
            in
            1 + disp
