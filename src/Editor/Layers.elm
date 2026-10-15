module Editor.Layers exposing (view)

{-| Left panel: layer tree, scene list and document assets.
-}

import App.Edit as Edit
import App.Model as Model exposing (LeftTab(..), Model)
import App.Msg exposing (Msg(..))
import Dict
import Domain.Document
import Domain.Fps
import Domain.Node as Node exposing (Node, NodeGeometry(..))
import Domain.Path
import Domain.Scene as Scene exposing (Scene)
import Html exposing (Html, button, div, input, li, span, text, ul)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import Set
import UI.Fields as Fields
import UI.Icons as Icons
import UI.Label as Label


view : Model -> Html Msg
view model =
    let
        e =
            model.editor

        tab label icon t =
            button
                [ A.class "panel-tab"
                , A.classList [ ( "active", e.leftTab == t ) ]
                , A.attribute "role" "tab"
                , A.attribute "aria-selected"
                    (if e.leftTab == t then
                        "true"

                     else
                        "false"
                    )
                , E.onClick (SetLeftTab t)
                ]
                [ Icons.icon icon, span [] [ text label ] ]
    in
    div [ A.class "panel left-panel", A.style "width" (String.fromFloat e.leftWidth ++ "px") ]
        [ div [ A.class "panel-tabs", A.attribute "role" "tablist" ]
            [ tab "Layers" "layers" LayersTab
            , tab "Scenes" "scenes" ScenesTab
            , tab "Assets" "assets" AssetsTab
            ]
        , case e.leftTab of
            LayersTab ->
                layersTab model

            ScenesTab ->
                scenesTab model

            AssetsTab ->
                assetsTab model
        , div [ A.class "splitter splitter-v", E.on "pointerdown" (D.map (SplitterDown "left") (D.field "clientX" D.float)), A.attribute "role" "separator", A.attribute "aria-orientation" "vertical" ] []
        ]


layersTab : Model -> Html Msg
layersTab model =
    case Model.activeScene model of
        Nothing ->
            text ""

        Just scene ->
            let
                e =
                    model.editor

                filter =
                    String.toLower (String.trim e.layerFilter)

                matches node =
                    String.isEmpty filter || String.contains filter (String.toLower node.name) || String.contains filter (String.toLower (Node.kindLabel node.geometry))

                roots =
                    List.reverse scene.rootNodeIds
            in
            div [ A.class "panel-body layers" ]
                [ div [ A.class "panel-toolbar" ]
                    [ div [ A.class "search-field" ]
                        [ Icons.icon "search"
                        , input
                            [ A.id "layer-filter"
                            , A.type_ "search"
                            , A.placeholder "Filter layers"
                            , A.value e.layerFilter
                            , A.attribute "aria-label" "Filter layers"
                            , E.onInput LayerFilter
                            ]
                            []
                        ]
                    , Fields.iconButton { icon = "group", label = "Group selection", active = False, onClick = GroupSelection False, disabled = List.isEmpty (Edit.selection model) }
                    , Fields.iconButton { icon = "trash", label = "Delete selection", active = False, onClick = DeleteSelection, disabled = List.isEmpty (Edit.selection model) }
                    ]
                , if Dict.isEmpty scene.nodes then
                    div [ A.class "empty" ] [ text "No layers yet. Draw a shape or import an SVG." ]

                  else
                    ul
                        [ A.class "layer-tree"
                        , A.attribute "role" "tree"
                        , A.attribute "aria-label" "Layers"
                        , E.onFocus (SetFocusContext Model.LayersFocus)
                        , E.on "dragover" (D.succeed NoOp)
                        ]
                        (List.concatMap (layerRow model scene matches 0) roots
                            ++ [ dropZone model Nothing 0 "Drop here to move to the back" ]
                        )
                ]


layerRow : Model -> Scene -> (Node -> Bool) -> Int -> String -> List (Html Msg)
layerRow model scene matches depth id =
    case Dict.get id scene.nodes of
        Nothing ->
            []

        Just node ->
            let
                e =
                    model.editor

                view_ =
                    Model.activeView model

                selected =
                    List.member id view_.selection

                expanded =
                    Set.member id view_.expanded

                hasChildren =
                    not (List.isEmpty node.childIds)

                animated =
                    not (List.isEmpty (Scene.tracksFor id scene))

                renaming =
                    e.renamingNode == Just id

                children =
                    if hasChildren && (expanded || not (String.isEmpty e.layerFilter)) then
                        List.concatMap (layerRow model scene matches (depth + 1)) (List.reverse node.childIds)

                    else
                        []

                visibleSelf =
                    matches node || not (List.isEmpty children)

                clickHandler =
                    E.custom "click"
                        (D.map2
                            (\shift meta ->
                                { message = SelectNodes [ id ] (shift || meta), stopPropagation = True, preventDefault = False }
                            )
                            (D.field "shiftKey" D.bool)
                            (D.oneOf [ D.field "metaKey" D.bool, D.succeed False ])
                        )

                index =
                    Scene.siblingsOf id scene |> List.indexedMap Tuple.pair |> List.filter (\( _, v ) -> v == id) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault 0

                isDropTarget =
                    e.dropTarget == Just ( node.parentId, index + 1 )

                warning =
                    List.filter (\i -> i.objectId == id) (Model.activeDoc model |> Maybe.map .validation |> Maybe.withDefault []) |> List.head
            in
            if not visibleSelf then
                []

            else
                [ li
                    [ A.class "layer-row"
                    , A.classList [ ( "selected", selected ), ( "hidden-layer", node.hidden ), ( "locked-layer", node.locked ), ( "drop-before", isDropTarget ) ]
                    , A.attribute "role" "treeitem"
                    , A.attribute "aria-selected"
                        (if selected then
                            "true"

                         else
                            "false"
                        )
                    , A.attribute "aria-expanded"
                        (if hasChildren then
                            if expanded then
                                "true"

                            else
                                "false"

                         else
                            "undefined"
                        )
                    , A.attribute "aria-level" (String.fromInt (depth + 1))
                    , A.tabindex 0
                    , A.draggable "true"
                    , E.on "dragstart" (D.succeed (LayerDragStart id))
                    , E.custom "dragover" (D.succeed { message = LayerDragOver node.parentId (index + 1), stopPropagation = True, preventDefault = True })
                    , E.custom "drop" (D.succeed { message = LayerDrop, stopPropagation = True, preventDefault = True })
                    , E.on "dragend" (D.succeed LayerDragEnd)
                    , E.custom "contextmenu"
                        (D.map2 (\x y -> { message = OpenContextMenu x y (Model.LayerContext id), stopPropagation = True, preventDefault = True })
                            (D.field "clientX" D.float)
                            (D.field "clientY" D.float)
                        )
                    , E.onDoubleClick (StartRename id)
                    , E.onFocus (SetFocusContext Model.LayersFocus)
                    , clickHandler
                    ]
                    [ div [ A.class "layer-main", A.style "padding-left" (String.fromInt (4 + depth * 14) ++ "px") ]
                        [ if hasChildren then
                            button
                                [ A.class "disclosure"
                                , A.attribute "aria-label"
                                    (if expanded then
                                        "Collapse"

                                     else
                                        "Expand"
                                    )
                                , Fields.stopPropagation "click" (ToggleExpanded id)
                                ]
                                [ Icons.icon
                                    (if expanded then
                                        "chevron-down"

                                     else
                                        "chevron-right"
                                    )
                                ]

                          else
                            span [ A.class "disclosure-spacer" ] []
                        , span [ A.class "layer-label", Label.style id ] []
                        , span [ A.class "layer-icon", A.title (Node.kindLabel node.geometry) ] [ Icons.icon (kindIcon node.geometry) ]
                        , if renaming then
                            input
                                [ A.class "layer-rename"
                                , A.id "layer-rename-input"
                                , A.value e.renameDraft
                                , A.attribute "aria-label" "Layer name"
                                , E.onInput RenameInput
                                , E.onBlur CommitRename
                                , E.custom "keydown"
                                    (D.field "key" D.string
                                        |> D.andThen
                                            (\k ->
                                                case k of
                                                    "Enter" ->
                                                        D.succeed { message = CommitRename, stopPropagation = True, preventDefault = True }

                                                    "Escape" ->
                                                        D.succeed { message = CancelRename, stopPropagation = True, preventDefault = True }

                                                    _ ->
                                                        D.succeed { message = NoOp, stopPropagation = True, preventDefault = False }
                                            )
                                    )
                                ]
                                []

                          else
                            span [ A.class "layer-name" ] [ text node.name ]
                        , if animated then
                            span [ A.class "layer-badge animated", A.title "Animated" ] [ Icons.icon "diamond-filled" ]

                          else
                            text ""
                        , case warning of
                            Just w ->
                                span [ A.class "layer-badge warning", A.title w.message ] [ Icons.icon "warning" ]

                            Nothing ->
                                text ""
                        ]
                    , div [ A.class "layer-actions" ]
                        [ button
                            [ A.class "layer-toggle"
                            , A.classList [ ( "on", not node.hidden ) ]
                            , A.title
                                (if node.hidden then
                                    "Show"

                                 else
                                    "Hide"
                                )
                            , A.attribute "aria-label"
                                (if node.hidden then
                                    "Show " ++ node.name

                                 else
                                    "Hide " ++ node.name
                                )
                            , A.attribute "aria-pressed"
                                (if node.hidden then
                                    "true"

                                 else
                                    "false"
                                )
                            , Fields.stopPropagation "click" (SetHidden id (not node.hidden))
                            ]
                            [ Icons.icon
                                (if node.hidden then
                                    "eye-off"

                                 else
                                    "eye"
                                )
                            ]
                        , button
                            [ A.class "layer-toggle"
                            , A.classList [ ( "on", node.locked ) ]
                            , A.title
                                (if node.locked then
                                    "Unlock"

                                 else
                                    "Lock"
                                )
                            , A.attribute "aria-label"
                                (if node.locked then
                                    "Unlock " ++ node.name

                                 else
                                    "Lock " ++ node.name
                                )
                            , A.attribute "aria-pressed"
                                (if node.locked then
                                    "true"

                                 else
                                    "false"
                                )
                            , Fields.stopPropagation "click" (SetLocked id (not node.locked))
                            ]
                            [ Icons.icon
                                (if node.locked then
                                    "lock"

                                 else
                                    "unlock"
                                )
                            ]
                        ]
                    ]
                ]
                    ++ (if hasChildren && expanded then
                            [ dropZone model (Just id) 0 ("Drop here to move into " ++ node.name) ]

                        else
                            []
                       )
                    ++ children


dropZone : Model -> Maybe String -> Int -> String -> Html Msg
dropZone model parent index label =
    case model.editor.gesture of
        Model.DragLayer _ ->
            li
                [ A.class "layer-dropzone"
                , A.classList [ ( "active", model.editor.dropTarget == Just ( parent, index ) ) ]
                , A.attribute "role" "none"
                , E.custom "dragover" (D.succeed { message = LayerDragOver parent index, stopPropagation = True, preventDefault = True })
                , E.custom "drop" (D.succeed { message = LayerDrop, stopPropagation = True, preventDefault = True })
                ]
                [ span [] [ text label ] ]

        _ ->
            text ""


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


scenesTab : Model -> Html Msg
scenesTab model =
    case Model.activeDoc model of
        Nothing ->
            text ""

        Just open ->
            let
                scenes =
                    Domain.Document.orderedScenes open.document
            in
            div [ A.class "panel-body scenes" ]
                [ div [ A.class "panel-toolbar" ]
                    [ button [ A.class "btn small", E.onClick AddScene ] [ Icons.icon "plus", text "New Scene" ]
                    ]
                , ul [ A.class "scene-list", A.attribute "role" "listbox", A.attribute "aria-label" "Scenes" ]
                    (List.indexedMap
                        (\i scene ->
                            let
                                active =
                                    scene.id == open.activeSceneId
                            in
                            li
                                [ A.class "scene-row"
                                , A.classList [ ( "active", active ) ]
                                , A.attribute "role" "option"
                                , A.attribute "aria-selected"
                                    (if active then
                                        "true"

                                     else
                                        "false"
                                    )
                                , E.onClick (SelectScene scene.id)
                                , E.custom "contextmenu"
                                    (D.map2 (\x y -> { message = OpenContextMenu x y (Model.SceneTabContext scene.id), stopPropagation = True, preventDefault = True })
                                        (D.field "clientX" D.float)
                                        (D.field "clientY" D.float)
                                    )
                                ]
                                [ div [ A.class "scene-thumb", A.style "aspect-ratio" (String.fromFloat scene.width ++ " / " ++ String.fromFloat scene.height) ] []
                                , div [ A.class "scene-body" ]
                                    [ span [ A.class "scene-name" ] [ text scene.name ]
                                    , span [ A.class "scene-meta" ] [ text (String.fromFloat scene.width ++ " × " ++ String.fromFloat scene.height ++ " · " ++ Domain.Fps.toLabel scene.fps ++ " fps · " ++ String.fromInt scene.durationFrames ++ " f") ]
                                    ]
                                , div [ A.class "scene-actions" ]
                                    [ button [ A.class "icon-button", A.title "Move up", A.attribute "aria-label" "Move scene up", A.disabled (i == 0), Fields.stopPropagation "click" (ReorderScene scene.id -1) ] [ Icons.icon "arrow-up" ]
                                    , button [ A.class "icon-button", A.title "Move down", A.attribute "aria-label" "Move scene down", A.disabled (i == List.length scenes - 1), Fields.stopPropagation "click" (ReorderScene scene.id 1) ] [ Icons.icon "arrow-down" ]
                                    , button [ A.class "icon-button", A.title "Duplicate scene", A.attribute "aria-label" "Duplicate scene", Fields.stopPropagation "click" (DuplicateScene scene.id) ] [ Icons.icon "duplicate" ]
                                    , button [ A.class "icon-button", A.title "Delete scene", A.attribute "aria-label" "Delete scene", A.disabled (List.length scenes <= 1), Fields.stopPropagation "click" (DeleteScene scene.id) ] [ Icons.icon "trash" ]
                                    ]
                                ]
                        )
                        scenes
                    )
                ]


assetsTab : Model -> Html Msg
assetsTab model =
    case Model.activeDoc model of
        Nothing ->
            text ""

        Just open ->
            let
                assets =
                    Dict.values open.document.assets

                usage asset =
                    open.document.scenes
                        |> Dict.values
                        |> List.concatMap (\s -> Dict.values s.nodes)
                        |> List.filter
                            (\n ->
                                case n.geometry of
                                    RasterImage i ->
                                        i.assetId == asset.id

                                    _ ->
                                        False
                            )
                        |> List.length

                motionPaths =
                    Model.activeScene model |> Maybe.map (.motionPaths >> Dict.values) |> Maybe.withDefault []
            in
            div [ A.class "panel-body assets" ]
                [ div [ A.class "panel-toolbar" ]
                    [ button [ A.class "btn small", E.onClick ImportImage ] [ Icons.icon "image", text "Import Image" ]
                    ]
                , if List.isEmpty assets && List.isEmpty motionPaths then
                    div [ A.class "empty" ] [ text "Imported images and motion paths appear here. Images are stored by content hash and packed into the .framewise file." ]

                  else
                    ul [ A.class "asset-list" ]
                        (List.map
                            (\a ->
                                li [ A.class "asset-row" ]
                                    [ div [ A.class "asset-thumb" ]
                                        [ case Dict.get a.id open.assetUrls of
                                            Just url ->
                                                Html.img [ A.src url, A.alt a.name ] []

                                            Nothing ->
                                                Icons.icon "image"
                                        ]
                                    , div [ A.class "asset-body" ]
                                        [ span [ A.class "asset-name" ] [ text a.name ]
                                        , span [ A.class "asset-meta" ] [ text (a.mimeType ++ " · " ++ String.fromInt a.width ++ " × " ++ String.fromInt a.height ++ " · used " ++ String.fromInt (usage a) ++ "×") ]
                                        ]
                                    ]
                            )
                            assets
                            ++ List.map
                                (\mp ->
                                    li [ A.class "asset-row" ]
                                        [ div [ A.class "asset-thumb" ] [ Icons.icon "motion" ]
                                        , div [ A.class "asset-body" ]
                                            [ span [ A.class "asset-name" ] [ text mp.name ]
                                            , span [ A.class "asset-meta" ] [ text ("Motion path · " ++ String.fromInt (Domain.Path.segmentCount mp.geometry) ++ " segments") ]
                                            ]
                                        ]
                                )
                                motionPaths
                        )
                ]
