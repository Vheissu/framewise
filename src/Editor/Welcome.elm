module Editor.Welcome exposing (view)

import App.Examples as Examples
import App.Model as Model exposing (Model)
import App.Msg exposing (Msg(..))
import App.Presets as Presets
import Dict
import Domain.Evaluate as Evaluate
import Html exposing (Html, button, div, h1, h2, p, section, span, text)
import Html.Attributes as A
import Html.Events as E
import Html.Lazy
import Render.Scene as Render
import Render.SvgDoc as SvgDoc
import Time
import UI.Icons as Icons


view : Model -> Html Msg
view model =
    div [ A.class "welcome" ]
        [ sidebar model
        , Html.main_ [ A.class "welcome-main" ]
            [ if List.isEmpty model.recoveries then
                text ""

              else
                div [ A.class "recovery-banner" ]
                    [ Icons.icon "warning"
                    , span [] [ text (String.fromInt (List.length model.recoveries) ++ " document(s) have autosaved changes newer than their last file save.") ]
                    , button [ A.class "btn small", E.onClick (SetDialog Model.RecoveryDialog) ] [ text "Recover Unsaved Work" ]
                    ]
            , section [ A.class "welcome-section" ]
                [ div [ A.class "welcome-section-head" ]
                    [ h2 [] [ text "New document" ]
                    , span [ A.class "welcome-section-note" ] [ text "Size, frame rate and length can be changed later in Scene Settings." ]
                    ]
                , div [ A.class "preset-list" ] (List.map presetButton Presets.all)
                ]
            , section [ A.class "welcome-section" ]
                [ div [ A.class "welcome-section-head" ]
                    [ h2 [] [ text "Recent" ]
                    , span [ A.class "welcome-section-note" ] [ text "Browser copies. The .framewise files you save are the ones to keep." ]
                    ]
                , if List.isEmpty model.recents then
                    p [ A.class "empty" ] [ text "Nothing yet. Documents you create are autosaved in this browser and appear here." ]

                  else
                    div [ A.class "recent-list", A.attribute "role" "list" ]
                        (List.map (recentRow model) (List.take model.preferences.recentLimit model.recents))
                ]
            , section [ A.class "welcome-section" ]
                [ div [ A.class "welcome-section-head" ]
                    [ h2 [] [ text "Examples" ]
                    , span [ A.class "welcome-section-note" ] [ text "Each opens as a new document you can take apart." ]
                    ]
                , div [ A.class "example-list" ]
                    (List.map
                        (\ex ->
                            button [ A.class "example", E.onClick (OpenExample ex.id) ]
                                [ Html.Lazy.lazy exampleThumb ex.id
                                , span [ A.class "example-name" ] [ text ex.name ]
                                , span [ A.class "example-desc" ] [ text ex.description ]
                                ]
                        )
                        Examples.all
                    )
                ]
            ]
        ]


sidebar : Model -> Html Msg
sidebar model =
    Html.aside [ A.class "welcome-side" ]
        [ div [ A.class "welcome-brand" ]
            [ Icons.icon "logo"
            , h1 [] [ text "Framewise" ]
            ]
        , p [ A.class "welcome-tagline" ] [ text "A vector animation editor that runs in your browser. Documents stay on this computer." ]
        , div [ A.class "welcome-actions" ]
            [ button [ A.class "btn primary", E.onClick (RunCommand "file.new") ] [ Icons.icon "plus", text "New Document" ]
            , button [ A.class "side-link", E.onClick OpenFile ] [ Icons.icon "folder", text "Open File" ]
            , button [ A.class "side-link", E.onClick ImportSvg ] [ Icons.icon "import", text "Import SVG" ]
            ]
        , div [ A.class "welcome-links" ]
            [ button [ A.class "side-link", E.onClick (SetDialog (Model.DocsDialog "getting-started" "")) ] [ Icons.icon "info", text "Documentation" ]
            , button [ A.class "side-link", E.onClick (SetDialog (Model.ShortcutsDialog "")) ] [ Icons.icon "command", text "Shortcuts" ]
            , button [ A.class "side-link", E.onClick (SetDialog (Model.PreferencesDialog Model.GeneralTab "")) ] [ Icons.icon "settings", text "Settings" ]
            ]
        , Html.footer [ A.class "welcome-footer" ]
            [ span [] [ text ("Version " ++ model.version) ]
            , button [ A.class "link", E.onClick (SetDialog (Model.DocsDialog "whats-new" "")) ] [ text "What's new" ]
            , Html.a [ A.href "https://github.com/Vheissu/framewise", A.target "_blank", A.rel "noopener noreferrer" ] [ text "Source on GitHub" ]
            , span [ A.class "welcome-offline" ]
                [ text
                    (if model.offlineReady then
                        "Available offline"

                     else
                        "Nothing leaves this device"
                    )
                ]
            ]
        ]


presetButton : Presets.Preset -> Html Msg
presetButton preset =
    let
        ( w, h ) =
            if preset.width >= preset.height then
                ( 40, 40 * preset.height / preset.width )

            else
                ( 40 * preset.width / preset.height, 40 )
    in
    button [ A.class "preset", E.onClick (NewDocumentFromPreset preset.id), A.title (preset.label ++ ", " ++ String.fromInt preset.fps ++ " fps") ]
        [ span [ A.class "preset-frame" ]
            [ span [ A.class "preset-shape", A.style "width" (String.fromInt (round w) ++ "px"), A.style "height" (String.fromInt (round h) ++ "px") ] [] ]
        , span [ A.class "preset-label" ] [ text preset.label ]
        , span [ A.class "preset-meta" ] [ text (String.fromFloat preset.width ++ " × " ++ String.fromFloat preset.height) ]
        ]


{-| A still of the example, rendered by the same evaluator and renderer the
editor uses. Taken partway through so moving examples show some motion.
-}
exampleThumb : String -> Html Msg
exampleThumb exampleId =
    let
        sceneId =
            "thumb-scene"

        rendered =
            Examples.build exampleId "thumb" sceneId "0"
                |> Maybe.andThen
                    (\doc ->
                        Dict.get sceneId doc.scenes
                            |> Maybe.andThen (\scene -> Evaluate.evaluateScene doc sceneId (toFloat scene.durationFrames * 0.35))
                    )
    in
    span [ A.class "example-thumb", A.attribute "aria-hidden" "true" ]
        [ case rendered of
            Just r ->
                SvgDoc.toHtml
                    (Render.renderScene
                        { idPrefix = "thumb-" ++ exampleId
                        , assetUrls = Dict.empty
                        , includeBackground = True
                        , includeIds = False
                        , title = Nothing
                        , description = Nothing
                        , standalone = False
                        }
                        r
                    )

            Nothing ->
                text ""
        ]


recentRow : Model -> Model.RecentEntry -> Html Msg
recentRow model r =
    div [ A.class "recent", A.attribute "role" "listitem" ]
        [ button [ A.class "recent-open", E.onClick (OpenRecent r.documentId) ]
            [ span [ A.class "recent-thumb" ] [ Icons.icon "file" ]
            , span [ A.class "recent-name" ] [ text r.name ]
            , span [ A.class "recent-meta" ] [ text (String.fromFloat r.width ++ " × " ++ String.fromFloat r.height) ]
            , span [ A.class "recent-meta" ] [ text (String.fromInt r.sceneCount ++ " scene" ++ plural r.sceneCount) ]
            , span [ A.class "recent-status" ]
                [ text
                    (case r.fileName of
                        Just f ->
                            f

                        Nothing ->
                            "Browser copy only"
                    )
                ]
            , span [ A.class "recent-meta recent-time" ] [ text (relativeTime model.now r.modifiedAt) ]
            ]
        , button [ A.class "icon-button tiny", A.title "Remove from recents", A.attribute "aria-label" ("Remove " ++ r.name ++ " from recents"), E.onClick (RemoveRecent r.documentId) ] [ Icons.icon "close" ]
        ]


plural : Int -> String
plural n =
    if n == 1 then
        ""

    else
        "s"


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
