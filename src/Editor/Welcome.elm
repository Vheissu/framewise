module Editor.Welcome exposing (view)

import App.Examples as Examples
import App.Model as Model exposing (Model)
import App.Msg exposing (Msg(..))
import App.Presets as Presets
import Html exposing (Html, button, div, h1, h2, p, section, span, text)
import Html.Attributes as A
import Html.Events as E
import Time
import UI.Icons as Icons


view : Model -> Html Msg
view model =
    div [ A.class "welcome" ]
        [ Html.header [ A.class "welcome-header" ]
            [ div [ A.class "welcome-brand" ] [ Icons.icon "logo", h1 [] [ text "Framewise" ] ]
            , p [ A.class "welcome-tagline" ] [ text "A vector animation editor that runs in your browser. Documents stay on this computer." ]
            , div [ A.class "welcome-actions" ]
                [ button [ A.class "btn primary", E.onClick (RunCommand "file.new") ] [ Icons.icon "plus", text "New Document" ]
                , button [ A.class "btn", E.onClick OpenFile ] [ Icons.icon "folder", text "Open File" ]
                , button [ A.class "btn", E.onClick ImportSvg ] [ Icons.icon "import", text "Import SVG" ]
                , button [ A.class "btn", E.onClick (SetDialog (Model.ShortcutsDialog "")) ] [ Icons.icon "command", text "Shortcuts" ]
                , button [ A.class "btn", E.onClick (SetDialog (Model.DocsDialog "getting-started" "")) ] [ Icons.icon "info", text "Documentation" ]
                , button [ A.class "btn", E.onClick (SetDialog (Model.PreferencesDialog Model.GeneralTab "")) ] [ Icons.icon "settings", text "Settings" ]
                ]
            ]
        , if List.isEmpty model.recoveries then
            text ""

          else
            section [ A.class "welcome-recovery" ]
                [ div [ A.class "recovery-banner" ]
                    [ Icons.icon "warning"
                    , span [] [ text (String.fromInt (List.length model.recoveries) ++ " document(s) have autosaved changes newer than their last file save.") ]
                    , button [ A.class "btn small", E.onClick (SetDialog Model.RecoveryDialog) ] [ text "Recover Unsaved Work" ]
                    ]
                ]
        , div [ A.class "welcome-grid" ]
            [ section [ A.class "welcome-section" ]
                [ h2 [] [ text "Start from a preset" ]
                , div [ A.class "preset-list" ]
                    (List.map
                        (\preset ->
                            button [ A.class "preset", E.onClick (NewDocumentFromPreset preset.id), A.title (preset.category ++ " preset") ]
                                [ div [ A.class "preset-shape", A.style "aspect-ratio" (String.fromFloat preset.width ++ " / " ++ String.fromFloat preset.height) ] []
                                , span [ A.class "preset-label" ] [ text preset.label ]
                                , span [ A.class "preset-meta" ] [ text (String.fromFloat preset.width ++ " × " ++ String.fromFloat preset.height ++ " · " ++ String.fromInt preset.fps ++ " fps") ]
                                ]
                        )
                        Presets.all
                    )
                ]
            , section [ A.class "welcome-section" ]
                [ h2 [] [ text "Recent" ]
                , if List.isEmpty model.recents then
                    div [ A.class "empty" ]
                        [ p [] [ text "Documents you create are autosaved in this browser and listed here. Open an example to start with something that already moves." ] ]

                  else
                    div [ A.class "recent-list" ]
                        (List.map (recentCard model) (List.take model.preferences.recentLimit model.recents))
                , p [ A.class "welcome-note" ] [ text "Recent entries are browser copies. The .framewise files you save are the portable source of truth; the browser can evict its storage." ]
                ]
            , section [ A.class "welcome-section" ]
                [ h2 [] [ text "Examples" ]
                , div [ A.class "example-list" ]
                    (List.map
                        (\ex ->
                            button [ A.class "example", E.onClick (OpenExample ex.id) ]
                                [ span [ A.class "example-name" ] [ text ex.name ]
                                , span [ A.class "example-desc" ] [ text ex.description ]
                                ]
                        )
                        Examples.all
                    )
                ]
            ]
        , Html.footer [ A.class "welcome-footer" ]
            [ span [] [ text ("Framewise " ++ model.version) ]
            , button [ A.class "link", E.onClick (SetDialog (Model.DocsDialog "whats-new" "")) ] [ text "What's new" ]
            , Html.a [ A.href "https://github.com/Vheissu/framewise", A.target "_blank", A.rel "noopener noreferrer" ] [ text "Source on GitHub" ]
            , span [ A.class "welcome-offline" ]
                [ text
                    (if model.offlineReady then
                        "Offline ready"

                     else
                        "Local-first · nothing leaves this device"
                    )
                ]
            ]
        ]


recentCard : Model -> Model.RecentEntry -> Html Msg
recentCard model r =
    div [ A.class "recent" ]
        [ button [ A.class "recent-open", E.onClick (OpenRecent r.documentId) ]
            [ div [ A.class "recent-thumb" ] [ Icons.icon "file" ]
            , div [ A.class "recent-body" ]
                [ span [ A.class "recent-name" ] [ text r.name ]
                , span [ A.class "recent-meta" ]
                    [ text (String.fromFloat r.width ++ " × " ++ String.fromFloat r.height ++ " · " ++ String.fromInt r.sceneCount ++ " scene" ++ plural r.sceneCount ++ " · " ++ relativeTime model.now r.modifiedAt) ]
                , span [ A.class "recent-status" ]
                    [ text
                        (case r.fileName of
                            Just f ->
                                f

                            Nothing ->
                                "Browser copy only"
                        )
                    ]
                ]
            ]
        , button [ A.class "icon-button", A.title "Remove from recents", A.attribute "aria-label" ("Remove " ++ r.name ++ " from recents"), E.onClick (RemoveRecent r.documentId) ] [ Icons.icon "close" ]
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
