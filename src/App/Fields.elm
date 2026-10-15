module App.Fields exposing
    ( commit
    , currentValue
    , displayValue
    , parseNumber
    , step
    )

{-| Inspector field semantics. A field id names a property of the current
selection (`pos.x`, `size.w`, `opacity`, …) or of the selected keyframe.
Text is parsed on commit; invalid input is rejected with a notice and the
field reverts, so NaN never reaches the document.
-}

import App.Canvas as Canvas
import App.Edit as Edit exposing (Update, pure)
import App.Model as Model exposing (Model)
import App.Msg exposing (Msg)
import App.Timeline as Timeline
import Dict
import Domain.Document as Document
import Domain.Easing exposing (Easing(..))
import Domain.Evaluate as Evaluate
import Domain.Keyframe as Keyframe
import Domain.Node as Node exposing (Node, NodeGeometry(..))
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Domain.Vec2 as Vec2
import Shared.Ids exposing (NodeId)


{-| Parse a number allowing a trailing unit (`px`, `%`, `°`) and simple
arithmetic like `100+20` or `50*2`.
-}
parseNumber : String -> Maybe Float
parseNumber raw =
    let
        cleaned =
            raw
                |> String.trim
                |> String.replace "px" ""
                |> String.replace "°" ""
                |> String.replace "%" ""
                |> String.replace "," "."
                |> String.replace " " ""
    in
    case String.toFloat cleaned of
        Just v ->
            finite v

        Nothing ->
            arithmetic cleaned


arithmetic : String -> Maybe Float
arithmetic s =
    let
        try op f =
            case String.indexes op (String.dropLeft 1 s) of
                i :: _ ->
                    let
                        idx =
                            i + 1

                        a =
                            String.left idx s

                        b =
                            String.dropLeft (idx + 1) s
                    in
                    Maybe.map2 f (String.toFloat a) (String.toFloat b) |> Maybe.andThen finite

                [] ->
                    Nothing
    in
    List.filterMap identity
        [ try "+" (+)
        , try "-" (-)
        , try "*" (*)
        , try "/" (\a b -> a / b)
        ]
        |> List.head


finite : Float -> Maybe Float
finite v =
    if isNaN v || isInfinite v then
        Nothing

    else
        Just v


displayValue : Float -> String
displayValue v =
    let
        r =
            toFloat (round (v * 100)) / 100
    in
    if r == toFloat (round r) then
        String.fromInt (round r)

    else
        String.fromFloat r


firstSelected : Model -> Maybe ( Scene, Node )
firstSelected model =
    case Model.activeScene model of
        Just scene ->
            Edit.selection model
                |> List.head
                |> Maybe.andThen (\id -> Dict.get id scene.nodes)
                |> Maybe.map (\n -> ( scene, n ))

        Nothing ->
            Nothing


evaluated : Model -> Scene -> Node -> PropertyPath -> Maybe PropertyValue
evaluated model scene node property =
    Evaluate.evaluateNodeProperty scene (Edit.currentFrame model) node property


{-| The numeric value a field currently shows (evaluated at the playhead).
-}
currentValue : String -> Model -> Maybe Float
currentValue field model =
    case field of
        "frame" ->
            Just (Edit.currentFrame model)

        "zoom" ->
            Just ((Model.activeView model).zoom * 100)

        _ ->
            if String.startsWith "key." field then
                keyValue field model

            else
                firstSelected model |> Maybe.andThen (\( scene, node ) -> nodeValue field model scene node)


keyValue : String -> Model -> Maybe Float
keyValue field model =
    case ( Model.activeScene model, model.editor.selectedKeys ) of
        ( Just scene, ref :: _ ) ->
            Dict.get ref.trackId scene.tracks
                |> Maybe.andThen (\t -> List.filter (\k -> k.id == ref.keyId) t.keyframes |> List.head)
                |> Maybe.andThen
                    (\k ->
                        case field of
                            "key.frame" ->
                                Just (toFloat k.frame)

                            "key.x1" ->
                                bez k.easing |> Maybe.map .x1

                            "key.y1" ->
                                bez k.easing |> Maybe.map .y1

                            "key.x2" ->
                                bez k.easing |> Maybe.map .x2

                            "key.y2" ->
                                bez k.easing |> Maybe.map .y2

                            "key.mass" ->
                                spr k.easing |> Maybe.map .mass

                            "key.stiffness" ->
                                spr k.easing |> Maybe.map .stiffness

                            "key.damping" ->
                                spr k.easing |> Maybe.map .damping

                            "key.velocity" ->
                                spr k.easing |> Maybe.map .velocity

                            "key.value" ->
                                case k.value of
                                    Scalar v ->
                                        Just v

                                    Angle v ->
                                        Just v

                                    _ ->
                                        Nothing

                            "key.value.x" ->
                                case k.value of
                                    PointValue p ->
                                        Just p.x

                                    SizeValue p ->
                                        Just p.x

                                    _ ->
                                        Nothing

                            "key.value.y" ->
                                case k.value of
                                    PointValue p ->
                                        Just p.y

                                    SizeValue p ->
                                        Just p.y

                                    _ ->
                                        Nothing

                            _ ->
                                Nothing
                    )

        _ ->
            Nothing


bez : Easing -> Maybe { x1 : Float, y1 : Float, x2 : Float, y2 : Float }
bez e =
    case e of
        CubicBezier x1 y1 x2 y2 ->
            Just { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }

        Preset p ->
            Domain.Easing.presetToCubic p

        Linear ->
            Just { x1 = 0, y1 = 0, x2 = 1, y2 = 1 }

        _ ->
            Nothing


spr : Easing -> Maybe Domain.Easing.SpringParams
spr e =
    case e of
        Spring s ->
            Just s

        _ ->
            Nothing


nodeValue : String -> Model -> Scene -> Node -> Maybe Float
nodeValue field model scene node =
    let
        point p get =
            case evaluated model scene node p of
                Just (PointValue v) ->
                    Just (get v)

                Just (SizeValue v) ->
                    Just (get v)

                _ ->
                    Nothing

        scalar p =
            case evaluated model scene node p of
                Just (Scalar v) ->
                    Just v

                Just (Angle v) ->
                    Just v

                _ ->
                    Nothing
    in
    case field of
        "pos.x" ->
            point Position .x

        "pos.y" ->
            point Position .y

        "size.w" ->
            sizeOf model node |> Maybe.map .x

        "size.h" ->
            sizeOf model node |> Maybe.map .y

        "rot" ->
            scalar Rotation

        "scale.x" ->
            point Scale .x |> Maybe.map ((*) 100)

        "scale.y" ->
            point Scale .y |> Maybe.map ((*) 100)

        "skew.x" ->
            point Skew .x

        "skew.y" ->
            point Skew .y

        "pivot.x" ->
            point Pivot .x

        "pivot.y" ->
            point Pivot .y

        "opacity" ->
            scalar Opacity |> Maybe.map ((*) 100)

        "corner" ->
            scalar RectCornerRadius

        "stroke.width" ->
            scalar StrokeWidth

        "dash.offset" ->
            scalar DashOffset

        "font.size" ->
            scalar FontSize

        "blur" ->
            scalar BlurRadius

        "progress" ->
            scalar MotionProgress |> Maybe.map ((*) 100)

        "letter" ->
            case node.geometry of
                Text t ->
                    Just t.letterSpacing

                _ ->
                    Nothing

        "sides" ->
            case node.geometry of
                Polygon p ->
                    Just (toFloat p.sides)

                _ ->
                    Nothing

        "polyradius" ->
            case node.geometry of
                Polygon p ->
                    Just p.radius

                _ ->
                    Nothing

        "inner" ->
            case node.geometry of
                Polygon p ->
                    p.innerRadius

                _ ->
                    Nothing

        "line.x2" ->
            case node.geometry of
                Line l ->
                    Just l.end.x

                _ ->
                    Nothing

        "line.y2" ->
            case node.geometry of
                Line l ->
                    Just l.end.y

                _ ->
                    Nothing

        "miter" ->
            Just node.stroke.miterLimit

        _ ->
            Nothing


{-| Displayed width/height: geometry size for primitives, world bounds for
everything else.
-}
sizeOf : Model -> Node -> Maybe Vec2.Vec2
sizeOf model node =
    case node.geometry of
        Rectangle _ ->
            case Model.activeScene model |> Maybe.andThen (\s -> evaluated model s node RectSize) of
                Just (SizeValue s) ->
                    Just s

                _ ->
                    Nothing

        Ellipse _ ->
            case Model.activeScene model |> Maybe.andThen (\s -> evaluated model s node EllipseRadii) of
                Just (SizeValue r) ->
                    Just { x = r.x * 2, y = r.y * 2 }

                _ ->
                    Nothing

        RasterImage i ->
            Just i.size

        _ ->
            Canvas.resolvedNow model
                |> Maybe.andThen (\r -> Dict.get node.id r.byId |> Maybe.andThen (Evaluate.worldBounds r))
                |> Maybe.map (\b -> { x = b.maxX - b.minX, y = b.maxY - b.minY })


{-| Commit typed text for a field.
-}
commit : String -> String -> Model -> Update
commit field text model =
    let
        cleared =
            { model | fieldDrafts = Dict.remove field model.fieldDrafts }
    in
    if field == "text.content" then
        applyToSelection "Edit text" (\m id -> setProp m id TextContent (StringValue text)) cleared

    else if field == "name" then
        case Model.activeScene cleared of
            Just scene ->
                Edit.commitCoalesced "rename" "Rename" (Document.updateScene scene.id (\s -> List.foldl (\id acc -> Scene.updateNode id (\n -> { n | name = text }) acc) s (Edit.selection cleared))) cleared

            Nothing ->
                pure cleared

    else if field == "font.family" then
        applyToSelection "Font"
            (\_ id s ->
                Scene.updateNode id
                    (\n ->
                        case n.geometry of
                            Text t ->
                                { n | geometry = Text { t | fontFamily = text } }

                            _ ->
                                n
                    )
                    s
            )
            cleared

    else if field == "dash.array" then
        let
            values =
                text
                    |> String.split ","
                    |> List.concatMap (String.split " ")
                    |> List.filter (not << String.isEmpty)
                    |> List.filterMap String.toFloat
                    |> List.filter (\v -> v >= 0)
        in
        applyToSelection "Dash pattern"
            (\_ id s ->
                Scene.updateNode id
                    (\n ->
                        let
                            st =
                                n.stroke
                        in
                        { n | stroke = { st | dashArray = values } }
                    )
                    s
            )
            cleared

    else
        case parseNumber text of
            Nothing ->
                pure (Edit.toast "error" ("\"" ++ text ++ "\" is not a number") cleared)

            Just value ->
                applyNumber field value cleared


{-| Arrow-key stepping: current value plus delta.
-}
step : String -> Float -> Model -> Update
step field delta model =
    case currentValue field model of
        Just current ->
            applyNumber field (current + delta) model

        Nothing ->
            pure model


applyNumber : String -> Float -> Model -> Update
applyNumber field value model =
    case field of
        "frame" ->
            pure (Timeline.setPlayhead value model)

        "zoom" ->
            let
                rect =
                    model.editor.canvasRect
            in
            pure (Canvas.zoomAround { x = rect.width / 2, y = rect.height / 2 } (clamp 10 3200 value / 100) model)

        _ ->
            if String.startsWith "key." field then
                applyKeyNumber field value model

            else
                applyNodeNumber field value model


applyKeyNumber : String -> Float -> Model -> Update
applyKeyNumber field value model =
    case ( Model.activeScene model, model.editor.selectedKeys ) of
        ( Just scene, refs ) ->
            let
                update s =
                    List.foldl
                        (\ref acc ->
                            case Dict.get ref.trackId acc.tracks of
                                Just t ->
                                    case List.filter (\k -> k.id == ref.keyId) t.keyframes of
                                        k :: _ ->
                                            let
                                                newTrack =
                                                    case field of
                                                        "key.frame" ->
                                                            Keyframe.setFrame k.id (max 0 (round value)) t

                                                        "key.value" ->
                                                            case k.value of
                                                                Scalar _ ->
                                                                    Keyframe.setValue k.id (Scalar (clampFor t.target.property value)) t

                                                                Angle _ ->
                                                                    Keyframe.setValue k.id (Angle value) t

                                                                _ ->
                                                                    t

                                                        "key.value.x" ->
                                                            case k.value of
                                                                PointValue p ->
                                                                    Keyframe.setValue k.id (PointValue { p | x = value }) t

                                                                SizeValue p ->
                                                                    Keyframe.setValue k.id (SizeValue { p | x = max 0 value }) t

                                                                _ ->
                                                                    t

                                                        "key.value.y" ->
                                                            case k.value of
                                                                PointValue p ->
                                                                    Keyframe.setValue k.id (PointValue { p | y = value }) t

                                                                SizeValue p ->
                                                                    Keyframe.setValue k.id (SizeValue { p | y = max 0 value }) t

                                                                _ ->
                                                                    t

                                                        _ ->
                                                            Keyframe.setEasing k.id (updateEasing field value k.easing) t
                                            in
                                            Scene.upsertTrack newTrack acc

                                        [] ->
                                            acc

                                Nothing ->
                                    acc
                        )
                        s
                        refs
            in
            Edit.commitCoalesced ("key:" ++ field) "Edit keyframe" (Document.updateScene scene.id update) model

        _ ->
            pure model


updateEasing : String -> Float -> Easing -> Easing
updateEasing field value easing =
    case field of
        "key.x1" ->
            withBez (\b -> { b | x1 = clamp 0 1 value }) easing

        "key.y1" ->
            withBez (\b -> { b | y1 = value }) easing

        "key.x2" ->
            withBez (\b -> { b | x2 = clamp 0 1 value }) easing

        "key.y2" ->
            withBez (\b -> { b | y2 = value }) easing

        "key.mass" ->
            withSpring (\s -> { s | mass = max 0.01 value }) easing

        "key.stiffness" ->
            withSpring (\s -> { s | stiffness = max 0.01 value }) easing

        "key.damping" ->
            withSpring (\s -> { s | damping = max 0 value }) easing

        "key.velocity" ->
            withSpring (\s -> { s | velocity = value }) easing

        _ ->
            easing


withBez : ({ x1 : Float, y1 : Float, x2 : Float, y2 : Float } -> { x1 : Float, y1 : Float, x2 : Float, y2 : Float }) -> Easing -> Easing
withBez f easing =
    case bez easing of
        Just b ->
            let
                n =
                    f b
            in
            CubicBezier n.x1 n.y1 n.x2 n.y2

        Nothing ->
            easing


withSpring : (Domain.Easing.SpringParams -> Domain.Easing.SpringParams) -> Easing -> Easing
withSpring f easing =
    case easing of
        Spring s ->
            Spring (f s)

        _ ->
            Spring (f Domain.Easing.defaultSpring)


clampFor : PropertyPath -> Float -> Float
clampFor property v =
    case property of
        Opacity ->
            clamp 0 1 v

        MotionProgress ->
            clamp 0 1 v

        StrokeWidth ->
            max 0 v

        RectCornerRadius ->
            max 0 v

        FontSize ->
            max 0.1 v

        BlurRadius ->
            max 0 v

        _ ->
            v


setProp : Model -> NodeId -> PropertyPath -> PropertyValue -> Scene -> Scene
setProp model id property value scene =
    Tuple.first (Edit.setAnimatedProperty model id property value scene)


applyToSelection : String -> (Model -> NodeId -> Scene -> Scene) -> Model -> Update
applyToSelection description f model =
    case Model.activeScene model of
        Just scene ->
            Edit.commitCoalesced description description (Document.updateScene scene.id (\s -> List.foldl (f model) s (Edit.selection model))) model

        Nothing ->
            pure model


applyNodeNumber : String -> Float -> Model -> Update
applyNodeNumber field value model =
    let
        setPoint property _ set m id s =
            case Dict.get id s.nodes |> Maybe.andThen (\n -> evaluated m s n property) of
                Just (PointValue p) ->
                    setProp m id property (PointValue (set value p)) s

                _ ->
                    s
    in
    case field of
        "pos.x" ->
            applyToSelection "Position" (setPoint Position .x (\v p -> { p | x = v })) model

        "pos.y" ->
            applyToSelection "Position" (setPoint Position .y (\v p -> { p | y = v })) model

        "rot" ->
            applyToSelection "Rotation" (\m id s -> setProp m id Rotation (Angle value) s) model

        "scale.x" ->
            applyToSelection "Scale" (setPoint Scale .x (\v p -> { p | x = v / 100 })) model

        "scale.y" ->
            applyToSelection "Scale" (setPoint Scale .y (\v p -> { p | y = v / 100 })) model

        "skew.x" ->
            applyToSelection "Skew" (setPoint Skew .x (\v p -> { p | x = v })) model

        "skew.y" ->
            applyToSelection "Skew" (setPoint Skew .y (\v p -> { p | y = v })) model

        "pivot.x" ->
            applyToSelection "Pivot" (setPoint Pivot .x (\v p -> { p | x = v })) model

        "pivot.y" ->
            applyToSelection "Pivot" (setPoint Pivot .y (\v p -> { p | y = v })) model

        "opacity" ->
            applyToSelection "Opacity" (\m id s -> setProp m id Opacity (Scalar (clamp 0 1 (value / 100))) s) model

        "corner" ->
            applyToSelection "Corner radius" (\m id s -> setProp m id RectCornerRadius (Scalar (max 0 value)) s) model

        "stroke.width" ->
            applyToSelection "Stroke width" (\m id s -> setProp m id StrokeWidth (Scalar (max 0 value)) s) model

        "dash.offset" ->
            applyToSelection "Dash offset" (\m id s -> setProp m id DashOffset (Scalar value) s) model

        "font.size" ->
            applyToSelection "Font size" (\m id s -> setProp m id FontSize (Scalar (max 0.1 value)) s) model

        "blur" ->
            applyToSelection "Blur" (\m id s -> setProp m id BlurRadius (Scalar (max 0 value)) s) model

        "progress" ->
            applyToSelection "Path progress" (\m id s -> setProp m id MotionProgress (Scalar (clamp 0 1 (value / 100))) s) model

        "size.w" ->
            applyToSelection "Resize" (resize True value) model

        "size.h" ->
            applyToSelection "Resize" (resize False value) model

        "letter" ->
            applyToSelection "Letter spacing"
                (\_ id s ->
                    updateGeometry id
                        (\g ->
                            case g of
                                Text t ->
                                    Text { t | letterSpacing = value }

                                other ->
                                    other
                        )
                        s
                )
                model

        "sides" ->
            applyToSelection "Sides"
                (\_ id s ->
                    updateGeometry id
                        (\g ->
                            case g of
                                Polygon p ->
                                    Polygon { p | sides = clamp 3 64 (round value) }

                                other ->
                                    other
                        )
                        s
                )
                model

        "polyradius" ->
            applyToSelection "Radius"
                (\_ id s ->
                    updateGeometry id
                        (\g ->
                            case g of
                                Polygon p ->
                                    Polygon { p | radius = max 0 value }

                                other ->
                                    other
                        )
                        s
                )
                model

        "inner" ->
            applyToSelection "Inner radius"
                (\_ id s ->
                    updateGeometry id
                        (\g ->
                            case g of
                                Polygon p ->
                                    Polygon { p | innerRadius = Just (max 0 value) }

                                other ->
                                    other
                        )
                        s
                )
                model

        "line.x2" ->
            applyToSelection "Line end"
                (\_ id s ->
                    updateGeometry id
                        (\g ->
                            case g of
                                Line l ->
                                    Line { l | end = { x = value, y = l.end.y } }

                                other ->
                                    other
                        )
                        s
                )
                model

        "line.y2" ->
            applyToSelection "Line end"
                (\_ id s ->
                    updateGeometry id
                        (\g ->
                            case g of
                                Line l ->
                                    Line { l | end = { x = l.end.x, y = value } }

                                other ->
                                    other
                        )
                        s
                )
                model

        "miter" ->
            applyToSelection "Miter limit"
                (\_ id s ->
                    Scene.updateNode id
                        (\n ->
                            let
                                st =
                                    n.stroke
                            in
                            { n | stroke = { st | miterLimit = max 1 value } }
                        )
                        s
                )
                model

        _ ->
            pure model


updateGeometry : NodeId -> (NodeGeometry -> NodeGeometry) -> Scene -> Scene
updateGeometry id f scene =
    Scene.updateNode id (\n -> { n | geometry = f n.geometry }) scene


{-| Width/height edits: geometry for primitives, scale for everything else.
-}
resize : Bool -> Float -> Model -> NodeId -> Scene -> Scene
resize isWidth value model id scene =
    case Dict.get id scene.nodes of
        Nothing ->
            scene

        Just node ->
            let
                v =
                    max 0 value
            in
            case node.geometry of
                Rectangle _ ->
                    case evaluated model scene node RectSize of
                        Just (SizeValue s) ->
                            setProp model
                                id
                                RectSize
                                (SizeValue
                                    (if isWidth then
                                        { s | x = v }

                                     else
                                        { s | y = v }
                                    )
                                )
                                scene

                        _ ->
                            scene

                Ellipse _ ->
                    case evaluated model scene node EllipseRadii of
                        Just (SizeValue r) ->
                            setProp model
                                id
                                EllipseRadii
                                (SizeValue
                                    (if isWidth then
                                        { r | x = v / 2 }

                                     else
                                        { r | y = v / 2 }
                                    )
                                )
                                scene

                        _ ->
                            scene

                RasterImage i ->
                    Scene.setNode
                        { node
                            | geometry =
                                RasterImage
                                    { i
                                        | size =
                                            if isWidth then
                                                { x = v, y = i.size.y }

                                            else
                                                { x = i.size.x, y = v }
                                    }
                        }
                        scene

                _ ->
                    case ( sizeOf model node, evaluated model scene node Scale ) of
                        ( Just current, Just (PointValue sc) ) ->
                            let
                                factor =
                                    if isWidth then
                                        if current.x > 0 then
                                            v / current.x

                                        else
                                            1

                                    else if current.y > 0 then
                                        v / current.y

                                    else
                                        1
                            in
                            setProp model
                                id
                                Scale
                                (PointValue
                                    (if isWidth then
                                        { sc | x = sc.x * factor }

                                     else
                                        { sc | y = sc.y * factor }
                                    )
                                )
                                scene

                        _ ->
                            scene
