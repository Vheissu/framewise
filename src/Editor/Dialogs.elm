module Editor.Dialogs exposing (view)

{-| Modal dialogs. Every dialog is a `role="dialog"` with a labelled title;
focus trapping is handled by the `fw-dialog` custom element in the adapter.
-}

import App.Commands as Commands
import App.Docs as Docs
import App.Model as Model exposing (Dialog(..), Model, PrefTab(..))
import App.Msg exposing (Msg(..))
import App.Presets as Presets
import Dict
import Domain.Color as Color
import Domain.Document
import Domain.Fps as Fps
import Domain.History as History
import Domain.Scene as Scene
import Editor.ExportStudio as ExportStudio
import Html exposing (Html, button, div, h2, h3, input, label, li, p, span, text, ul)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import Time
import UI.Fields as UI
import UI.Icons as Icons
import UI.Picker as Picker


view : Model -> Html Msg
view model =
    case model.dialog of
        NoDialog ->
            text ""

        NewDocumentDialog form ->
            frame "New Document" "wide" (newDocument model form)

        SceneSettingsDialog form ->
            frame "Scene Settings" "" (sceneSettings model form)

        FpsRetimeDialog form ->
            frame "Scene Settings" "" (sceneSettings model form)

        ImportReviewDialog review ->
            frame "Import Review" "" (importReview review)

        ExportDialog form ->
            frame "Export Studio" "full" [ ExportStudio.view model form ]

        PreferencesDialog tab query ->
            frame "Preferences" "wide" (preferences model tab query)

        ShortcutsDialog query ->
            frame "Keyboard Shortcuts" "wide" (shortcuts model query)

        AboutDialog ->
            frame "About Framewise" "" (about model)

        DocsDialog page query ->
            frame "Documentation" "wide" (docs page query)

        RecoveryDialog ->
            frame "Recover Unsaved Work" "wide" (recovery model)

        HistoryDialog ->
            frame "History" "" (history model)

        StaggerDialog form ->
            frame "Stagger Animation" "" (stagger form)

        ConfirmDialog c ->
            frame c.title
                ""
                [ p [] [ text c.body ]
                , actions [ button [ A.class "btn", E.onClick CloseDialog ] [ text "Cancel" ], button [ A.class "btn danger", A.autofocus True, E.onClick (ConfirmAccepted c.onConfirm) ] [ text c.confirmLabel ] ]
                ]

        DocumentSettingsDialog form ->
            frame "Document Settings"
                ""
                [ labelled "Name" (input [ A.type_ "text", A.value form.name, A.autofocus True, E.onInput (DocSettingsChanged "name"), UI.onEnter SubmitDocumentSettings ] [])
                , labelled "Description" (Html.textarea [ A.class "text-area", A.value form.description, E.onInput (DocSettingsChanged "description") ] [])
                , actions [ button [ A.class "btn", E.onClick CloseDialog ] [ text "Cancel" ], button [ A.class "btn primary", E.onClick SubmitDocumentSettings ] [ text "Save" ] ]
                ]

        ErrorDialog title body ->
            frame title
                ""
                [ div [ A.class "notice error" ] [ Icons.icon "warning", Html.pre [ A.class "error-detail" ] [ text body ] ]
                , p [ A.class "hint" ] [ text "Nothing was changed. Your original file is untouched." ]
                , actions [ button [ A.class "btn primary", A.autofocus True, E.onClick CloseDialog ] [ text "Close" ] ]
                ]


frame : String -> String -> List (Html Msg) -> Html Msg
frame title size children =
    div [ A.class "dialog-backdrop", E.on "click" backdropClick ]
        [ Html.node "fw-dialog"
            [ A.class ("dialog " ++ size)
            , A.attribute "role" "dialog"
            , A.attribute "aria-modal" "true"
            , A.attribute "aria-label" title
            ]
            [ div [ A.class "dialog-header" ]
                [ h2 [] [ text title ]
                , button [ A.class "icon-button", A.attribute "aria-label" "Close dialog", E.onClick CloseDialog ] [ Icons.icon "close" ]
                ]
            , div [ A.class "dialog-body" ] children
            ]
        ]


{-| Close only when the backdrop itself is clicked, not content inside the
dialog. Stopping propagation from the dialog would make Elm re-render
synchronously inside the click, which breaks native checkbox toggling.
-}
backdropClick : D.Decoder Msg
backdropClick =
    D.at [ "target", "className" ] D.string
        |> D.andThen
            (\cls ->
                if String.contains "dialog-backdrop" cls then
                    D.succeed CloseDialog

                else
                    D.fail "inside dialog"
            )


actions : List (Html Msg) -> Html Msg
actions children =
    div [ A.class "dialog-actions" ] children


labelled : String -> Html Msg -> Html Msg
labelled labelText control =
    label [ A.class "labelled" ] [ span [ A.class "field-label" ] [ text labelText ], control ]



-- NEW DOCUMENT


newDocument : Model -> Model.DocForm -> List (Html Msg)
newDocument model form =
    let
        change f =
            DocFormChanged f

        textField labelText value toMsg =
            labelled labelText (input [ A.type_ "text", A.value value, E.onInput toMsg, UI.onEnter SubmitNewDocument ] [])

        filtered =
            Presets.all
                |> List.filter (\p -> String.isEmpty form.search || String.contains (String.toLower form.search) (String.toLower (p.label ++ " " ++ p.category)))
    in
    [ div [ A.class "two-column" ]
        [ div []
            [ h3 [] [ text "Preset" ]
            , div [ A.class "search-field" ] [ Icons.icon "search", input [ A.type_ "search", A.placeholder "Search presets", A.value form.search, E.onInput (\v -> change (\f -> { f | search = v })) ] [] ]
            , div [ A.class "preset-grid" ]
                (List.map
                    (\p ->
                        button
                            [ A.class "preset small"
                            , A.classList [ ( "selected", form.preset == p.id ) ]
                            , E.onClick (NewDocumentFromPreset p.id)
                            ]
                            [ span [ A.class "preset-label" ] [ text p.label ], span [ A.class "preset-meta" ] [ text p.category ] ]
                    )
                    filtered
                )
            ]
        , div []
            [ h3 [] [ text "Document" ]
            , textField "Title" form.title (\v -> change (\f -> { f | title = v }))
            , textField "First scene name" form.sceneName (\v -> change (\f -> { f | sceneName = v }))
            , div [ A.class "field-grid two" ]
                [ textField "Width (px)" form.width (\v -> change (\f -> { f | width = v, preset = "custom" }))
                , textField "Height (px)" form.height (\v -> change (\f -> { f | height = v, preset = "custom" }))
                ]
            , labelled "Frame rate"
                (UI.select "Frame rate preset"
                    form.fpsPreset
                    (List.map (\( l, _ ) -> ( l, l ++ " fps" )) Fps.presets ++ [ ( "custom", "Custom rational" ) ])
                    (\v ->
                        change
                            (\f ->
                                case Fps.presets |> List.filter (\( l, _ ) -> l == v) |> List.head of
                                    Just ( _, rate ) ->
                                        { f | fpsPreset = v, fpsNumerator = String.fromInt rate.numerator, fpsDenominator = String.fromInt rate.denominator }

                                    Nothing ->
                                        { f | fpsPreset = v }
                            )
                    )
                )
            , if form.fpsPreset == "custom" then
                div [ A.class "field-grid two" ]
                    [ textField "Numerator" form.fpsNumerator (\v -> change (\f -> { f | fpsNumerator = v }))
                    , textField "Denominator" form.fpsDenominator (\v -> change (\f -> { f | fpsDenominator = v }))
                    ]

              else
                text ""
            , textField ("Duration (frames) · " ++ durationLabel form) form.duration (\v -> change (\f -> { f | duration = v }))
            , div [ A.class "field-row" ]
                [ UI.checkbox "Transparent background" form.transparent (\v -> change (\f -> { f | transparent = v }))
                , if form.transparent then
                    text ""

                  else
                    Picker.swatchButton "Background colour" Model.FormBackgroundTarget (Just form.background)
                ]
            , p [ A.class "hint" ] [ text "Units are px (SVG user units). Colour profile is sRGB." ]
            , case form.error of
                Just e ->
                    div [ A.class "notice error" ] [ Icons.icon "warning", span [] [ text e ] ]

                Nothing ->
                    text ""
            ]
        ]
    , actions
        [ button [ A.class "btn", E.onClick CloseDialog ] [ text "Cancel" ]
        , button [ A.class "btn primary", E.onClick SubmitNewDocument ] [ text "Create" ]
        ]
    , let
        _ =
            model
      in
      text ""
    ]


durationLabel : Model.DocForm -> String
durationLabel form =
    case ( String.toInt form.duration, String.toInt form.fpsNumerator, String.toInt form.fpsDenominator ) of
        ( Just d, Just n, Just den ) ->
            if n > 0 && den > 0 then
                String.fromFloat (toFloat (round (toFloat d * toFloat den / toFloat n * 100)) / 100) ++ " s"

            else
                ""

        _ ->
            ""



-- SCENE SETTINGS


sceneSettings : Model -> Model.SceneForm -> List (Html Msg)
sceneSettings model form =
    let
        change f =
            SceneFormChanged f

        textField labelText value toMsg =
            labelled labelText (input [ A.type_ "text", A.value value, E.onInput toMsg, UI.onEnter SubmitSceneSettings ] [])

        current =
            Model.activeDoc model |> Maybe.andThen (\d -> Dict.get form.sceneId d.document.scenes)

        fpsChanged =
            case ( current, String.toInt form.fpsNumerator, String.toInt form.fpsDenominator ) of
                ( Just s, Just n, Just d ) ->
                    not (Fps.equal s.fps (Fps.fps n d))

                _ ->
                    False

        sizeChanged =
            case ( current, String.toFloat form.width, String.toFloat form.height ) of
                ( Just s, Just w, Just h ) ->
                    w /= s.width || h /= s.height

                _ ->
                    False

        durationShrinks =
            case ( current, String.toInt form.duration ) of
                ( Just s, Just d ) ->
                    d < s.durationFrames

                _ ->
                    False
    in
    [ textField "Name" form.name (\v -> change (\f -> { f | name = v }))
    , div [ A.class "field-grid two" ]
        [ textField "Width" form.width (\v -> change (\f -> { f | width = v }))
        , textField "Height" form.height (\v -> change (\f -> { f | height = v }))
        ]
    , if sizeChanged then
        labelled "When resizing" (UI.select "Resize policy" form.resizeMode [ ( "keep", "Keep content positions" ), ( "scale", "Scale content to fit" ) ] (\v -> change (\f -> { f | resizeMode = v })))

      else
        text ""
    , div [ A.class "field-grid two" ]
        [ textField "FPS numerator" form.fpsNumerator (\v -> change (\f -> { f | fpsNumerator = v }))
        , textField "FPS denominator" form.fpsDenominator (\v -> change (\f -> { f | fpsDenominator = v }))
        ]
    , if fpsChanged then
        div []
            [ labelled "When changing frame rate" (UI.select "Retime policy" form.fpsMode [ ( "time", "Preserve timing in seconds (rescale frames)" ), ( "frames", "Preserve frame indices (duration changes)" ) ] (\v -> change (\f -> { f | fpsMode = v })))
            , retimePreview model form
            ]

      else
        text ""
    , textField "Duration (frames)" form.duration (\v -> change (\f -> { f | duration = v }))
    , if durationShrinks then
        UI.checkbox "Keep keyframes beyond the new duration (hidden until restored)" form.keepOutOfRange (\v -> change (\f -> { f | keepOutOfRange = v }))

      else
        text ""
    , div [ A.class "field-row" ]
        [ UI.checkbox "Transparent background" form.transparent (\v -> change (\f -> { f | transparent = v }))
        , if form.transparent then
            text ""

          else
            Picker.swatchButton "Background colour" Model.FormBackgroundTarget (Just form.background)
        ]
    , labelled "Loop mode"
        (UI.select "Loop mode" (Scene.playbackModeToCode form.playbackMode) [ ( "once", "Play once" ), ( "repeat", "Repeat" ), ( "pingpong", "Ping-pong" ) ] (\v -> change (\f -> { f | playbackMode = Scene.playbackModeFromCode v |> Maybe.withDefault f.playbackMode })))
    , UI.checkbox "Use a work range for playback and export" form.useWorkRange (\v -> change (\f -> { f | useWorkRange = v }))
    , if form.useWorkRange then
        div [ A.class "field-grid two" ]
            [ textField "Work start" form.workStart (\v -> change (\f -> { f | workStart = v }))
            , textField "Work end" form.workEnd (\v -> change (\f -> { f | workEnd = v }))
            ]

      else
        text ""
    , labelled "Description (accessibility)" (Html.textarea [ A.class "text-area", A.value form.description, E.onInput (\v -> change (\f -> { f | description = v })) ] [])
    , case form.error of
        Just e ->
            div [ A.class "notice error" ] [ Icons.icon "warning", span [] [ text e ] ]

        Nothing ->
            text ""
    , actions
        [ button [ A.class "btn", E.onClick CloseDialog ] [ text "Cancel" ]
        , button [ A.class "btn primary", E.onClick SubmitSceneSettings ] [ text "Apply" ]
        ]
    ]


retimePreview : Model -> Model.SceneForm -> Html Msg
retimePreview model form =
    case ( Model.activeDoc model |> Maybe.andThen (\d -> Dict.get form.sceneId d.document.scenes), String.toInt form.fpsNumerator, String.toInt form.fpsDenominator ) of
        ( Just scene, Just n, Just d ) ->
            let
                newFps =
                    Fps.fps n d

                factor =
                    Fps.toFloat newFps / Fps.toFloat scene.fps

                sample =
                    Dict.values scene.tracks
                        |> List.concatMap .keyframes
                        |> List.map .frame
                        |> List.sort
                        |> dedupe
                        |> List.take 8
            in
            if List.isEmpty sample then
                text ""

            else
                div [ A.class "retime-preview" ]
                    [ span [ A.class "hint" ]
                        [ text
                            (if form.fpsMode == "time" then
                                "Keyframes move: " ++ String.join ", " (List.map (\f -> String.fromInt f ++ "→" ++ String.fromInt (round (toFloat f * factor))) sample)

                             else
                                "Keyframes stay on their frames; the scene now lasts " ++ String.fromFloat (toFloat (round (Fps.framesToSeconds newFps (toFloat scene.durationFrames) * 100)) / 100) ++ " s"
                            )
                        ]
                    ]

        _ ->
            text ""


dedupe : List comparable -> List comparable
dedupe =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []



-- IMPORT REVIEW


importReview : Model.ImportReview -> List (Html Msg)
importReview review =
    [ p [] [ text (review.fileName ++ ": " ++ String.fromInt review.supportedCount ++ " element(s) can be imported as editable layers.") ]
    , reviewList "Approximated" "baked" review.approximated
    , reviewList "Unsupported (skipped)" "unsupported" review.unsupported
    , reviewList "Warnings" "warning" review.warnings
    , if review.supportedCount == 0 then
        div [ A.class "notice error" ] [ Icons.icon "warning", span [] [ text "Nothing in this file can be converted to editable artwork." ] ]

      else
        text ""
    , p [ A.class "hint" ] [ text "Scripts, event handlers, external references and foreignObject were removed before parsing. Nothing from this file runs." ]
    , actions
        [ button [ A.class "btn", E.onClick ImportReviewCancel ] [ text "Cancel" ]
        , button [ A.class "btn primary", A.disabled (review.supportedCount == 0), E.onClick ImportReviewAccept ]
            [ text
                (if review.asNewDocument then
                    "Open as New Document"

                 else
                    "Import Supported"
                )
            ]
        ]
    ]


reviewList : String -> String -> List String -> Html Msg
reviewList title cls items =
    if List.isEmpty items then
        text ""

    else
        div [ A.class "review-group" ]
            [ h3 [] [ span [ A.class ("pill " ++ cls) ] [ text (String.fromInt (List.length items)) ], text (" " ++ title) ]
            , ul [ A.class "review-list" ] (List.map (\i -> li [] [ text i ]) (List.take 40 items))
            , if List.length items > 40 then
                span [ A.class "hint" ] [ text ("…and " ++ String.fromInt (List.length items - 40) ++ " more") ]

              else
                text ""
            ]



-- PREFERENCES


preferences : Model -> PrefTab -> String -> List (Html Msg)
preferences model tab query =
    let
        prefs =
            model.preferences

        tabButton t labelText =
            button [ A.class "pref-tab", A.classList [ ( "active", tab == t ) ], A.attribute "role" "tab", A.attribute "aria-selected" (iif (tab == t) "true" "false"), E.onClick (SetPrefTab t) ] [ text labelText ]

        numberPref labelText value toPrefs =
            labelled labelText
                (input
                    [ A.type_ "number"
                    , A.value (String.fromFloat value)
                    , E.onInput (\s -> PreferenceChanged (\p -> String.toFloat s |> Maybe.map (toPrefs p) |> Maybe.withDefault p))
                    ]
                    []
                )

        content =
            case tab of
                GeneralTab ->
                    [ labelled "Theme" (UI.select "Theme" (Model.themeToCode prefs.theme) [ ( "system", "System" ), ( "light", "Light" ), ( "dark", "Dark" ) ] (\v -> PreferenceChanged (\p -> { p | theme = Model.themeFromCode v })))
                    , UI.checkbox "Compact density" prefs.compact (\v -> PreferenceChanged (\p -> { p | compact = v }))
                    , labelled "Reduced motion" (UI.select "Reduced motion" (maybeBool prefs.reducedMotionOverride) [ ( "system", "Follow system" ), ( "on", "Always reduce" ), ( "off", "Never reduce" ) ] (\v -> PreferenceChanged (\p -> { p | reducedMotionOverride = boolMaybe v })))
                    , numberPref "Autosave idle delay (ms)" (toFloat prefs.autosaveIdleMs) (\p v -> { p | autosaveIdleMs = clamp 300 60000 (round v) })
                    , numberPref "Recent documents to show" (toFloat prefs.recentLimit) (\p v -> { p | recentLimit = clamp 1 50 (round v) })
                    , UI.checkbox "Confirm before deleting layers" prefs.confirmDelete (\v -> PreferenceChanged (\p -> { p | confirmDelete = v }))
                    , labelled "Language" (UI.select "Language" "en" [ ( "en", "English" ) ] (\_ -> NoOp))
                    ]

                CanvasTab ->
                    [ numberPref "Grid spacing" prefs.gridSpacing (\p v -> { p | gridSpacing = max 1 v })
                    , numberPref "Snap tolerance (screen px)" prefs.snapTolerance (\p v -> { p | snapTolerance = clamp 1 32 v })
                    , numberPref "Nudge (units)" prefs.nudge (\p v -> { p | nudge = max 0.01 v })
                    , numberPref "Large nudge (units)" prefs.largeNudge (\p v -> { p | largeNudge = max 0.01 v })
                    , numberPref "Default document width" prefs.defaultWidth (\p v -> { p | defaultWidth = clamp 1 16384 v })
                    , numberPref "Default document height" prefs.defaultHeight (\p v -> { p | defaultHeight = clamp 1 16384 v })
                    ]

                AnimationTab ->
                    [ labelled "Default frame rate" (UI.select "Default fps" (Fps.toLabel prefs.defaultFps) (List.map (\( l, _ ) -> ( l, l ++ " fps" )) Fps.presets) (\v -> PreferenceChanged (\p -> { p | defaultFps = Fps.presets |> List.filter (\( l, _ ) -> l == v) |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault p.defaultFps })))
                    , numberPref "Default duration (frames)" (toFloat prefs.defaultDuration) (\p v -> { p | defaultDuration = clamp 1 100000 (round v) })
                    , UI.checkbox "Auto-keyframe on for new documents" prefs.autoKeyDefault (\v -> PreferenceChanged (\p -> { p | autoKeyDefault = v }))
                    , labelled "Editing an animated value with Auto-Keyframe off" (UI.select "Off-key policy" prefs.offKeyPolicy [ ( "nearest", "Edit the nearest keyframe" ), ( "add", "Add a keyframe at the playhead" ) ] (\v -> PreferenceChanged (\p -> { p | offKeyPolicy = v })))
                    , UI.checkbox "Snap playhead and keys to whole frames" prefs.timelineSnap (\v -> PreferenceChanged (\p -> { p | timelineSnap = v }))
                    ]

                PerformanceTab ->
                    [ numberPref "Undo history limit" (toFloat prefs.historyLimit) (\p v -> { p | historyLimit = clamp 10 2000 (round v) })
                    , UI.checkbox "Show developer diagnostics in the status bar" prefs.showDiagnostics (\v -> PreferenceChanged (\p -> { p | showDiagnostics = v }))
                    , p [ A.class "hint" ] [ text "Rendering uses the browser's SVG engine; exports rasterise through an offscreen canvas when available." ]
                    ]

                ShortcutsTab ->
                    shortcuts model query

                StorageTab ->
                    storage model

                AboutTab ->
                    about model
    in
    [ div [ A.class "pref-layout" ]
        [ div [ A.class "pref-tabs", A.attribute "role" "tablist" ]
            [ tabButton GeneralTab "General"
            , tabButton CanvasTab "Canvas"
            , tabButton AnimationTab "Animation"
            , tabButton PerformanceTab "Performance"
            , tabButton ShortcutsTab "Shortcuts"
            , tabButton StorageTab "Privacy & Storage"
            , tabButton AboutTab "About"
            ]
        , div [ A.class "pref-content" ] content
        ]
    , actions [ button [ A.class "btn", E.onClick ResetPreferences ] [ text "Reset to defaults" ], button [ A.class "btn primary", E.onClick CloseDialog ] [ text "Done" ] ]
    ]


maybeBool : Maybe Bool -> String
maybeBool m =
    case m of
        Nothing ->
            "system"

        Just True ->
            "on"

        Just False ->
            "off"


boolMaybe : String -> Maybe Bool
boolMaybe s =
    case s of
        "on" ->
            Just True

        "off" ->
            Just False

        _ ->
            Nothing


iif : Bool -> a -> a -> a
iif c a b =
    if c then
        a

    else
        b


storage : Model -> List (Html Msg)
storage model =
    let
        caps =
            model.capabilities

        estimate =
            case caps.storageEstimate of
                Just e ->
                    "Using about " ++ mb e.usage ++ " of " ++ mb e.quota ++ " available to this origin."

                Nothing ->
                    "Storage estimate unavailable."
    in
    [ p [] [ text "Documents are autosaved to this browser's IndexedDB. Browsers can evict origin storage, so save .framewise files for anything you need to keep." ]
    , p [ A.class "hint" ] [ text estimate ]
    , p [ A.class "hint" ] [ text (iif caps.persistentStorage "Persistent storage is granted." "Persistent storage has not been granted.") ]
    , div [ A.class "button-row" ]
        [ button [ A.class "btn small", E.onClick RequestPersistentStorage ] [ text "Request persistent storage" ]
        , button [ A.class "btn small", E.onClick (ClearStorage "recents") ] [ text "Clear recents" ]
        , button [ A.class "btn small", E.onClick (ClearStorage "recoveries") ] [ text "Clear recovery checkpoints" ]
        , button [ A.class "btn small", E.onClick (ClearStorage "thumbnails") ] [ text "Clear thumbnails" ]
        , button [ A.class "btn small danger", E.onClick (ClearStorage "everything") ] [ text "Reset application state" ]
        ]
    , p [ A.class "hint" ] [ text "No telemetry, analytics or remote fonts. Nothing is sent anywhere unless you export or save." ]
    ]


mb : Int -> String
mb bytes =
    String.fromFloat (toFloat (round (toFloat bytes / 100000)) / 10) ++ " MB"



-- SHORTCUTS


shortcuts : Model -> String -> List (Html Msg)
shortcuts model query =
    let
        q =
            String.toLower query

        commands =
            Commands.all
                |> List.filter (\c -> c.shortcut /= Nothing)
                |> List.filter (\c -> String.isEmpty q || String.contains q (String.toLower (c.label ++ " " ++ c.category)))
    in
    [ div [ A.class "search-field" ] [ Icons.icon "search", input [ A.type_ "search", A.placeholder "Search shortcuts", A.value query, A.autofocus True, E.onInput ShortcutSearch ] [] ]
    , Html.table [ A.class "shortcut-table" ]
        [ Html.thead [] [ Html.tr [] [ Html.th [] [ text "Command" ], Html.th [] [ text "Category" ], Html.th [] [ text "Shortcut" ], Html.th [] [ text "Context" ] ] ]
        , Html.tbody []
            (List.map
                (\c ->
                    Html.tr []
                        [ Html.td [] [ text c.label ]
                        , Html.td [] [ text c.category ]
                        , Html.td [] [ Html.kbd [] [ text (c.shortcut |> Maybe.map (Commands.shortcutLabel model.isMac) |> Maybe.withDefault "") ] ]
                        , Html.td [] [ text (c.shortcut |> Maybe.map .context |> Maybe.withDefault "") ]
                        ]
                )
                commands
            )
        ]
    , p [ A.class "hint" ] [ text "Tool letters (V, A, H, Z, P, R, O, L, Y, T, M) apply when the canvas has focus. Space plays when the timeline has focus and pans the canvas while held." ]
    ]



-- ABOUT


about : Model -> List (Html Msg)
about model =
    [ div [ A.class "about" ]
        [ Icons.icon "logo"
        , h3 [] [ text ("Framewise " ++ model.version) ]
        , p [] [ text "Open-source, local-first SVG and vector animation editor. MIT licence." ]
        , p [ A.class "hint" ] [ text ("Document schema version " ++ String.fromInt Domain.Document.currentSchemaVersion ++ ". Portable animation format version 1.") ]
        , p [] [ Html.a [ A.href "https://github.com/Vheissu/framewise", A.target "_blank", A.rel "noopener noreferrer" ] [ text "github.com/Vheissu/framewise" ] ]
        , div [ A.class "button-row" ]
            [ button [ A.class "btn small", E.onClick (SetDialog (DocsDialog "licences" "")) ] [ text "Open source licences" ]
            , button [ A.class "btn small", E.onClick (SetDialog (DocsDialog "whats-new" "")) ] [ text "What's new" ]
            ]
        , h3 [] [ text "Capabilities detected" ]
        , ul [ A.class "capability-list" ]
            (List.map
                (\( labelText, ok ) -> li [ A.classList [ ( "ok", ok ) ] ] [ Icons.icon (iif ok "check" "close"), text labelText ])
                [ ( "Native file pickers", model.capabilities.nativeFilePickers )
                , ( "IndexedDB", model.capabilities.indexedDb )
                , ( "Clipboard write", model.capabilities.clipboardWrite )
                , ( "Clipboard read", model.capabilities.clipboardRead )
                , ( "OffscreenCanvas", model.capabilities.offscreenCanvas )
                , ( "WebCodecs", model.capabilities.webCodecs )
                , ( "Service worker", model.capabilities.serviceWorker )
                , ( "BroadcastChannel", model.capabilities.broadcastChannel )
                ]
            )
        ]
    ]



-- DOCS


docs : String -> String -> List (Html Msg)
docs pageId query =
    let
        results =
            Docs.search query
    in
    [ div [ A.class "docs-layout" ]
        [ div [ A.class "docs-nav" ]
            (div [ A.class "search-field" ] [ Icons.icon "search", input [ A.type_ "search", A.placeholder "Search docs", A.value query, E.onInput DocsSearch ] [] ]
                :: List.map
                    (\p -> button [ A.class "docs-link", A.classList [ ( "active", p.id == pageId ) ], E.onClick (SetDocsPage p.id) ] [ text p.title ])
                    Docs.pages
            )
        , div [ A.class "docs-content" ]
            (if not (String.isEmpty (String.trim query)) then
                h3 [] [ text ("Results for \"" ++ query ++ "\"") ]
                    :: (if List.isEmpty results then
                            [ p [ A.class "hint" ] [ text "No matches." ] ]

                        else
                            List.map
                                (\( page, heading, para ) ->
                                    div [ A.class "docs-result" ]
                                        [ button [ A.class "link", E.onClick (SetDocsPage page.id) ] [ text (page.title ++ " › " ++ heading) ]
                                        , p [] [ text para ]
                                        ]
                                )
                                results
                       )

             else
                case Docs.find pageId of
                    Just page ->
                        h3 [] [ text page.title ]
                            :: List.concatMap
                                (\( heading, paragraphs ) ->
                                    Html.h4 [] [ text heading ] :: List.map (\para -> p [] [ text para ]) paragraphs
                                )
                                page.sections

                    Nothing ->
                        [ p [] [ text "Page not found." ] ]
            )
        ]
    ]



-- RECOVERY


recovery : Model -> List (Html Msg)
recovery model =
    if List.isEmpty model.recoveries then
        [ p [] [ text "No recovery checkpoints. Autosaves newer than their last file save appear here after an interrupted session." ]
        , actions [ button [ A.class "btn primary", E.onClick CloseDialog ] [ text "Close" ] ]
        ]

    else
        [ p [ A.class "hint" ] [ text "Opening a recovery copy never overwrites a file you saved; it opens as a separate document you can Save As." ]
        , Html.table [ A.class "recovery-table" ]
            [ Html.thead [] [ Html.tr [] [ Html.th [] [ text "Document" ], Html.th [] [ text "Autosaved" ], Html.th [] [ text "File save" ], Html.th [] [ text "Size" ], Html.th [] [ text "" ] ] ]
            , Html.tbody []
                (List.map
                    (\r ->
                        Html.tr []
                            [ Html.td [] [ text r.name ]
                            , Html.td [] [ text ("rev " ++ String.fromInt r.revision ++ " · " ++ relativeTime model.now r.checkpointAt) ]
                            , Html.td [] [ text (r.savedRevision |> Maybe.map (\s -> "rev " ++ String.fromInt s) |> Maybe.withDefault "never") ]
                            , Html.td [] [ text (String.fromInt (r.byteLength // 1000) ++ " kB") ]
                            , Html.td [ A.class "button-row" ]
                                [ button [ A.class "btn small primary", A.disabled (not r.decodable), A.title (iif r.decodable "Open" "This checkpoint could not be decoded; download it instead"), E.onClick (OpenRecovery r.documentId) ] [ text "Open Recovery Copy" ]
                                , button [ A.class "btn small", E.onClick (DownloadRecovery r.documentId) ] [ text "Download Backup" ]
                                , button [ A.class "btn small danger", E.onClick (DiscardRecovery r.documentId) ] [ text "Discard" ]
                                ]
                            ]
                    )
                    model.recoveries
                )
            ]
        , actions [ button [ A.class "btn", E.onClick CloseDialog ] [ text "Close" ] ]
        ]


relativeTime : Time.Posix -> Int -> String
relativeTime now ms =
    let
        diff =
            (Time.posixToMillis now - ms) // 1000
    in
    if diff < 60 then
        "just now"

    else if diff < 3600 then
        String.fromInt (diff // 60) ++ " min ago"

    else if diff < 86400 then
        String.fromInt (diff // 3600) ++ " h ago"

    else
        String.fromInt (diff // 86400) ++ " d ago"



-- HISTORY


history : Model -> List (Html Msg)
history model =
    case Model.activeDoc model of
        Nothing ->
            [ p [] [ text "No document open." ] ]

        Just open ->
            let
                past =
                    History.entries open.history

                future =
                    open.history.future |> List.map Tuple.first
            in
            [ p [ A.class "hint" ] [ text ("Revision " ++ String.fromInt open.revision ++ ". Click an entry to undo back to that point; redo entries restore forward.") ]
            , ul [ A.class "history-list" ]
                (List.indexedMap
                    (\i d -> li [] [ button [ A.class "history-entry", E.onClick (HistoryJump -(i + 1)) ] [ Icons.icon "undo", text d ] ])
                    past
                    ++ [ li [ A.class "history-current" ] [ Icons.icon "check", text "Current state" ] ]
                    ++ List.indexedMap
                        (\i d -> li [] [ button [ A.class "history-entry redo", E.onClick (HistoryJump (i + 1)) ] [ Icons.icon "redo", text d ] ])
                        future
                )
            , actions [ button [ A.class "btn primary", E.onClick CloseDialog ] [ text "Close" ] ]
            ]



-- STAGGER


stagger : { startFrame : String, spacing : String, order : String } -> List (Html Msg)
stagger form =
    [ p [ A.class "hint" ] [ text "Shifts each selected layer's animation so it starts at the given frame plus the spacing times its position in the order." ]
    , labelled "Start frame" (input [ A.type_ "text", A.value form.startFrame, E.onInput (StaggerFormChanged "start") ] [])
    , labelled "Spacing (frames)" (input [ A.type_ "text", A.value form.spacing, E.onInput (StaggerFormChanged "spacing") ] [])
    , labelled "Order" (UI.select "Order" form.order [ ( "layer", "Layer order" ), ( "selection", "Selection order" ), ( "reverse", "Reverse selection" ) ] (StaggerFormChanged "order"))
    , actions [ button [ A.class "btn", E.onClick CloseDialog ] [ text "Cancel" ], button [ A.class "btn primary", E.onClick ApplyStagger ] [ text "Apply" ] ]
    ]
