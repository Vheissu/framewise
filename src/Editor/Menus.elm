module Editor.Menus exposing (contextMenu, menuBar, palette)

import App.Commands as Commands
import App.Model as Model exposing (ContextTarget(..), Model)
import App.Msg exposing (Msg(..))
import Dict
import Domain.Scene
import Html exposing (Html, button, div, input, kbd, li, span, text, ul)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import UI.Icons as Icons


menuBar : Model -> Html Msg
menuBar model =
    div [ A.class "menubar", A.attribute "role" "menubar" ]
        (button [ A.class "brand", E.onClick GoWelcome, A.title "Framewise home" ] [ Icons.icon "logo", span [] [ text "Framewise" ] ]
            :: List.map (menuButton model) Commands.menuGroups
        )


menuButton : Model -> ( String, List String ) -> Html Msg
menuButton model ( title, items ) =
    let
        isOpen =
            model.openMenu == Just title
    in
    div [ A.class "menu", A.classList [ ( "open", isOpen ) ] ]
        [ button
            [ A.class "menu-title"
            , A.attribute "role" "menuitem"
            , A.attribute "aria-haspopup" "true"
            , A.attribute "aria-expanded"
                (if isOpen then
                    "true"

                 else
                    "false"
                )
            , E.stopPropagationOn "click" (D.succeed ( ToggleMenu title, True ))
            , E.onMouseEnter (HoverMenu title)
            ]
            [ text title ]
        , if isOpen then
            ul [ A.class "menu-list", A.attribute "role" "menu" ] (List.map (menuItem model) items)

          else
            text ""
        ]


menuItem : Model -> String -> Html Msg
menuItem model id =
    if id == "-" then
        li [ A.class "menu-separator", A.attribute "role" "separator" ] []

    else
        case Commands.find id of
            Nothing ->
                text ""

            Just cmd ->
                let
                    state =
                        Commands.enabled model cmd

                    disabledReason =
                        case state of
                            Err r ->
                                Just r

                            Ok () ->
                                Nothing

                    checked =
                        checkedState model id
                in
                li [ A.attribute "role" "none" ]
                    [ button
                        [ A.class "menu-item"
                        , A.attribute "role" "menuitem"
                        , A.disabled (disabledReason /= Nothing)
                        , A.title (Maybe.withDefault cmd.label disabledReason)
                        , E.onClick (RunCommand id)
                        ]
                        [ span [ A.class "menu-check" ]
                            [ if checked then
                                Icons.icon "check"

                              else
                                text ""
                            ]
                        , span [ A.class "menu-label" ] [ text cmd.label ]
                        , span [ A.class "menu-shortcut" ]
                            [ text (cmd.shortcut |> Maybe.map (Commands.shortcutLabel model.isMac) |> Maybe.withDefault "") ]
                        ]
                    ]


checkedState : Model -> String -> Bool
checkedState model id =
    let
        e =
            model.editor
    in
    case id of
        "view.rulers" ->
            e.showRulers

        "view.grid" ->
            e.showGrid

        "view.guides" ->
            e.showGuides

        "view.snapGrid" ->
            e.snapToGrid

        "view.snapObjects" ->
            e.snapToObjects

        "view.snapArtboard" ->
            e.snapToArtboard

        "view.outline" ->
            e.outlineMode

        "view.motionPaths" ->
            e.showMotionPaths

        "view.onion" ->
            e.onionSkin

        "animate.onion" ->
            e.onionSkin

        "view.checker" ->
            e.checkerboard

        "animate.autoKey" ->
            e.autoKey

        "animate.reversePlay" ->
            e.playback.reverse

        "animate.loopOnce" ->
            Model.activeScene model |> Maybe.map (\s -> s.playbackMode == Domain.Scene.PlayOnce) |> Maybe.withDefault False

        "animate.loopRepeat" ->
            Model.activeScene model |> Maybe.map (\s -> s.playbackMode == Domain.Scene.Repeat) |> Maybe.withDefault False

        "animate.loopPingPong" ->
            Model.activeScene model |> Maybe.map (\s -> s.playbackMode == Domain.Scene.PingPong) |> Maybe.withDefault False

        "view.leftPanel" ->
            not e.leftCollapsed

        "view.rightPanel" ->
            not e.rightCollapsed

        "view.timelinePanel" ->
            not e.timelineCollapsed

        _ ->
            False


contextMenu : Model -> Model.ContextMenu -> Html Msg
contextMenu model menu =
    let
        items =
            case menu.target of
                CanvasContext (Just _) ->
                    [ "edit.cut", "edit.copy", "edit.paste", "edit.duplicate", "edit.delete", "-", "object.group", "object.ungroup", "object.clipToShape", "-", "layer.front", "layer.moveUp", "layer.moveDown", "layer.back", "-", "object.convertToPath", "object.flipH", "object.flipV", "-", "edit.rename", "layer.lock", "layer.hide", "layer.isolate", "-", "insert.keyframe", "layer.removeAnimation" ]

                CanvasContext Nothing ->
                    [ "edit.paste", "edit.pasteInPlace", "edit.selectAll", "-", "view.fitScene", "view.actualSize", "view.grid", "view.rulers", "-", "layer.exitIsolation", "file.sceneSettings" ]

                LayerContext _ ->
                    [ "edit.rename", "edit.duplicate", "edit.delete", "-", "object.group", "object.ungroup", "-", "layer.front", "layer.moveUp", "layer.moveDown", "layer.back", "-", "layer.lock", "layer.hide", "layer.isolate", "layer.selectChildren", "-", "layer.removeAnimation" ]

                KeyframeContext _ ->
                    [ "animate.hold", "animate.linear", "animate.easeIn", "animate.easeOut", "animate.easeInOut", "animate.spring", "-", "animate.copyKeys", "animate.pasteKeys", "animate.reverse", "animate.distribute", "animate.scaleUp", "animate.scaleDown", "-", "animate.setWorkRange", "-", "animate.removeKeys" ]

                TrackContext _ ->
                    [ "animate.pasteKeys", "animate.clearWorkRange" ]

                SceneTabContext _ ->
                    [ "file.sceneSettings", "file.newScene" ]

        extra =
            case menu.target of
                TrackContext trackId ->
                    [ li [ A.attribute "role" "none" ] [ button [ A.class "menu-item", E.onClick (RemoveTrack trackId) ] [ span [ A.class "menu-check" ] [], span [ A.class "menu-label" ] [ text "Remove Track" ] ] ] ]

                SceneTabContext sceneId ->
                    [ li [ A.attribute "role" "none" ] [ button [ A.class "menu-item", E.onClick (DuplicateScene sceneId) ] [ span [ A.class "menu-check" ] [], span [ A.class "menu-label" ] [ text "Duplicate Scene" ] ] ]
                    , li [ A.attribute "role" "none" ] [ button [ A.class "menu-item", E.onClick (DeleteScene sceneId) ] [ span [ A.class "menu-check" ] [], span [ A.class "menu-label" ] [ text "Delete Scene" ] ] ]
                    ]

                _ ->
                    []

        left =
            min menu.x (model.editor.canvasRect.left + model.editor.canvasRect.width + model.editor.rightWidth - 260)
    in
    ul
        [ A.class "menu-list context-menu"
        , A.attribute "role" "menu"
        , A.style "left" (String.fromFloat (max 4 left) ++ "px")
        , A.style "top" (String.fromFloat (min menu.y 600) ++ "px")
        ]
        (List.map (menuItem model) items ++ extra)


palette : Model -> Model.PaletteState -> Html Msg
palette model state =
    let
        results =
            paletteResults state.query

        keyHandler =
            E.custom "keydown"
                (D.field "key" D.string
                    |> D.andThen
                        (\key ->
                            case key of
                                "ArrowDown" ->
                                    D.succeed { message = PaletteMove 1, stopPropagation = True, preventDefault = True }

                                "ArrowUp" ->
                                    D.succeed { message = PaletteMove -1, stopPropagation = True, preventDefault = True }

                                "Enter" ->
                                    D.succeed { message = PaletteRun, stopPropagation = True, preventDefault = True }

                                "Escape" ->
                                    D.succeed { message = ClosePalette, stopPropagation = True, preventDefault = True }

                                _ ->
                                    D.fail "ignore"
                        )
                )
    in
    div
        [ A.class "palette-backdrop"
        , E.on "click"
            (D.at [ "target", "className" ] D.string
                |> D.andThen
                    (\cls ->
                        if String.contains "palette-backdrop" cls then
                            D.succeed ClosePalette

                        else
                            D.fail "inside"
                    )
            )
        ]
        [ div [ A.class "palette", A.attribute "role" "dialog", A.attribute "aria-label" "Command palette" ]
            [ div [ A.class "palette-input" ]
                [ Icons.icon "search"
                , input
                    [ A.id "palette-input"
                    , A.type_ "text"
                    , A.placeholder "Type a command…"
                    , A.value state.query
                    , A.autofocus True
                    , A.attribute "aria-label" "Search commands"
                    , E.onInput PaletteInput
                    , keyHandler
                    ]
                    []
                ]
            , ul [ A.class "palette-results", A.attribute "role" "listbox" ]
                (if List.isEmpty results then
                    [ li [ A.class "palette-empty" ] [ text "No matching commands" ] ]

                 else
                    List.indexedMap
                        (\i cmd ->
                            let
                                state_ =
                                    Commands.enabled model cmd
                            in
                            li
                                [ A.class "palette-item"
                                , A.classList [ ( "selected", i == state.index ), ( "disabled", state_ /= Ok () ) ]
                                , A.attribute "role" "option"
                                , E.onClick (RunCommand cmd.id)
                                , E.onMouseEnter (PaletteMove (i - state.index))
                                ]
                                [ span [ A.class "palette-category" ] [ text cmd.category ]
                                , span [ A.class "palette-label" ] [ text cmd.label ]
                                , case state_ of
                                    Err reason ->
                                        span [ A.class "palette-reason" ] [ text reason ]

                                    Ok () ->
                                        span [ A.class "palette-shortcut" ]
                                            [ cmd.shortcut |> Maybe.map (\s -> kbd [] [ text (Commands.shortcutLabel model.isMac s) ]) |> Maybe.withDefault (text "") ]
                                ]
                        )
                        results
                )
            ]
        ]


paletteResults : String -> List Commands.Command
paletteResults query =
    let
        q =
            String.toLower (String.trim query)

        score cmd =
            let
                label =
                    String.toLower cmd.label

                cat =
                    String.toLower cmd.category
            in
            if String.isEmpty q then
                Just 0

            else if String.startsWith q label then
                Just 0

            else if String.contains q label then
                Just 1

            else if String.contains q cat then
                Just 2

            else if fuzzy q label then
                Just 3

            else
                Nothing
    in
    Commands.all
        |> List.filterMap (\c -> score c |> Maybe.map (\s -> ( s, c )))
        |> List.sortBy Tuple.first
        |> List.map Tuple.second
        |> List.take 40


fuzzy : String -> String -> Bool
fuzzy pattern textValue =
    let
        go ps ts =
            case ( ps, ts ) of
                ( [], _ ) ->
                    True

                ( _, [] ) ->
                    False

                ( p :: prest, t :: trest ) ->
                    if p == t then
                        go prest trest

                    else
                        go ps trest
    in
    go (String.toList pattern) (String.toList textValue)
