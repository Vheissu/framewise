module Editor.CanvasView exposing (pointerDecoder, view)

{-| The scene canvas: artwork SVG rendered through the shared renderer, an
editor-only overlay SVG for selection, handles, anchors, snapping, motion
paths and onion skins, plus rulers.
-}

import App.Canvas as Canvas
import App.Edit as Edit
import App.Model as Model exposing (Gesture(..), Model, Tool(..))
import App.Msg exposing (Msg(..), PointerEvent)
import Dict
import Domain.Document
import Domain.Evaluate as Evaluate exposing (ResolvedScene)
import Domain.Matrix as Matrix
import Domain.Node exposing (NodeGeometry(..))
import Domain.Path as Path
import Domain.Scene as Scene exposing (Scene)
import Domain.Vec2 as Vec2 exposing (Vec2)
import Html exposing (Html, div, span, text)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import Render.Scene as Render
import Render.SvgDoc as SvgDoc
import Svg
import Svg.Attributes as SA
import Svg.Keyed


view : Model -> Html Msg
view model =
    case ( Model.activeDoc model, Model.activeScene model ) of
        ( Just open, Just scene ) ->
            let
                view_ =
                    Model.activeView model

                frame =
                    Edit.currentFrame model

                resolved =
                    Evaluate.evaluateScene open.document scene.id frame

                e =
                    model.editor

                cursorClass =
                    case e.tool of
                        HandTool ->
                            "cursor-grab"

                        ZoomTool ->
                            "cursor-zoom"

                        PenTool ->
                            "cursor-pen"

                        MotionPathTool ->
                            "cursor-pen"

                        TextTool ->
                            "cursor-text"

                        SelectTool ->
                            "cursor-default"

                        _ ->
                            "cursor-cross"

                transform =
                    "matrix(" ++ String.fromFloat view_.zoom ++ " 0 0 " ++ String.fromFloat view_.zoom ++ " " ++ String.fromFloat view_.pan.x ++ " " ++ String.fromFloat view_.pan.y ++ ")"
            in
            div [ A.class "canvas-wrap" ]
                [ if e.showRulers then
                    rulers model scene

                  else
                    text ""
                , Html.node "fw-rect-host"
                    [ A.class ("canvas-host " ++ cursorClass)
                    , A.classList [ ( "panning", e.spaceHeld || e.tool == HandTool ), ( "checker", e.checkerboard ) ]
                    , A.id "fw-canvas"
                    , A.tabindex 0
                    , A.attribute "aria-label" "Scene canvas"
                    , A.attribute "role" "application"
                    , E.on "fwrect" (D.map CanvasRect rectDecoder)
                    , E.on "pointerdown" (D.map CanvasPointerDown pointerDecoder)
                    , E.on "pointermove" (D.map CanvasPointerMove pointerDecoder)
                    , E.on "pointerup" (D.map CanvasPointerUp pointerDecoder)
                    , E.on "dblclick" (D.map CanvasDoubleClick pointerDecoder)
                    , E.custom "wheel" (D.map (\w -> { message = CanvasWheel w, stopPropagation = True, preventDefault = True }) wheelDecoder)
                    , E.custom "contextmenu" (D.succeed { message = NoOp, stopPropagation = False, preventDefault = True })
                    , E.onFocus (SetFocusContext Model.CanvasFocus)
                    ]
                    [ Svg.svg [ SA.class "artwork", A.attribute "aria-hidden" "true" ]
                        [ Svg.defs []
                            [ Svg.pattern [ SA.id "fw-checker", SA.width "16", SA.height "16", SA.patternUnits "userSpaceOnUse" ]
                                [ Svg.rect [ SA.width "8", SA.height "8", SA.fill "var(--checker-a)" ] []
                                , Svg.rect [ SA.x "8", SA.y "8", SA.width "8", SA.height "8", SA.fill "var(--checker-a)" ] []
                                , Svg.rect [ SA.x "8", SA.width "8", SA.height "8", SA.fill "var(--checker-b)" ] []
                                , Svg.rect [ SA.y "8", SA.width "8", SA.height "8", SA.fill "var(--checker-b)" ] []
                                ]
                            ]
                        , Svg.g [ SA.transform transform ]
                            ([ Svg.rect
                                [ SA.width (String.fromFloat scene.width)
                                , SA.height (String.fromFloat scene.height)
                                , SA.fill
                                    (if e.checkerboard then
                                        "url(#fw-checker)"

                                     else
                                        "var(--artboard-bg)"
                                    )
                                , SA.class "artboard-bg"
                                ]
                                []
                             ]
                                ++ onionSkins model open.document scene frame
                                ++ (case resolved of
                                        Just r ->
                                            [ Svg.g
                                                [ SA.class
                                                    (if e.outlineMode then
                                                        "scene-root outline-mode"

                                                     else
                                                        "scene-root"
                                                    )
                                                ]
                                                (List.map SvgDoc.toHtml
                                                    (Render.renderSceneBody
                                                        { idPrefix = "fw-" ++ shortId scene.id
                                                        , assetUrls = open.assetUrls
                                                        , includeBackground = True
                                                        , includeIds = True
                                                        , title = Nothing
                                                        , description = Nothing
                                                        , standalone = False
                                                        }
                                                        r
                                                    )
                                                )
                                            ]

                                        Nothing ->
                                            []
                                   )
                            )
                        ]
                    , Svg.svg [ SA.class "overlay", A.attribute "aria-hidden" "true" ]
                        (overlay model scene resolved)
                    , if e.isolation /= Nothing then
                        div [ A.class "isolation-badge" ]
                            [ span [] [ text ("Editing inside " ++ (e.isolation |> Maybe.andThen (\id -> Dict.get id scene.nodes) |> Maybe.map .name |> Maybe.withDefault "group")) ]
                            , Html.button [ A.class "btn small", E.onClick ExitIsolation ] [ text "Exit" ]
                            ]

                      else
                        text ""
                    , if e.penDraft /= Nothing then
                        div [ A.class "canvas-hint" ] [ text "Click to add anchors, drag for curves. Enter to finish, Escape to cancel." ]

                      else
                        emptyHint model scene
                    ]
                ]

        _ ->
            div [ A.class "canvas-wrap" ] []


shortId : String -> String
shortId id =
    String.left 8 (String.filter Char.isAlphaNum id)


emptyHint : Model -> Scene -> Html Msg
emptyHint model scene =
    if Dict.isEmpty scene.nodes then
        div [ A.class "canvas-empty" ]
            [ span [] [ text "The scene is empty." ]
            , Html.button [ A.class "btn small", E.onClick (ChooseTool RectTool) ] [ text "Draw a shape (R)" ]
            , Html.button [ A.class "btn small", E.onClick ImportSvg ] [ text "Import SVG" ]
            , let
                _ =
                    model
              in
              text ""
            ]

    else
        text ""


rectDecoder : D.Decoder { left : Float, top : Float, width : Float, height : Float }
rectDecoder =
    D.at [ "detail" ]
        (D.map4 (\l t w h -> { left = l, top = t, width = w, height = h })
            (D.field "left" D.float)
            (D.field "top" D.float)
            (D.field "width" D.float)
            (D.field "height" D.float)
        )


{-| Decode pointer position, modifiers and what was hit: a node wrapper id
(`fw-<scene>-node-<id>`), a handle (`data-fw-handle`) or an anchor
(`data-fw-anchor`).
-}
pointerDecoder : D.Decoder PointerEvent
pointerDecoder =
    let
        dataset name =
            D.oneOf
                [ D.at [ "target", "dataset", name ] D.string |> D.map Just
                , D.succeed Nothing
                ]

        idAt path =
            D.oneOf [ D.at path D.string, D.succeed "" ]

        nodeId =
            D.map4
                (\a b c d ->
                    [ a, b, c, d ]
                        |> List.filterMap extractNodeId
                        |> List.head
                )
                (idAt [ "target", "id" ])
                (idAt [ "target", "parentNode", "id" ])
                (idAt [ "target", "parentNode", "parentNode", "id" ])
                (idAt [ "target", "parentNode", "parentNode", "parentNode", "id" ])
    in
    D.succeed PointerEvent
        |> andMap (D.field "clientX" D.float)
        |> andMap (D.field "clientY" D.float)
        |> andMap (D.oneOf [ D.field "button" D.int, D.succeed 0 ])
        |> andMap (D.field "shiftKey" D.bool)
        |> andMap (D.field "altKey" D.bool)
        |> andMap (D.field "ctrlKey" D.bool)
        |> andMap (D.field "metaKey" D.bool)
        |> andMap nodeId
        |> andMap (dataset "fwHandle")
        |> andMap (dataset "fwAnchor")
        |> andMap (D.oneOf [ D.field "detail" D.int, D.succeed 1 ])


extractNodeId : String -> Maybe String
extractNodeId id =
    case String.indexes "-node-" id of
        i :: _ ->
            if String.startsWith "fw-" id then
                Just (String.dropLeft (i + 6) id)

            else
                Nothing

        [] ->
            Nothing


andMap : D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
andMap =
    D.map2 (|>)


wheelDecoder : D.Decoder App.Msg.WheelEvent
wheelDecoder =
    D.map7 App.Msg.WheelEvent
        (D.field "clientX" D.float)
        (D.field "clientY" D.float)
        (D.field "deltaX" D.float)
        (D.field "deltaY" D.float)
        (D.field "ctrlKey" D.bool)
        (D.field "metaKey" D.bool)
        (D.field "shiftKey" D.bool)



-- ONION SKIN


onionSkins : Model -> Domain.Document.Document -> Scene -> Float -> List (Svg.Svg Msg)
onionSkins model doc scene frame =
    let
        e =
            model.editor
    in
    if not e.onionSkin then
        []

    else
        let
            frames =
                (List.range 1 e.onionBefore |> List.map (\i -> ( frame - toFloat i, "var(--onion-before)", i )))
                    ++ (List.range 1 e.onionAfter |> List.map (\i -> ( frame + toFloat i, "var(--onion-after)", i )))

            ghost ( fr, color, distance ) =
                if fr < 0 || fr > toFloat scene.durationFrames then
                    Nothing

                else
                    Evaluate.evaluateScene doc scene.id fr
                        |> Maybe.map
                            (\r ->
                                Svg.g
                                    [ SA.class "onion"
                                    , SA.opacity (String.fromFloat (0.5 / toFloat distance))
                                    , SA.style ("--onion-color:" ++ color)
                                    , SA.pointerEvents "none"
                                    ]
                                    (List.map SvgDoc.toHtml
                                        (Render.renderSceneBody
                                            { idPrefix = "onion" ++ String.fromInt (round fr)
                                            , assetUrls = Dict.empty
                                            , includeBackground = False
                                            , includeIds = False
                                            , title = Nothing
                                            , description = Nothing
                                            , standalone = False
                                            }
                                            r
                                        )
                                    )
                            )
        in
        List.filterMap ghost frames



-- OVERLAY


overlay : Model -> Scene -> Maybe ResolvedScene -> List (Svg.Svg Msg)
overlay model scene resolved =
    let
        e =
            model.editor

        view_ =
            Model.activeView model

        toScreen =
            Canvas.toScreen model

        sel =
            Edit.selection model

        artboard =
            let
                a =
                    toScreen Vec2.zero

                b =
                    toScreen { x = scene.width, y = scene.height }
            in
            Svg.rect [ SA.x (f a.x), SA.y (f a.y), SA.width (f (b.x - a.x)), SA.height (f (b.y - a.y)), SA.class "artboard-outline" ] []

        grid =
            if e.showGrid then
                gridLines model scene

            else
                []

        hoverOutline =
            case ( e.hover, resolved ) of
                ( Just id, Just r ) ->
                    if List.member id sel || e.gesture /= NoGesture then
                        []

                    else
                        case Dict.get id r.byId |> Maybe.andThen (Evaluate.worldBounds r) of
                            Just b ->
                                [ boundsRect toScreen b "hover-outline" ]

                            Nothing ->
                                []

                _ ->
                    []

        selectionOverlay =
            case resolved of
                Just r ->
                    selectionHandles model r sel

                Nothing ->
                    []

        marquee =
            case e.gesture of
                Marquee g ->
                    [ marqueeRect toScreen g.start g.current "marquee" ]

                ZoomMarquee g ->
                    [ marqueeRect toScreen g.start g.current "marquee" ]

                DrawShape g ->
                    [ marqueeRect toScreen g.start g.current "draw-preview" ]

                _ ->
                    []

        snapLines =
            case e.gesture of
                DragMove g ->
                    List.map
                        (\( vertical, pos ) ->
                            if vertical then
                                let
                                    x =
                                        (toScreen { x = pos, y = 0 }).x
                                in
                                Svg.line [ SA.x1 (f x), SA.x2 (f x), SA.y1 "0", SA.y2 "100%", SA.class "snap-line" ] []

                            else
                                let
                                    y =
                                        (toScreen { x = 0, y = pos }).y
                                in
                                Svg.line [ SA.y1 (f y), SA.y2 (f y), SA.x1 "0", SA.x2 "100%", SA.class "snap-line" ] []
                        )
                        g.snapLines

                _ ->
                    []

        motionPaths =
            if e.showMotionPaths then
                case resolved of
                    Just r ->
                        motionPathOverlay model scene r

                    Nothing ->
                        []

            else
                []

        pen =
            penPreview model

        anchors =
            if e.tool == DirectSelectTool then
                case resolved of
                    Just r ->
                        List.concatMap (anchorOverlay model r) sel

                    Nothing ->
                        []

            else
                []

        pivot =
            case ( resolved, sel ) of
                ( Just r, [ id ] ) ->
                    case ( Dict.get id r.byId, Dict.get id scene.nodes ) of
                        ( Just res, Just node ) ->
                            let
                                p =
                                    toScreen (Matrix.apply res.worldMatrix node.transform.pivot)
                            in
                            [ Svg.g [ SA.class "pivot-marker", SA.transform ("translate(" ++ f p.x ++ " " ++ f p.y ++ ")") ]
                                [ Svg.circle [ SA.r "5" ] [], Svg.path [ SA.d "M-9 0 H9 M0 -9 V9" ] [] ]
                            ]

                        _ ->
                            []

                _ ->
                    []

        _ =
            view_
    in
    grid ++ [ artboard ] ++ motionPaths ++ hoverOutline ++ selectionOverlay ++ anchors ++ pivot ++ pen ++ marquee ++ snapLines


f : Float -> String
f v =
    String.fromFloat (toFloat (round (v * 100)) / 100)


boundsRect : (Vec2 -> Vec2) -> { minX : Float, minY : Float, maxX : Float, maxY : Float } -> String -> Svg.Svg Msg
boundsRect toScreen b cls =
    let
        a =
            toScreen { x = b.minX, y = b.minY }

        c =
            toScreen { x = b.maxX, y = b.maxY }
    in
    Svg.rect [ SA.x (f a.x), SA.y (f a.y), SA.width (f (max 0 (c.x - a.x))), SA.height (f (max 0 (c.y - a.y))), SA.class cls ] []


marqueeRect : (Vec2 -> Vec2) -> Vec2 -> Vec2 -> String -> Svg.Svg Msg
marqueeRect toScreen p q cls =
    let
        a =
            toScreen p

        b =
            toScreen q
    in
    Svg.rect
        [ SA.x (f (min a.x b.x))
        , SA.y (f (min a.y b.y))
        , SA.width (f (abs (b.x - a.x)))
        , SA.height (f (abs (b.y - a.y)))
        , SA.class cls
        ]
        []


gridLines : Model -> Scene -> List (Svg.Svg Msg)
gridLines model scene =
    let
        spacing =
            max 1 model.preferences.gridSpacing

        view_ =
            Model.activeView model

        toScreen =
            Canvas.toScreen model
    in
    if spacing * view_.zoom < 6 then
        []

    else
        let
            xs =
                List.range 0 (floor (scene.width / spacing)) |> List.map (\i -> toFloat i * spacing)

            ys =
                List.range 0 (floor (scene.height / spacing)) |> List.map (\i -> toFloat i * spacing)

            a =
                toScreen Vec2.zero

            b =
                toScreen { x = scene.width, y = scene.height }
        in
        List.map (\x -> Svg.line [ SA.x1 (f (toScreen { x = x, y = 0 }).x), SA.x2 (f (toScreen { x = x, y = 0 }).x), SA.y1 (f a.y), SA.y2 (f b.y), SA.class "grid-line" ] []) xs
            ++ List.map (\y -> Svg.line [ SA.y1 (f (toScreen { x = 0, y = y }).y), SA.y2 (f (toScreen { x = 0, y = y }).y), SA.x1 (f a.x), SA.x2 (f b.x), SA.class "grid-line" ] []) ys


selectionHandles : Model -> ResolvedScene -> List String -> List (Svg.Svg Msg)
selectionHandles model resolved sel =
    let
        toScreen =
            Canvas.toScreen model

        boundsList =
            List.filterMap (\id -> Dict.get id resolved.byId |> Maybe.andThen (Evaluate.worldBounds resolved)) sel

        union =
            case boundsList of
                [] ->
                    Nothing

                first :: rest ->
                    Just (List.foldl (\b acc -> { minX = min acc.minX b.minX, minY = min acc.minY b.minY, maxX = max acc.maxX b.maxX, maxY = max acc.maxY b.maxY }) first rest)

        showHandles =
            model.editor.tool == SelectTool || model.editor.tool == PivotTool
    in
    case union of
        Nothing ->
            []

        Just b ->
            let
                a =
                    toScreen { x = b.minX, y = b.minY }

                c =
                    toScreen { x = b.maxX, y = b.maxY }

                cx =
                    (a.x + c.x) / 2

                cy =
                    (a.y + c.y) / 2

                handle code x y =
                    Svg.rect
                        [ SA.x (f (x - 4))
                        , SA.y (f (y - 4))
                        , SA.width "8"
                        , SA.height "8"
                        , SA.class ("handle handle-" ++ code)
                        , A.attribute "data-fw-handle" code
                        ]
                        []

                individual =
                    if List.length boundsList > 1 then
                        List.map (\ib -> boundsRect toScreen ib "selection-child") boundsList

                    else
                        []
            in
            individual
                ++ [ Svg.rect [ SA.x (f a.x), SA.y (f a.y), SA.width (f (c.x - a.x)), SA.height (f (c.y - a.y)), SA.class "selection-outline" ] [] ]
                ++ (if showHandles then
                        [ Svg.line [ SA.x1 (f cx), SA.y1 (f a.y), SA.x2 (f cx), SA.y2 (f (a.y - 22)), SA.class "rotate-stem" ] []
                        , Svg.circle [ SA.cx (f cx), SA.cy (f (a.y - 22)), SA.r "5", SA.class "handle handle-rotate", A.attribute "data-fw-handle" "rotate" ] []
                        , handle "nw" a.x a.y
                        , handle "n" cx a.y
                        , handle "ne" c.x a.y
                        , handle "e" c.x cy
                        , handle "se" c.x c.y
                        , handle "s" cx c.y
                        , handle "sw" a.x c.y
                        , handle "w" a.x cy
                        ]

                    else
                        []
                   )
                ++ [ Svg.text_ [ SA.x (f a.x), SA.y (f (c.y + 16)), SA.class "selection-size" ]
                        [ Svg.text (f (b.maxX - b.minX) ++ " × " ++ f (b.maxY - b.minY)) ]
                   ]


anchorOverlay : Model -> ResolvedScene -> String -> List (Svg.Svg Msg)
anchorOverlay model resolved nodeId =
    case Dict.get nodeId resolved.byId of
        Nothing ->
            []

        Just res ->
            case res.geometry of
                Path geometry ->
                    let
                        toScreen p =
                            Canvas.toScreen model (Matrix.apply res.worldMatrix p)

                        outline =
                            Svg.path [ SA.d (Path.serialize (Path.transformGeometry res.worldMatrix geometry)), SA.class "path-outline", SA.transform (viewportTransform model) ] []

                        anchorEls =
                            Path.anchors geometry
                                |> List.concatMap
                                    (\anchor ->
                                        let
                                            p =
                                                toScreen anchor.point

                                            code =
                                                "a:" ++ nodeId ++ ":" ++ String.fromInt anchor.subpath ++ ":" ++ String.fromInt anchor.index

                                            handleEl which hp =
                                                let
                                                    h =
                                                        toScreen hp
                                                in
                                                [ Svg.line [ SA.x1 (f p.x), SA.y1 (f p.y), SA.x2 (f h.x), SA.y2 (f h.y), SA.class "anchor-stem" ] []
                                                , Svg.circle [ SA.cx (f h.x), SA.cy (f h.y), SA.r "3.5", SA.class "anchor-handle", A.attribute "data-fw-anchor" ("h:" ++ which ++ ":" ++ nodeId ++ ":" ++ String.fromInt anchor.subpath ++ ":" ++ String.fromInt anchor.index) ] []
                                                ]
                                        in
                                        (anchor.handleIn |> Maybe.map (handleEl "in") |> Maybe.withDefault [])
                                            ++ (anchor.handleOut |> Maybe.map (handleEl "out") |> Maybe.withDefault [])
                                            ++ [ Svg.rect [ SA.x (f (p.x - 3.5)), SA.y (f (p.y - 3.5)), SA.width "7", SA.height "7", SA.class "anchor", A.attribute "data-fw-anchor" code ] [] ]
                                    )
                    in
                    outline :: anchorEls

                _ ->
                    []


viewportTransform : Model -> String
viewportTransform model =
    let
        v =
            Model.activeView model
    in
    "matrix(" ++ String.fromFloat v.zoom ++ " 0 0 " ++ String.fromFloat v.zoom ++ " " ++ String.fromFloat v.pan.x ++ " " ++ String.fromFloat v.pan.y ++ ")"


motionPathOverlay : Model -> Scene -> ResolvedScene -> List (Svg.Svg Msg)
motionPathOverlay model scene resolved =
    Dict.values scene.nodes
        |> List.filterMap
            (\node ->
                node.motion
                    |> Maybe.andThen (\m -> Dict.get m.pathId scene.motionPaths)
                    |> Maybe.map
                        (\mp ->
                            let
                                parentWorld =
                                    node.parentId
                                        |> Maybe.andThen (\pid -> Dict.get pid resolved.byId)
                                        |> Maybe.map .worldMatrix
                                        |> Maybe.withDefault Matrix.identity

                                world =
                                    Matrix.multiply parentWorld (Matrix.translation node.transform.translation.x node.transform.translation.y)

                                d =
                                    Path.serialize (Path.transformGeometry world mp.geometry)

                                selected =
                                    List.member node.id (Edit.selection model)
                            in
                            Svg.path
                                [ SA.d d
                                , SA.class
                                    (if selected then
                                        "motion-path selected"

                                     else
                                        "motion-path"
                                    )
                                , SA.transform (viewportTransform model)
                                , SA.pointerEvents "none"
                                ]
                                []
                        )
            )


penPreview : Model -> List (Svg.Svg Msg)
penPreview model =
    case model.editor.penDraft of
        Nothing ->
            []

        Just draft ->
            let
                geometry =
                    { subpaths = [ { start = draft.subpathStart, segments = draft.segments, closed = False } ] }

                start =
                    Canvas.toScreen model draft.subpathStart

                anchorsEls =
                    Path.anchors geometry
                        |> List.map
                            (\a ->
                                let
                                    p =
                                        Canvas.toScreen model a.point
                                in
                                Svg.rect [ SA.x (f (p.x - 3)), SA.y (f (p.y - 3)), SA.width "6", SA.height "6", SA.class "anchor" ] []
                            )

                handleLine =
                    case ( draft.lastHandle, List.reverse draft.segments ) of
                        ( Just h, seg :: _ ) ->
                            let
                                anchor =
                                    case seg of
                                        Path.LineTo e ->
                                            e

                                        Path.CubicTo _ _ e ->
                                            e

                                a =
                                    Canvas.toScreen model anchor

                                hs =
                                    Canvas.toScreen model h

                                mirrored =
                                    Canvas.toScreen model (Vec2.sub (Vec2.scale 2 anchor) h)
                            in
                            [ Svg.line [ SA.x1 (f mirrored.x), SA.y1 (f mirrored.y), SA.x2 (f hs.x), SA.y2 (f hs.y), SA.class "anchor-stem" ] []
                            , Svg.circle [ SA.cx (f hs.x), SA.cy (f hs.y), SA.r "3.5", SA.class "anchor-handle" ] []
                            , Svg.circle [ SA.cx (f mirrored.x), SA.cy (f mirrored.y), SA.r "3.5", SA.class "anchor-handle" ] []
                            , Svg.circle [ SA.cx (f a.x), SA.cy (f a.y), SA.r "1", SA.class "anchor" ] []
                            ]

                        ( Just h, [] ) ->
                            let
                                hs =
                                    Canvas.toScreen model h
                            in
                            [ Svg.line [ SA.x1 (f start.x), SA.y1 (f start.y), SA.x2 (f hs.x), SA.y2 (f hs.y), SA.class "anchor-stem" ] [] ]

                        _ ->
                            []
            in
            Svg.path [ SA.d (Path.serialize geometry), SA.class "pen-preview", SA.transform (viewportTransform model) ] []
                :: anchorsEls
                ++ handleLine



-- RULERS


rulers : Model -> Scene -> Html Msg
rulers model scene =
    let
        view_ =
            Model.activeView model

        rect =
            model.editor.canvasRect

        stepFor zoom =
            let
                candidates =
                    [ 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000 ]
            in
            candidates |> List.filter (\s -> s * zoom >= 48) |> List.head |> Maybe.withDefault 5000

        step =
            stepFor view_.zoom

        ticks axisLen pan =
            let
                first =
                    toFloat (floor (-pan / view_.zoom / step)) * step

                count =
                    ceiling (axisLen / view_.zoom / step) + 2
            in
            List.range 0 count |> List.map (\i -> first + toFloat i * step)

        _ =
            scene
    in
    div [ A.class "rulers" ]
        [ div [ A.class "ruler ruler-h" ]
            (List.map
                (\v ->
                    let
                        x =
                            view_.pan.x + v * view_.zoom
                    in
                    span [ A.class "ruler-tick", A.style "left" (f x ++ "px") ] [ text (String.fromInt (round v)) ]
                )
                (ticks rect.width view_.pan.x)
            )
        , div [ A.class "ruler ruler-v" ]
            (List.map
                (\v ->
                    let
                        y =
                            view_.pan.y + v * view_.zoom
                    in
                    span [ A.class "ruler-tick", A.style "top" (f y ++ "px") ] [ text (String.fromInt (round v)) ]
                )
                (ticks rect.height view_.pan.y)
            )
        , div [ A.class "ruler-corner" ] []
        ]
