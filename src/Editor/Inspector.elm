module Editor.Inspector exposing (view)

{-| Right panel: context-sensitive properties for the scene, a node, a
multi-selection or selected keyframes. Every animatable field carries a
keyframe diamond showing whether the property is animated and whether a key
sits at the playhead.
-}

import App.Canvas as Canvas
import App.Edit as Edit
import App.Fields as Fields
import App.Model as Model exposing (Model)
import App.Msg exposing (Msg(..))
import Dict
import Domain.Color as Color
import Domain.Easing as Easing exposing (Easing(..))
import Domain.Evaluate
import Domain.Fps as Fps
import Domain.Keyframe as Keyframe
import Domain.Node as Node exposing (Node, NodeGeometry(..))
import Domain.Paint as Paint exposing (Paint(..))
import Domain.Path
import Domain.Property as Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Export.Capability as Capability
import Export.Format
import Html exposing (Html, button, div, input, span, text, textarea)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import UI.Fields as UI
import UI.Icons as Icons
import UI.Picker as Picker


view : Model -> Html Msg
view model =
    let
        e =
            model.editor

        body =
            case ( Model.activeScene model, Edit.selectedNodes model, e.selectedKeys ) of
                ( Just scene, [], [] ) ->
                    sceneInspector model scene

                ( Just scene, [ node ], _ ) ->
                    nodeInspector model scene node

                ( Just scene, nodes, _ ) ->
                    multiInspector model scene nodes

                _ ->
                    text ""
    in
    div [ A.class "panel right-panel", A.style "width" (String.fromFloat e.rightWidth ++ "px") ]
        [ div [ A.class "splitter splitter-v", E.on "pointerdown" (D.map (SplitterDown "right") (D.field "clientX" D.float)), A.attribute "role" "separator", A.attribute "aria-orientation" "vertical" ] []
        , div [ A.class "panel-body inspector" ]
            [ body
            , keyframeInspector model
            ]
        ]



-- SCENE


sceneInspector : Model -> Scene -> Html Msg
sceneInspector model scene =
    let
        report =
            Capability.report Export.Format.AnimatedSvg scene
    in
    div []
        [ div [ A.class "inspector-header" ]
            [ span [ A.class "inspector-kind" ] [ text "Scene" ]
            , UI.textField model { id = "scene.name", label = "Scene name", value = scene.name, placeholder = "Scene name" }
            ]
        , UI.section model
            "scene.size"
            "Size"
            [ div [ A.class "field-grid" ]
                [ staticNumber "W" scene.width
                , staticNumber "H" scene.height
                ]
            , button [ A.class "btn small", E.onClick (RunCommand "file.sceneSettings") ] [ Icons.icon "settings", text "Scene Settings…" ]
            ]
        , UI.section model
            "scene.background"
            "Background"
            [ div [ A.class "field-row" ]
                [ UI.checkbox "Transparent" (scene.background == Scene.Transparent) SetSceneBackground
                , case scene.background of
                    Scene.SolidBackground c ->
                        Picker.swatchButton "Background colour" Model.BackgroundTarget (Just c)

                    Scene.Transparent ->
                        text ""
                ]
            ]
        , UI.section model
            "scene.timing"
            "Timing"
            [ div [ A.class "field-grid" ]
                [ staticText "FPS" (Fps.toLabel scene.fps)
                , staticText "Frames" (String.fromInt scene.durationFrames)
                , staticText "Length" (Fps.toTimecode scene.fps scene.durationFrames)
                ]
            , UI.select "Loop mode"
                (Scene.playbackModeToCode scene.playbackMode)
                [ ( "once", "Play once" ), ( "repeat", "Repeat" ), ( "pingpong", "Ping-pong" ) ]
                (SetSceneOption "playbackMode")
            , case scene.workRange of
                Just r ->
                    div [ A.class "field-row" ]
                        [ span [ A.class "field-label" ] [ text ("Work range " ++ String.fromInt r.start ++ "–" ++ String.fromInt r.end) ]
                        , button [ A.class "btn small", E.onClick (SetWorkRange Nothing) ] [ text "Clear" ]
                        ]

                Nothing ->
                    text ""
            ]
        , UI.section model
            "scene.accessibility"
            "Accessibility"
            [ textarea
                [ A.class "text-area"
                , A.placeholder "Scene description used as <desc> in exports"
                , A.value scene.description
                , A.attribute "aria-label" "Scene description"
                , E.onInput (SetSceneOption "description")
                ]
                []
            ]
        , UI.section model
            "scene.export"
            "Export readiness"
            [ div [ A.class "report-summary" ]
                [ span [ A.class "pill exact" ] [ text (String.fromInt report.exactCount ++ " exact") ]
                , span [ A.class "pill baked" ] [ text (String.fromInt report.bakedCount ++ " baked") ]
                , span [ A.class "pill unsupported" ] [ text (String.fromInt report.unsupportedCount ++ " unsupported") ]
                ]
            , span [ A.class "hint" ] [ text "For animated SVG (SMIL). Open Export for every target." ]
            ]
        , UI.section model
            "scene.meta"
            "Metadata"
            [ staticText "ID" scene.id
            , staticText "Layers" (String.fromInt (Dict.size scene.nodes))
            , staticText "Tracks" (String.fromInt (Dict.size scene.tracks))
            ]
        , emptyHint
        ]


emptyHint : Html Msg
emptyHint =
    div [ A.class "inspector-hint" ]
        [ text "Select a layer to edit its transform, appearance and animation. Click a diamond next to a value to add a keyframe at the playhead." ]


staticNumber : String -> Float -> Html Msg
staticNumber label v =
    div [ A.class "static-field" ] [ span [ A.class "num-label" ] [ text label ], span [ A.class "static-value" ] [ text (Fields.displayValue v) ] ]


staticText : String -> String -> Html Msg
staticText label v =
    div [ A.class "static-field" ] [ span [ A.class "num-label" ] [ text label ], span [ A.class "static-value", A.title v ] [ text v ] ]



-- NODE


nodeInspector : Model -> Scene -> Node -> Html Msg
nodeInspector model scene node =
    let
        parent =
            node.parentId |> Maybe.andThen (\p -> Dict.get p scene.nodes)
    in
    div []
        [ div [ A.class "inspector-header" ]
            [ span [ A.class "inspector-kind" ] [ Icons.icon (kindIcon node.geometry), text (Node.kindLabel node.geometry) ]
            , UI.textField model { id = "name", label = "Layer name", value = node.name, placeholder = "Layer name" }
            , div [ A.class "inspector-header-actions" ]
                [ case parent of
                    Just p ->
                        button [ A.class "btn small", E.onClick SelectParent, A.title ("Select parent " ++ p.name) ] [ Icons.icon "arrow-up", text p.name ]

                    Nothing ->
                        text ""
                , UI.iconButton { icon = iif node.hidden "eye-off" "eye", label = iif node.hidden "Show" "Hide", active = node.hidden, onClick = SetHidden node.id (not node.hidden), disabled = False }
                , UI.iconButton { icon = iif node.locked "lock" "unlock", label = iif node.locked "Unlock" "Lock", active = node.locked, onClick = SetLocked node.id (not node.locked), disabled = False }
                , UI.iconButton { icon = "duplicate", label = "Duplicate", active = False, onClick = DuplicateSelection, disabled = False }
                , UI.iconButton { icon = "trash", label = "Delete", active = False, onClick = DeleteSelection, disabled = False }
                ]
            ]
        , transformSection model scene node
        , geometrySection model scene node
        , appearanceSection model scene node
        , effectsSection model scene node
        , animationSection model scene node
        , exportSection model scene node
        ]


iif : Bool -> a -> a -> a
iif c a b =
    if c then
        a

    else
        b


kindIcon : NodeGeometry -> String
kindIcon g =
    case g of
        Rectangle _ ->
            "rect"

        Ellipse _ ->
            "ellipse"

        Line _ ->
            "line"

        Polygon _ ->
            "polygon"

        Path _ ->
            "path"

        Text _ ->
            "text"

        RasterImage _ ->
            "image"

        Group ->
            "group"

        ClippingGroup ->
            "clip"


{-| Keyframe diamond for a property: hollow when not animated, filled when a
key sits at the playhead, outlined-filled when animated elsewhere.
-}
diamond : Model -> Scene -> Node -> PropertyPath -> Html Msg
diamond model scene node property =
    let
        frame =
            round (Edit.currentFrame model)

        track =
            Scene.trackFor node.id property scene

        atPlayhead =
            track |> Maybe.andThen (Keyframe.keyAt frame) |> (/=) Nothing

        animated =
            track |> Maybe.map (\t -> not (List.isEmpty t.keyframes)) |> Maybe.withDefault False

        label =
            Property.pathLabel property
                ++ (if atPlayhead then
                        ": remove keyframe at playhead"

                    else
                        ": add keyframe at playhead"
                   )
    in
    if Node.supportsProperty node property then
        button
            [ A.class "diamond"
            , A.classList [ ( "animated", animated ), ( "at-playhead", atPlayhead ) ]
            , A.title label
            , A.attribute "aria-label" label
            , A.attribute "aria-pressed" (iif atPlayhead "true" "false")
            , E.onClick (ToggleKeyAt node.id property)
            ]
            [ Icons.icon (iif atPlayhead "diamond-filled" "diamond") ]

    else
        text ""


num : Model -> Scene -> Node -> String -> String -> Float -> String -> Maybe PropertyPath -> Html Msg
num model scene node id label step unit property =
    UI.numberField model
        { id = id
        , label = label
        , value = Fields.currentValue id model
        , step = step
        , unit = unit
        , animated = Maybe.map (diamond model scene node) property
        }


transformSection : Model -> Scene -> Node -> Html Msg
transformSection model scene node =
    UI.section model
        "node.transform"
        "Transform"
        [ div [ A.class "field-grid two" ]
            [ num model scene node "pos.x" "X" 1 "" (Just Position)
            , num model scene node "pos.y" "Y" 1 "" Nothing
            , num model scene node "size.w" "W" 1 "" sizeProperty
            , num model scene node "size.h" "H" 1 "" Nothing
            , num model scene node "rot" "Rotation" 1 "°" (Just Rotation)
            , num model scene node "opacity" "Opacity" 1 "%" (Just Opacity)
            , num model scene node "scale.x" "Scale X" 1 "%" (Just Scale)
            , num model scene node "scale.y" "Scale Y" 1 "%" Nothing
            , num model scene node "skew.x" "Skew X" 1 "°" (Just Skew)
            , num model scene node "skew.y" "Skew Y" 1 "°" Nothing
            , num model scene node "pivot.x" "Pivot X" 1 "" (Just Pivot)
            , num model scene node "pivot.y" "Pivot Y" 1 "" Nothing
            ]
        , div [ A.class "button-row" ]
            [ button [ A.class "btn small", E.onClick (FlipSelection True), A.title "Flip horizontal" ] [ Icons.icon "flip-h" ]
            , button [ A.class "btn small", E.onClick (FlipSelection False), A.title "Flip vertical" ] [ Icons.icon "flip-v" ]
            , button [ A.class "btn small", E.onClick (ChooseTool Model.PivotTool), A.title "Move pivot" ] [ Icons.icon "pivot", text "Pivot" ]
            , button [ A.class "btn small", E.onClick ResetTransform ] [ text "Reset" ]
            ]
        , let
            _ =
                sizeProperty
          in
          case node.geometry of
            Rectangle _ ->
                text ""

            Ellipse _ ->
                text ""

            _ ->
                text ""
        ]
        |> withSizeDiamond model scene node


sizeProperty : Maybe PropertyPath
sizeProperty =
    Nothing


{-| The W/H diamond depends on the node kind (RectSize or EllipseRadii).
-}
withSizeDiamond : Model -> Scene -> Node -> Html Msg -> Html Msg
withSizeDiamond _ _ _ html =
    html


geometrySection : Model -> Scene -> Node -> Html Msg
geometrySection model scene node =
    case node.geometry of
        Rectangle _ ->
            UI.section model
                "node.geometry"
                "Rectangle"
                [ div [ A.class "field-grid two" ]
                    [ num model scene node "corner" "Corner" 1 "" (Just RectCornerRadius)
                    , div [ A.class "num-field" ] [ span [ A.class "num-label" ] [ text "Size" ], span [ A.class "static-value" ] [ text "W × H above" ], diamond model scene node RectSize ]
                    ]
                , button [ A.class "btn small", E.onClick ConvertToPath ] [ Icons.icon "path", text "Convert to Path" ]
                ]

        Ellipse _ ->
            UI.section model
                "node.geometry"
                "Ellipse"
                [ div [ A.class "field-row" ] [ span [ A.class "field-label" ] [ text "Radii follow W × H" ], diamond model scene node EllipseRadii ]
                , button [ A.class "btn small", E.onClick ConvertToPath ] [ Icons.icon "path", text "Convert to Path" ]
                ]

        Line _ ->
            UI.section model
                "node.geometry"
                "Line"
                [ div [ A.class "field-grid two" ]
                    [ num model scene node "line.x2" "End X" 1 "" Nothing
                    , num model scene node "line.y2" "End Y" 1 "" Nothing
                    ]
                , button [ A.class "btn small", E.onClick ConvertToPath ] [ Icons.icon "path", text "Convert to Path" ]
                ]

        Polygon p ->
            UI.section model
                "node.geometry"
                (iif (p.innerRadius /= Nothing) "Star" "Polygon")
                [ div [ A.class "field-grid two" ]
                    ([ num model scene node "sides" "Sides" 1 "" Nothing
                     , num model scene node "polyradius" "Radius" 1 "" Nothing
                     ]
                        ++ (case p.innerRadius of
                                Just _ ->
                                    [ num model scene node "inner" "Inner" 1 "" Nothing ]

                                Nothing ->
                                    []
                           )
                    )
                , button [ A.class "btn small", E.onClick ConvertToPath ] [ Icons.icon "path", text "Convert to Path" ]
                ]

        Path g ->
            UI.section model
                "node.geometry"
                "Path"
                [ div [ A.class "field-row" ]
                    [ span [ A.class "field-label" ] [ text (String.fromInt (Domain.Path.anchorCount g) ++ " anchors · " ++ String.fromInt (List.length g.subpaths) ++ " subpath" ++ iif (List.length g.subpaths == 1) "" "s") ]
                    , diamond model scene node PathGeometryProp
                    ]
                , div [ A.class "button-row" ]
                    [ button [ A.class "btn small", E.onClick (ChooseTool Model.DirectSelectTool) ] [ Icons.icon "direct", text "Edit anchors" ]
                    , button [ A.class "btn small", E.onClick ToggleClosedPath ] [ text (iif (List.all .closed g.subpaths) "Open path" "Close path") ]
                    , button [ A.class "btn small", E.onClick ReversePath ] [ text "Reverse" ]
                    ]
                , span [ A.class "hint" ] [ text "Path keyframes morph when every key has the same anchor structure." ]
                ]

        Text t ->
            UI.section model
                "node.geometry"
                "Text"
                [ textarea
                    [ A.class "text-area"
                    , A.id "text-content"
                    , A.value (Dict.get "text.content" model.fieldDrafts |> Maybe.withDefault t.content)
                    , A.attribute "aria-label" "Text content"
                    , A.autofocus (model.editor.editingText == Just node.id)
                    , E.onInput (FieldInput "text.content")
                    , E.onBlur (FieldCommit "text.content")
                    ]
                    []
                , div [ A.class "field-row" ] [ span [ A.class "field-label" ] [ text "Content" ], diamond model scene node TextContent ]
                , UI.textField model { id = "font.family", label = "Font family", value = t.fontFamily, placeholder = "Font family" }
                , div [ A.class "field-grid two" ]
                    [ num model scene node "font.size" "Size" 1 "" (Just FontSize)
                    , num model scene node "letter" "Tracking" 0.5 "" Nothing
                    ]
                , div [ A.class "field-row" ]
                    [ UI.select "Weight" (String.fromInt t.fontWeight) [ ( "300", "Light" ), ( "400", "Regular" ), ( "500", "Medium" ), ( "600", "Semibold" ), ( "700", "Bold" ), ( "800", "Heavy" ) ] (SetTextOption node.id "weight")
                    , UI.select "Alignment" (Node.alignToCode t.align) [ ( "start", "Left" ), ( "middle", "Centre" ), ( "end", "Right" ) ] (SetTextOption node.id "align")
                    , UI.checkbox "Italic" t.italic (\v -> SetTextOption node.id "italic" (iif v "true" "false"))
                    ]
                , span [ A.class "hint" ] [ text "Text uses fonts on the viewing device. Exports warn about possible reflow." ]
                ]

        RasterImage i ->
            UI.section model
                "node.geometry"
                "Image"
                [ staticText "Asset" (Dict.get i.assetId (Model.activeDoc model |> Maybe.map (.document >> .assets) |> Maybe.withDefault Dict.empty) |> Maybe.map .name |> Maybe.withDefault ("Missing: " ++ i.assetId))
                , staticText "Natural" (Fields.displayValue i.naturalSize.x ++ " × " ++ Fields.displayValue i.naturalSize.y)
                ]

        Group ->
            UI.section model
                "node.geometry"
                "Group"
                [ span [ A.class "hint" ] [ text (String.fromInt (List.length node.childIds) ++ " children. Double-click on the canvas to edit inside the group.") ]
                , div [ A.class "button-row" ]
                    [ button [ A.class "btn small", E.onClick (EnterIsolation node.id) ] [ text "Isolate" ]
                    , button [ A.class "btn small", E.onClick UngroupSelection ] [ text "Ungroup" ]
                    ]
                ]

        ClippingGroup ->
            UI.section model
                "node.geometry"
                "Clip group"
                [ span [ A.class "hint" ] [ text "The first child is the clipping shape; the rest are clipped by it." ]
                , div [ A.class "button-row" ]
                    [ button [ A.class "btn small", E.onClick (EnterIsolation node.id) ] [ text "Isolate" ]
                    , button [ A.class "btn small", E.onClick UngroupSelection ] [ text "Release clip" ]
                    ]
                ]


appearanceSection : Model -> Scene -> Node -> Html Msg
appearanceSection model scene node =
    case node.geometry of
        Group ->
            text ""

        ClippingGroup ->
            text ""

        RasterImage _ ->
            text ""

        _ ->
            let
                fillColor =
                    case Domain.Evaluate.evaluateNodeProperty scene (Edit.currentFrame model) node FillColor of
                        Just (ColorValue c) ->
                            Just c

                        _ ->
                            Nothing

                strokeColor =
                    case Domain.Evaluate.evaluateNodeProperty scene (Edit.currentFrame model) node StrokeColor of
                        Just (ColorValue c) ->
                            Just c

                        _ ->
                            Nothing

                isLine =
                    case node.geometry of
                        Line _ ->
                            True

                        _ ->
                            False
            in
            UI.section model
                "node.appearance"
                "Appearance"
                [ if isLine then
                    text ""

                  else
                    div [ A.class "field-row paint-row" ]
                        [ UI.checkbox "Fill" (node.fill /= NoPaint) (SetNodeFill node.id)
                        , case node.fill of
                            GradientPaint _ ->
                                span [ A.class "hint" ] [ text "Gradient (imported)" ]

                            _ ->
                                Picker.swatchButton "Fill colour" Model.FillTarget fillColor
                        , case fillColor of
                            Just c ->
                                span [ A.class "paint-hex" ] [ text (Color.toHex c) ]

                            Nothing ->
                                text ""
                        , diamond model scene node FillColor
                        ]
                , div [ A.class "field-row paint-row" ]
                    [ UI.checkbox "Stroke" (node.stroke.paint /= NoPaint) (SetNodeStroke node.id)
                    , Picker.swatchButton "Stroke colour" Model.StrokeTarget strokeColor
                    , case strokeColor of
                        Just c ->
                            span [ A.class "paint-hex" ] [ text (Color.toHex c) ]

                        Nothing ->
                            text ""
                    , diamond model scene node StrokeColor
                    ]
                , if node.stroke.paint == NoPaint then
                    text ""

                  else
                    div []
                        [ div [ A.class "field-grid two" ]
                            [ num model scene node "stroke.width" "Width" 0.5 "" (Just StrokeWidth)
                            , num model scene node "miter" "Miter" 1 "" Nothing
                            ]
                        , div [ A.class "field-row" ]
                            [ UI.select "Line cap" (Paint.capToCode node.stroke.cap) [ ( "butt", "Butt cap" ), ( "round", "Round cap" ), ( "square", "Square cap" ) ] (SetStrokeOption node.id "cap")
                            , UI.select "Line join" (Paint.joinToCode node.stroke.join) [ ( "miter", "Miter join" ), ( "round", "Round join" ), ( "bevel", "Bevel join" ) ] (SetStrokeOption node.id "join")
                            ]
                        , div [ A.class "field-row" ]
                            [ span [ A.class "field-label" ] [ text "Dashes" ]
                            , UI.textField model { id = "dash.array", label = "Dash pattern", value = String.join " " (List.map Fields.displayValue node.stroke.dashArray), placeholder = "e.g. 6 4" }
                            ]
                        , div [ A.class "field-grid two" ]
                            [ num model scene node "dash.offset" "Offset" 1 "" (Just DashOffset) ]
                        ]
                ]


effectsSection : Model -> Scene -> Node -> Html Msg
effectsSection model scene node =
    let
        hasBlur =
            List.any
                (\e ->
                    case e of
                        Node.Blur _ ->
                            True

                        _ ->
                            False
                )
                node.effects

        shadow =
            node.effects
                |> List.filterMap
                    (\e ->
                        case e of
                            Node.DropShadow d ->
                                Just d

                            _ ->
                                Nothing
                    )
                |> List.head
    in
    UI.section model
        "node.effects"
        "Effects"
        [ if hasBlur then
            div [ A.class "field-row" ]
                [ num model scene node "blur" "Blur" 0.5 "" (Just BlurRadius)
                , button [ A.class "icon-button", A.title "Remove blur", A.attribute "aria-label" "Remove blur", E.onClick (SetEffect node.id "removeBlur") ] [ Icons.icon "close" ]
                ]

          else
            button [ A.class "btn small", E.onClick (SetEffect node.id "addBlur") ] [ Icons.icon "plus", text "Gaussian blur" ]
        , case shadow of
            Just d ->
                div [ A.class "field-row" ]
                    [ span [ A.class "field-label" ] [ text ("Drop shadow " ++ Fields.displayValue d.offset.x ++ ", " ++ Fields.displayValue d.offset.y ++ " blur " ++ Fields.displayValue d.blur) ]
                    , button [ A.class "icon-button", A.title "Remove shadow", A.attribute "aria-label" "Remove shadow", E.onClick (SetEffect node.id "removeShadow") ] [ Icons.icon "close" ]
                    ]

            Nothing ->
                button [ A.class "btn small", E.onClick (SetEffect node.id "addShadow") ] [ Icons.icon "plus", text "Drop shadow" ]
        , span [ A.class "hint" ] [ text "Effects export to SVG filters; CSS export leaves them static." ]
        ]


animationSection : Model -> Scene -> Node -> Html Msg
animationSection model scene node =
    let
        tracks =
            Scene.tracksFor node.id scene

        frame =
            Edit.currentFrame model
    in
    UI.section model
        "node.animation"
        "Animation"
        ([ if List.isEmpty tracks then
            span [ A.class "hint" ] [ text "No tracks yet. Click a diamond or press K to key the selection at the playhead." ]

           else
            div [ A.class "track-summary" ]
                (List.map
                    (\t ->
                        div [ A.class "track-summary-row", A.classList [ ( "disabled", not t.enabled ) ] ]
                            [ button [ A.class "track-toggle", A.title (iif t.enabled "Mute track" "Enable track"), A.attribute "aria-label" (iif t.enabled "Mute track" "Enable track"), E.onClick (SetTrackEnabled t.id (not t.enabled)) ] [ Icons.icon (iif t.enabled "check" "minus") ]
                            , span [ A.class "track-name" ] [ text (Property.pathLabel t.target.property) ]
                            , span [ A.class "track-count" ] [ text (String.fromInt (List.length t.keyframes) ++ " keys") ]
                            , button [ A.class "icon-button", A.title "Remove track", A.attribute "aria-label" ("Remove " ++ Property.pathLabel t.target.property ++ " track"), E.onClick (RemoveTrack t.id) ] [ Icons.icon "trash" ]
                            ]
                    )
                    tracks
                )
         , div [ A.class "button-row" ]
            [ button [ A.class "btn small", E.onClick AddKeyAtPlayhead ] [ Icons.icon "diamond-filled", text ("Key at " ++ String.fromInt (round frame)) ]
            , button [ A.class "btn small", E.onClick (RemoveAllAnimation node.id), A.disabled (List.isEmpty tracks) ] [ text "Remove all" ]
            ]
         ]
            ++ motionControls model scene node
        )


motionControls : Model -> Scene -> Node -> List (Html Msg)
motionControls model scene node =
    case node.motion of
        Just m ->
            [ div [ A.class "subsection" ]
                [ span [ A.class "subsection-title" ] [ text ("Motion path: " ++ (Dict.get m.pathId scene.motionPaths |> Maybe.map .name |> Maybe.withDefault m.pathId)) ]
                , div [ A.class "field-grid two" ]
                    [ num model scene node "progress" "Progress" 1 "%" (Just MotionProgress) ]
                , div [ A.class "field-row" ]
                    [ UI.checkbox "Orient to path" m.orient (SetMotionOrient node.id)
                    , button [ A.class "btn small", E.onClick (DetachMotionPath node.id) ] [ text "Detach" ]
                    ]
                ]
            ]

        Nothing ->
            [ div [ A.class "button-row" ]
                [ button [ A.class "btn small", E.onClick (ChooseTool Model.MotionPathTool) ] [ Icons.icon "motion", text "Draw motion path" ] ]
            ]


exportSection : Model -> Scene -> Node -> Html Msg
exportSection model scene node =
    let
        report =
            Capability.report Export.Format.AnimatedSvg scene

        mine =
            List.filter (\i -> i.nodeId == node.id && i.status /= Capability.Exact) report.items
    in
    UI.section model
        "node.export"
        "Export"
        [ staticText "Output id" ("fw-…-node-" ++ node.id)
        , if List.isEmpty mine then
            span [ A.class "hint" ] [ text "Every track on this layer exports exactly to animated SVG." ]

          else
            div [ A.class "report-list" ]
                (List.map
                    (\i ->
                        div [ A.class ("report-item " ++ String.toLower (Capability.statusLabel i.status)) ]
                            [ span [ A.class "pill" ] [ text (Capability.statusLabel i.status) ]
                            , span [] [ text ((i.property |> Maybe.map Property.pathLabel |> Maybe.withDefault "Layer") ++ ": " ++ statusMessage i.status) ]
                            ]
                    )
                    mine
                )
        ]


statusMessage : Capability.Status -> String
statusMessage s =
    case s of
        Capability.Exact ->
            ""

        Capability.Baked m ->
            m

        Capability.Unsupported m ->
            m



-- MULTI


multiInspector : Model -> Scene -> List Node -> Html Msg
multiInspector model scene nodes =
    let
        bounds =
            Canvas.selectionBounds model

        kinds =
            nodes |> List.map (.geometry >> Node.kindLabel) |> unique
    in
    div []
        [ div [ A.class "inspector-header" ]
            [ span [ A.class "inspector-kind" ] [ text (String.fromInt (List.length nodes) ++ " layers selected") ]
            , span [ A.class "hint" ] [ text (String.join ", " kinds) ]
            ]
        , UI.section model
            "multi.bounds"
            "Selection"
            [ case bounds of
                Just b ->
                    div [ A.class "field-grid two" ]
                        [ staticNumber "X" b.minX
                        , staticNumber "Y" b.minY
                        , staticNumber "W" (b.maxX - b.minX)
                        , staticNumber "H" (b.maxY - b.minY)
                        ]

                Nothing ->
                    text ""
            , div [ A.class "field-grid two" ]
                [ UI.numberField model { id = "opacity", label = "Opacity", value = Fields.currentValue "opacity" model, step = 1, unit = "%", animated = Nothing }
                , UI.numberField model { id = "rot", label = "Rotation", value = Fields.currentValue "rot" model, step = 1, unit = "°", animated = Nothing }
                ]
            , span [ A.class "hint" ] [ text "Values show the first selected layer; edits apply to all." ]
            ]
        , UI.section model
            "multi.arrange"
            "Align & distribute"
            [ div [ A.class "button-row" ]
                [ alignButton "left" "Align left"
                , alignButton "centerH" "Align horizontal centres"
                , alignButton "right" "Align right"
                , alignButton "top" "Align top"
                , alignButton "centerV" "Align vertical centres"
                , alignButton "bottom" "Align bottom"
                ]
            , div [ A.class "button-row" ]
                [ button [ A.class "btn small", E.onClick (Distribute "h"), A.disabled (List.length nodes < 3) ] [ text "Distribute H" ]
                , button [ A.class "btn small", E.onClick (Distribute "v"), A.disabled (List.length nodes < 3) ] [ text "Distribute V" ]
                ]
            , div [ A.class "button-row" ]
                [ button [ A.class "btn small", E.onClick (GroupSelection False) ] [ Icons.icon "group", text "Group" ]
                , button [ A.class "btn small", E.onClick (GroupSelection True) ] [ Icons.icon "clip", text "Clip" ]
                , button [ A.class "btn small", E.onClick (SetDialog (Model.StaggerDialog { startFrame = "0", spacing = "5", order = "layer" })) ] [ text "Stagger…" ]
                ]
            ]
        , let
            _ =
                scene
          in
          text ""
        ]


alignButton : String -> String -> Html Msg
alignButton how label =
    button [ A.class "btn small", A.title label, A.attribute "aria-label" label, E.onClick (SetAlign how) ] [ text (String.left 1 (String.toUpper (String.replace "center" "C" how))) ]


unique : List String -> List String
unique =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []



-- KEYFRAMES


keyframeInspector : Model -> Html Msg
keyframeInspector model =
    case ( Model.activeScene model, model.editor.selectedKeys ) of
        ( Just scene, ref :: rest ) ->
            case Dict.get ref.trackId scene.tracks |> Maybe.andThen (\t -> List.filter (\k -> k.id == ref.keyId) t.keyframes |> List.head |> Maybe.map (Tuple.pair t)) of
                Just ( track, key ) ->
                    let
                        count =
                            1 + List.length rest

                        easingCode =
                            case key.easing of
                                Hold ->
                                    "hold"

                                Linear ->
                                    "linear"

                                Preset p ->
                                    Easing.presetToCode p

                                CubicBezier _ _ _ _ ->
                                    "custom"

                                Spring _ ->
                                    "spring"

                        options =
                            [ ( "hold", "Hold" ), ( "linear", "Linear" ) ]
                                ++ List.map (\p -> ( Easing.presetToCode p, Easing.label (Preset p) )) Easing.allPresets
                                ++ [ ( "custom", "Cubic Bézier" ), ( "spring", "Spring" ) ]

                        toEasing code =
                            case code of
                                "hold" ->
                                    Hold

                                "linear" ->
                                    Linear

                                "custom" ->
                                    case key.easing of
                                        CubicBezier a b c d ->
                                            CubicBezier a b c d

                                        _ ->
                                            CubicBezier 0.42 0 0.58 1

                                "spring" ->
                                    Spring Easing.defaultSpring

                                other ->
                                    Easing.presetFromCode other |> Maybe.map Preset |> Maybe.withDefault Linear
                    in
                    UI.section model
                        "keyframe"
                        (iif (count == 1) "Keyframe" (String.fromInt count ++ " keyframes"))
                        [ div [ A.class "field-grid two" ]
                            [ UI.numberField model { id = "key.frame", label = "Frame", value = Just (toFloat key.frame), step = 1, unit = "", animated = Nothing }
                            , staticText "Time" (Fps.toTimecode scene.fps key.frame)
                            ]
                        , staticText "Property" (Property.pathLabel track.target.property ++ " · " ++ (Dict.get track.target.nodeId scene.nodes |> Maybe.map .name |> Maybe.withDefault ""))
                        , keyValueFields model key
                        , div [ A.class "field-row" ]
                            [ span [ A.class "field-label" ] [ text "Easing out" ]
                            , UI.select "Easing" easingCode options (\code -> SetKeyEasing (toEasing code))
                            ]
                        , easingEditor model key.easing
                        , div [ A.class "button-row" ]
                            [ button [ A.class "btn small", E.onClick (JumpToKey -1) ] [ Icons.icon "key-prev" ]
                            , button [ A.class "btn small", E.onClick (SetPlayhead (toFloat key.frame)) ] [ text "Go to key" ]
                            , button [ A.class "btn small", E.onClick (JumpToKey 1) ] [ Icons.icon "key-next" ]
                            , button [ A.class "btn small", E.onClick RemoveSelectedKeys ] [ Icons.icon "trash" ]
                            ]
                        ]

                Nothing ->
                    text ""

        _ ->
            text ""


keyValueFields : Model -> Keyframe.Keyframe -> Html Msg
keyValueFields model key =
    case key.value of
        Scalar _ ->
            UI.numberField model { id = "key.value", label = "Value", value = Fields.currentValue "key.value" model, step = 1, unit = "", animated = Nothing }

        Angle _ ->
            UI.numberField model { id = "key.value", label = "Angle", value = Fields.currentValue "key.value" model, step = 1, unit = "°", animated = Nothing }

        PointValue _ ->
            div [ A.class "field-grid two" ]
                [ UI.numberField model { id = "key.value.x", label = "X", value = Fields.currentValue "key.value.x" model, step = 1, unit = "", animated = Nothing }
                , UI.numberField model { id = "key.value.y", label = "Y", value = Fields.currentValue "key.value.y" model, step = 1, unit = "", animated = Nothing }
                ]

        SizeValue _ ->
            div [ A.class "field-grid two" ]
                [ UI.numberField model { id = "key.value.x", label = "W", value = Fields.currentValue "key.value.x" model, step = 1, unit = "", animated = Nothing }
                , UI.numberField model { id = "key.value.y", label = "H", value = Fields.currentValue "key.value.y" model, step = 1, unit = "", animated = Nothing }
                ]

        ColorValue c ->
            div [ A.class "field-row" ] [ span [ A.class "field-label" ] [ text "Colour" ], span [ A.class "swatch static", A.style "background" (Color.toCss c) ] [], span [ A.class "paint-hex" ] [ text (Color.toHex c) ] ]

        BoolValue b ->
            staticText "Value" (iif b "visible" "hidden")

        StringValue s ->
            staticText "Value" s

        PathValue p ->
            staticText "Value" (String.fromInt (Domain.Path.anchorCount p) ++ " anchors")

        NumberList l ->
            staticText "Value" (String.join ", " (List.map Fields.displayValue l))


{-| Curve preview with numeric handles for Bézier easing and spring
parameters; the graph samples the actual easing function.
-}
easingEditor : Model -> Easing -> Html Msg
easingEditor model easing =
    let
        samples =
            List.range 0 60
                |> List.map
                    (\i ->
                        let
                            u =
                                toFloat i / 60

                            t =
                                Easing.evaluate easing u
                        in
                        String.fromFloat (toFloat (round (u * 100 * 100)) / 100) ++ "," ++ String.fromFloat (toFloat (round ((1 - t) * 100 * 100)) / 100)
                    )

        graph =
            Html.node "svg"
                [ A.attribute "viewBox" "-10 -30 120 160", A.class "easing-graph", A.attribute "aria-hidden" "true" ]
                [ Html.node "rect" [ A.attribute "x" "0", A.attribute "y" "0", A.attribute "width" "100", A.attribute "height" "100", A.class "easing-box" ] []
                , Html.node "polyline" [ A.attribute "points" (String.join " " samples), A.class "easing-curve" ] []
                , case easing of
                    CubicBezier x1 y1 x2 y2 ->
                        Html.node "g"
                            []
                            [ Html.node "line" [ A.attribute "x1" "0", A.attribute "y1" "100", A.attribute "x2" (String.fromFloat (x1 * 100)), A.attribute "y2" (String.fromFloat (100 - y1 * 100)), A.class "easing-handle-line" ] []
                            , Html.node "line" [ A.attribute "x1" "100", A.attribute "y1" "0", A.attribute "x2" (String.fromFloat (x2 * 100)), A.attribute "y2" (String.fromFloat (100 - y2 * 100)), A.class "easing-handle-line" ] []
                            , Html.node "circle" [ A.attribute "cx" (String.fromFloat (x1 * 100)), A.attribute "cy" (String.fromFloat (100 - y1 * 100)), A.attribute "r" "4", A.class "easing-handle" ] []
                            , Html.node "circle" [ A.attribute "cx" (String.fromFloat (x2 * 100)), A.attribute "cy" (String.fromFloat (100 - y2 * 100)), A.attribute "r" "4", A.class "easing-handle" ] []
                            ]

                    _ ->
                        text ""
                ]

        fields =
            case easing of
                CubicBezier _ _ _ _ ->
                    div [ A.class "field-grid two" ]
                        [ UI.numberField model { id = "key.x1", label = "x1", value = Fields.currentValue "key.x1" model, step = 0.05, unit = "", animated = Nothing }
                        , UI.numberField model { id = "key.y1", label = "y1", value = Fields.currentValue "key.y1" model, step = 0.05, unit = "", animated = Nothing }
                        , UI.numberField model { id = "key.x2", label = "x2", value = Fields.currentValue "key.x2" model, step = 0.05, unit = "", animated = Nothing }
                        , UI.numberField model { id = "key.y2", label = "y2", value = Fields.currentValue "key.y2" model, step = 0.05, unit = "", animated = Nothing }
                        ]

                Spring _ ->
                    div [ A.class "field-grid two" ]
                        [ UI.numberField model { id = "key.mass", label = "Mass", value = Fields.currentValue "key.mass" model, step = 0.1, unit = "", animated = Nothing }
                        , UI.numberField model { id = "key.stiffness", label = "Stiffness", value = Fields.currentValue "key.stiffness" model, step = 10, unit = "", animated = Nothing }
                        , UI.numberField model { id = "key.damping", label = "Damping", value = Fields.currentValue "key.damping" model, step = 1, unit = "", animated = Nothing }
                        , UI.numberField model { id = "key.velocity", label = "Velocity", value = Fields.currentValue "key.velocity" model, step = 0.5, unit = "", animated = Nothing }
                        ]

                _ ->
                    text ""
    in
    div [ A.class "easing-editor" ] [ graph, fields ]
