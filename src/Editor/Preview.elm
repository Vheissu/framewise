module Editor.Preview exposing (view)

{-| Full-screen preview: a clean stage using the same evaluator and renderer
as the canvas, with transport controls and no editor overlays.
-}

import App.Edit as Edit
import App.Fields as Fields
import App.Model as Model exposing (Model)
import App.Msg exposing (Msg(..))
import Domain.Evaluate as Evaluate
import Domain.Fps as Fps
import Domain.Scene as Scene
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes as A
import Html.Events as E
import Render.Scene as Render
import Render.SvgDoc as SvgDoc
import UI.Fields as UI
import UI.Icons as Icons


view : Model -> Html Msg
view model =
    case ( Model.activeDoc model, Model.activeScene model ) of
        ( Just open, Just scene ) ->
            let
                frame =
                    Edit.currentFrame model

                pb =
                    model.editor.playback

                resolved =
                    Evaluate.evaluateScene open.document scene.id frame

                stage =
                    case resolved of
                        Just r ->
                            SvgDoc.toHtml
                                (Render.renderScene
                                    { idPrefix = "preview"
                                    , assetUrls = open.assetUrls
                                    , includeBackground = True
                                    , includeIds = False
                                    , title = Just scene.name
                                    , description = Nothing
                                    , standalone = False
                                    }
                                    r
                                )

                        Nothing ->
                            text ""
            in
            div [ A.class "preview", A.attribute "role" "region", A.attribute "aria-label" "Preview" ]
                [ div [ A.class "preview-top" ]
                    [ span [ A.class "preview-title" ] [ text (open.document.metadata.name ++ " · " ++ scene.name) ]
                    , span [ A.class "preview-meta" ] [ text (String.fromFloat scene.width ++ " × " ++ String.fromFloat scene.height ++ " · " ++ Fps.toLabel scene.fps ++ " fps") ]
                    , button [ A.class "btn", E.onClick ClosePreview ] [ Icons.icon "close", text "Close (Esc)" ]
                    ]
                , div [ A.class "preview-stage", A.classList [ ( "checker", scene.background == Scene.Transparent ) ] ]
                    [ div [ A.class "preview-frame", A.style "aspect-ratio" (String.fromFloat scene.width ++ " / " ++ String.fromFloat scene.height) ] [ stage ] ]
                , div [ A.class "preview-controls", A.attribute "role" "toolbar", A.attribute "aria-label" "Preview playback" ]
                    [ UI.iconButton { icon = "skip-start", label = "Restart", active = False, onClick = PreviewSeek 0, disabled = False }
                    , button [ A.class "icon-button play-button", A.classList [ ( "active", pb.playing ) ], A.attribute "aria-label" (iif pb.playing "Pause" "Play"), E.onClick TogglePlay ] [ Icons.icon (iif pb.playing "pause" "play") ]
                    , UI.iconButton { icon = "stop", label = "Stop all motion", active = False, onClick = StopPlayback, disabled = False }
                    , input
                        [ A.type_ "range"
                        , A.class "scrubber"
                        , A.min "0"
                        , A.max (String.fromInt scene.durationFrames)
                        , A.step "1"
                        , A.value (String.fromFloat frame)
                        , A.attribute "aria-label" "Scrub frame"
                        , E.onInput (\s -> PreviewSeek (String.toFloat s |> Maybe.withDefault 0))
                        ]
                        []
                    , span [ A.class "timecode" ] [ text (String.fromInt (round frame) ++ " / " ++ String.fromInt scene.durationFrames ++ "  " ++ Fps.toTimecode scene.fps (round frame)) ]
                    , UI.select "Loop" (Scene.playbackModeToCode (Maybe.withDefault scene.playbackMode pb.loopOverride)) [ ( "once", "Once" ), ( "repeat", "Repeat" ), ( "pingpong", "Ping-pong" ) ] (\c -> SetLoopMode (Scene.playbackModeFromCode c |> Maybe.withDefault scene.playbackMode))
                    , UI.select "Speed" (String.fromFloat pb.speed) [ ( "0.25", "0.25×" ), ( "0.5", "0.5×" ), ( "1", "1×" ), ( "1.5", "1.5×" ), ( "2", "2×" ) ] (\s -> SetSpeed (String.toFloat s |> Maybe.withDefault 1))
                    , UI.iconButton { icon = "fullscreen", label = "Toggle full screen", active = False, onClick = PreviewToggleFull, disabled = False }
                    , button [ A.class "btn small", E.onClick OpenExport ] [ Icons.icon "export", text "Export" ]
                    , let
                        _ =
                            Fields.displayValue
                      in
                      text ""
                    ]
                ]

        _ ->
            div [ A.class "preview" ] [ text "Loading…" ]


iif : Bool -> a -> a -> a
iif c a b =
    if c then
        a

    else
        b
