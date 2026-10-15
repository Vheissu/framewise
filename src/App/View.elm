module App.View exposing (view)

import App.Commands as Commands
import App.Edit as Edit
import App.Model as Model exposing (Model, Route(..), Tool(..))
import App.Msg exposing (Msg(..))
import Browser
import Dict
import Domain.Fps as Fps
import Domain.Validation
import Editor.CanvasView as CanvasView
import Editor.Dialogs as Dialogs
import Editor.Inspector as Inspector
import Editor.Layers as Layers
import Editor.Menus as Menus
import Editor.Preview as Preview
import Editor.TimelineView as TimelineView
import Editor.Welcome as Welcome
import Html exposing (Html, button, div, span, text)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import UI.Fields as UI
import UI.Icons as Icons
import UI.Picker as Picker


view : Model -> Browser.Document Msg
view model =
    let
        title =
            case Model.activeDoc model of
                Just open ->
                    open.document.metadata.name ++ dirtyMark open ++ " · Framewise"

                Nothing ->
                    "Framewise"

        themeAttr =
            A.attribute "data-theme" (Model.themeToCode model.preferences.theme)
    in
    { title = title
    , body =
        [ div
            [ A.class "app"
            , A.classList [ ( "compact", model.preferences.compact ), ( "reduced-motion", model.preferences.reducedMotionOverride == Just True || (model.preferences.reducedMotionOverride == Nothing && model.reducedMotion) ) ]
            , themeAttr
            , E.on "click" (D.succeed CloseMenus)
            ]
            [ body model
            , overlays model
            , div [ A.class "sr-only", A.attribute "role" "status", A.attribute "aria-live" "polite" ] [ text model.liveAnnouncement ]
            ]
        ]
    }


dirtyMark : Model.OpenDocument -> String
dirtyMark open =
    if Just open.revision == open.savedRevision then
        ""

    else
        " •"


body : Model -> Html Msg
body model =
    case model.route of
        Welcome ->
            Welcome.view model

        NotFound ->
            Welcome.view model

        PreviewRoute _ _ ->
            case Model.activeDoc model of
                Just _ ->
                    Preview.view model

                Nothing ->
                    loading

        EditorRoute _ ->
            case Model.activeDoc model of
                Just _ ->
                    editor model

                Nothing ->
                    loading


loading : Html Msg
loading =
    div [ A.class "loading" ] [ text "Opening document…" ]


editor : Model -> Html Msg
editor model =
    let
        e =
            model.editor
    in
    div [ A.class "editor" ]
        [ Menus.menuBar model
        , documentBar model
        , div [ A.class "workspace" ]
            [ toolRail model
            , if e.leftCollapsed then
                collapsedPanel "left" "Show layers panel"

              else
                Layers.view model
            , div [ A.class "center" ]
                [ CanvasView.view model
                , if e.timelineCollapsed then
                    collapsedPanel "timeline" "Show timeline"

                  else
                    TimelineView.view model
                ]
            , if e.rightCollapsed then
                collapsedPanel "right" "Show inspector"

              else
                Inspector.view model
            ]
        , statusBar model
        ]


collapsedPanel : String -> String -> Html Msg
collapsedPanel which label =
    button [ A.class ("collapsed-panel collapsed-" ++ which), A.title label, A.attribute "aria-label" label, E.onClick (ToggleCollapse which) ]
        [ Icons.icon
            (case which of
                "left" ->
                    "chevron-right"

                "right" ->
                    "arrow-left"

                _ ->
                    "arrow-up"
            )
        ]


documentBar : Model -> Html Msg
documentBar model =
    div [ A.class "docbar" ]
        [ div [ A.class "doc-tabs", A.attribute "role" "tablist" ]
            (List.filterMap
                (\id ->
                    Dict.get id model.documents
                        |> Maybe.map
                            (\open ->
                                let
                                    active =
                                        model.activeDocument == Just id
                                in
                                div [ A.class "doc-tab", A.classList [ ( "active", active ) ], A.attribute "role" "tab", A.attribute "aria-selected" (iif active "true" "false") ]
                                    [ button [ A.class "doc-tab-name", E.onClick (OpenDocumentTab id), A.title (Maybe.withDefault "Not saved to a file yet" open.fileName) ]
                                        [ text open.document.metadata.name
                                        , span [ A.class ("doc-dot " ++ statusClass open) ] []
                                        ]
                                    , button [ A.class "doc-tab-close", A.attribute "aria-label" ("Close " ++ open.document.metadata.name), E.onClick (CloseDocument id) ] [ Icons.icon "close" ]
                                    ]
                            )
                )
                model.openOrder
            )
        , div [ A.class "docbar-actions" ]
            [ saveStatus model
            , button [ A.class "btn small", E.onClick SaveDocument, A.title "Save (Ctrl/Cmd+S)" ] [ Icons.icon "save", text "Save" ]
            , button [ A.class "btn small", E.onClick OpenPreview, A.title "Preview (Ctrl/Cmd+Enter)" ] [ Icons.icon "play", text "Preview" ]
            , button [ A.class "btn small primary", E.onClick OpenExport, A.title "Export (Ctrl/Cmd+E)" ] [ Icons.icon "export", text "Export" ]
            ]
        ]


statusClass : Model.OpenDocument -> String
statusClass open =
    if Just open.revision == open.savedRevision then
        "saved"

    else if open.autosavedRevision == Just open.revision then
        "autosaved"

    else
        "dirty"


saveStatus : Model -> Html Msg
saveStatus model =
    case Model.activeDoc model of
        Nothing ->
            text ""

        Just open ->
            let
                ( cls, label ) =
                    case open.saveStatus of
                        Model.Saving ->
                            ( "saving", "Saving…" )

                        Model.SaveFailed reason ->
                            ( "failed", "Save failed: " ++ reason )

                        Model.SaveIdle ->
                            case open.autosaveFailed of
                                Just _ ->
                                    ( "failed", "Autosave failed" )

                                Nothing ->
                                    if Just open.revision == open.savedRevision then
                                        ( "saved"
                                        , if open.lastSaveWasDownload then
                                            "Downloaded"

                                          else
                                            "Saved to file"
                                        )

                                    else if open.autosavedRevision == Just open.revision then
                                        ( "autosaved", "Autosaved locally" )

                                    else
                                        ( "dirty", "Unsaved changes" )
            in
            span [ A.class ("save-status " ++ cls), A.title (Maybe.withDefault "No file yet. Save writes a .framewise archive." open.fileName) ]
                [ text label
                , if open.isRecoveryCopy then
                    span [ A.class "pill warning" ] [ text "recovery copy" ]

                  else
                    text ""
                ]


toolRail : Model -> Html Msg
toolRail model =
    let
        e =
            model.editor

        tool t icon =
            let
                label =
                    Model.toolLabel t ++ (Model.toolShortcut t |> Maybe.map (\s -> " (" ++ s ++ ")") |> Maybe.withDefault "")
            in
            button
                [ A.class "tool"
                , A.classList [ ( "active", e.tool == t ) ]
                , A.title label
                , A.attribute "aria-label" label
                , A.attribute "aria-pressed" (iif (e.tool == t) "true" "false")
                , E.onClick (ChooseTool t)
                ]
                [ Icons.icon icon ]
    in
    div [ A.class "tool-rail", A.attribute "role" "toolbar", A.attribute "aria-label" "Tools", A.attribute "aria-orientation" "vertical" ]
        [ tool SelectTool "select"
        , tool DirectSelectTool "direct"
        , div [ A.class "tool-sep" ] []
        , tool PenTool "pen"
        , tool RectTool "rect"
        , tool EllipseTool "ellipse"
        , tool LineTool "line"
        , tool PolygonTool "polygon"
        , tool StarTool "star"
        , tool TextTool "text"
        , button [ A.class "tool", A.title "Image (import)", A.attribute "aria-label" "Import image", E.onClick ImportImage ] [ Icons.icon "image" ]
        , div [ A.class "tool-sep" ] []
        , tool MotionPathTool "motion"
        , tool PivotTool "pivot"
        , div [ A.class "tool-sep" ] []
        , tool HandTool "hand"
        , tool ZoomTool "zoom"
        , div [ A.class "tool-spacer" ] []
        , UI.iconButton { icon = "grid", label = "Grid", active = e.showGrid, onClick = ToggleEditorFlag "grid", disabled = False }
        , UI.iconButton { icon = "magnet", label = "Snap to grid", active = e.snapToGrid, onClick = ToggleEditorFlag "snapGrid", disabled = False }
        , UI.iconButton { icon = "ruler", label = "Rulers", active = e.showRulers, onClick = ToggleEditorFlag "rulers", disabled = False }
        ]


statusBar : Model -> Html Msg
statusBar model =
    let
        e =
            model.editor

        view_ =
            Model.activeView model

        sel =
            Edit.selectedNodes model

        selectionText =
            case sel of
                [] ->
                    "Nothing selected"

                [ n ] ->
                    n.name

                many ->
                    String.fromInt (List.length many) ++ " selected"

        hint =
            case e.tool of
                SelectTool ->
                    "Drag to move · Shift+drag constrains · Alt+drag duplicates · Double-click a group to isolate"

                DirectSelectTool ->
                    "Drag anchors and handles · Alt breaks handle mirroring"

                PenTool ->
                    "Click to add anchors · Drag for curves · Click the first anchor to close · Enter finishes"

                MotionPathTool ->
                    "Draw the path for the selected object · Enter finishes"

                HandTool ->
                    "Drag to pan · Space+drag from any tool"

                ZoomTool ->
                    "Click to zoom in · Drag a marquee · Ctrl/Cmd+wheel zooms anywhere"

                TextTool ->
                    "Click to place text"

                PivotTool ->
                    "Drag to move the pivot without moving the artwork"

                _ ->
                    "Drag to draw · Shift keeps proportions · Click for a 100×100 default"

        issues =
            Model.activeDoc model |> Maybe.map .validation |> Maybe.withDefault []

        errors =
            List.filter (\i -> i.severity == Domain.Validation.Error) issues

        warnings =
            List.filter (\i -> i.severity == Domain.Validation.Warning) issues
    in
    div [ A.class "statusbar" ]
        [ span [ A.class "status-tool" ] [ text (Model.toolLabel e.tool) ]
        , span [ A.class "status-hint" ] [ text hint ]
        , span [ A.class "status-selection" ] [ text selectionText ]
        , span [ A.class "status-frame" ]
            [ text
                (case Model.activeScene model of
                    Just s ->
                        "f " ++ String.fromInt (round view_.playhead) ++ " · " ++ Fps.toTimecode s.fps (round view_.playhead)

                    Nothing ->
                        ""
                )
            ]
        , UI.numberField model { id = "zoom", label = "Zoom", value = Just (view_.zoom * 100), step = 10, unit = "%", animated = Nothing }
        , span [ A.class "status-snap", A.title "Snapping" ]
            [ text
                ("Snap: "
                    ++ String.join ", "
                        (List.filterMap identity
                            [ iif e.snapToArtboard (Just "artboard") Nothing
                            , iif e.snapToObjects (Just "objects") Nothing
                            , iif e.snapToGrid (Just "grid") Nothing
                            ]
                        )
                )
            ]
        , if List.isEmpty errors && List.isEmpty warnings then
            text ""

          else
            span [ A.class "status-issues", A.title (String.join "\n" (List.map .message (List.take 5 issues))) ]
                [ Icons.icon "warning", text (String.fromInt (List.length errors) ++ " errors · " ++ String.fromInt (List.length warnings) ++ " warnings") ]
        , if model.preferences.showDiagnostics then
            span [ A.class "status-diag" ]
                [ text ("ids " ++ String.fromInt (List.length model.ids) ++ " · docs " ++ String.fromInt (Dict.size model.documents) ++ " · jobs " ++ String.fromInt (List.length model.exportJobs)) ]

          else
            text ""
        , span [ A.class "status-keys" ]
            [ text (iif e.autoKey "Auto-key on" "Auto-key off") ]
        ]


overlays : Model -> Html Msg
overlays model =
    div []
        [ Dialogs.view model
        , case model.palette of
            Just p ->
                Menus.palette model p

            Nothing ->
                text ""
        , case model.contextMenu of
            Just m ->
                Menus.contextMenu model m

            Nothing ->
                text ""
        , case model.picker of
            Just p ->
                Picker.view model p

            Nothing ->
                text ""
        , toasts model
        , if model.dragOverlay then
            div [ A.class "drop-overlay" ]
                [ div [ A.class "drop-card" ] [ Icons.icon "import", span [] [ text "Drop .framewise, .svg or an image" ], span [ A.class "hint" ] [ text (iif (Model.activeDoc model /= Nothing) "SVG and images import into the current scene; .framewise opens as a document." "Files open as new documents.") ] ] ]

          else
            text ""
        ]


toasts : Model -> Html Msg
toasts model =
    div [ A.class "toasts", A.attribute "aria-live" "polite" ]
        (List.map
            (\t ->
                div [ A.class ("toast toast-" ++ t.kind) ]
                    [ Icons.icon
                        (case t.kind of
                            "error" ->
                                "warning"

                            "warning" ->
                                "warning"

                            _ ->
                                "info"
                        )
                    , span [] [ text t.message ]
                    , button [ A.class "icon-button", A.attribute "aria-label" "Dismiss", E.onClick (DismissToast t.id) ] [ Icons.icon "close" ]
                    ]
            )
            (List.reverse model.toasts |> List.take 4)
        )


iif : Bool -> a -> a -> a
iif c a b =
    if c then
        a

    else
        b
