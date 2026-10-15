module Editor.ExportStudio exposing (view)

{-| Export Studio: format list with availability, target settings, a live
compatibility report and a preview of the actual output (SMIL previews run
natively in the browser).
-}

import App.Edit as Edit
import App.Model as Model exposing (ExportForm, Model)
import App.Msg exposing (Msg(..))
import Dict
import Domain.Document exposing (Document)
import Domain.Evaluate as Evaluate
import Domain.Property as Property
import Domain.Scene exposing (Scene)
import Export.Capability as Capability
import Export.Css
import Export.Format as Format exposing (Availability(..), Format(..))
import Export.Smil as Smil
import Html exposing (Html, button, div, h2, input, label, p, span, text)
import Html.Attributes as A
import Html.Events as E
import Render.Scene as Render
import Render.SvgDoc as SvgDoc
import UI.Fields as UI
import UI.Icons as Icons


view : Model -> ExportForm -> Html Msg
view model form =
    case ( Model.activeDoc model, Model.activeScene model ) of
        ( Just open, Just scene ) ->
            let
                report =
                    Capability.report form.format scene

                availability =
                    Format.availability form.format

                blocked =
                    report.unsupportedCount > 0 && not form.skipUnsupported && Format.isAnimated form.format && form.format /= PngSequence
            in
            div [ A.class "export-studio" ]
                [ div [ A.class "export-formats" ]
                    [ h2 [] [ text "Format" ]
                    , div [ A.class "format-list", A.attribute "role" "radiogroup", A.attribute "aria-label" "Export format" ]
                        (List.map (formatButton form) Format.all)
                    , div [ A.class "export-scope" ]
                        [ h2 [] [ text "Scenes" ]
                        , label [ A.class "radio" ] [ input [ A.type_ "radio", A.name "scope", A.checked (not form.allScenes), E.onClick (ExportFormChanged (\f -> { f | allScenes = False })) ] [], text ("Current scene (" ++ scene.name ++ ")") ]
                        , label [ A.class "radio" ] [ input [ A.type_ "radio", A.name "scope", A.checked form.allScenes, E.onClick (ExportFormChanged (\f -> { f | allScenes = True })) ] [], text ("All scenes (" ++ String.fromInt (Dict.size open.document.scenes) ++ ")") ]
                        ]
                    ]
                , div [ A.class "export-center" ]
                    [ h2 [] [ text (Format.label form.format) ]
                    , p [ A.class "format-description" ] [ text (Format.description form.format) ]
                    , case availability of
                        Unavailable reason ->
                            div [ A.class "notice error" ] [ Icons.icon "warning", span [] [ text reason ] ]

                        Available ->
                            previewPane model open.document scene form
                    , reportPane form report
                    ]
                , div [ A.class "export-settings" ]
                    [ h2 [] [ text "Settings" ]
                    , settingsPane model scene form
                    , h2 [] [ text "Jobs" ]
                    , jobsPane model
                    , div [ A.class "export-actions" ]
                        [ button [ A.class "btn", E.onClick CloseDialog ] [ text "Close" ]
                        , button
                            [ A.class "btn primary"
                            , A.disabled (availability /= Available || blocked)
                            , A.title
                                (if blocked then
                                    "Unsupported tracks block this export. Skip them or choose another format."

                                 else
                                    "Export"
                                )
                            , E.onClick RunExport
                            ]
                            [ Icons.icon "export", text "Export" ]
                        ]
                    , if blocked then
                        div [ A.class "notice warning" ]
                            [ Icons.icon "warning"
                            , span [] [ text "Some tracks cannot be represented. Choose Skip Affected Tracks, or switch to the HTML player which supports everything." ]
                            , button [ A.class "btn small", E.onClick (SelectExportFormat HtmlPlayer) ] [ text "Switch to HTML Player" ]
                            ]

                      else
                        text ""
                    , let
                        _ =
                            Edit.currentFrame model
                      in
                      text ""
                    ]
                ]

        _ ->
            text ""


formatButton : ExportForm -> Format -> Html Msg
formatButton form format =
    let
        availability =
            Format.availability format

        selected =
            form.format == format
    in
    button
        [ A.class "format-option"
        , A.classList [ ( "selected", selected ), ( "unavailable", availability /= Available ) ]
        , A.attribute "role" "radio"
        , A.attribute "aria-checked"
            (if selected then
                "true"

             else
                "false"
            )
        , E.onClick (SelectExportFormat format)
        ]
        [ span [ A.class "format-name" ] [ text (Format.label format) ]
        , span [ A.class "format-ext" ] [ text ("." ++ Format.extension format) ]
        , case availability of
            Unavailable _ ->
                span [ A.class "pill unsupported" ] [ text "Not available" ]

            Available ->
                text ""
        ]


previewPane : Model -> Document -> Scene -> ExportForm -> Html Msg
previewPane model doc scene form =
    let
        frame =
            String.toFloat form.frame |> Maybe.withDefault (Edit.currentFrame model)

        staticPreview f =
            case Evaluate.evaluateScene doc scene.id f of
                Just r ->
                    SvgDoc.toHtml
                        (Render.renderScene
                            { idPrefix = "exp"
                            , assetUrls = Maybe.map .assetUrls (Model.activeDoc model) |> Maybe.withDefault Dict.empty
                            , includeBackground = form.includeBackground
                            , includeIds = False
                            , title = Nothing
                            , description = Nothing
                            , standalone = False
                            }
                            r
                        )

                Nothing ->
                    text ""

        content =
            case form.format of
                AnimatedSvg ->
                    case Smil.export { includeBackground = form.includeBackground, title = Nothing, description = Nothing, skipUnsupported = True } doc scene of
                        Ok r ->
                            -- the SMIL output itself, so the preview is the actual artefact
                            Html.node "fw-svg-preview" [ A.attribute "data-svg" r.svg, A.class "svg-preview" ] []

                        Err _ ->
                            staticPreview frame

                SvgCss ->
                    case Export.Css.export { includeBackground = form.includeBackground, title = Nothing, description = Nothing, skipUnsupported = True, reducedMotionPause = False } doc scene of
                        Ok r ->
                            Html.node "fw-svg-preview" [ A.attribute "data-svg" r.svg, A.class "svg-preview" ] []

                        Err _ ->
                            staticPreview frame

                HtmlPlayer ->
                    staticPreview (Edit.currentFrame model)

                PngSequence ->
                    staticPreview (String.toFloat form.rangeStart |> Maybe.withDefault 0)

                _ ->
                    staticPreview frame
    in
    div [ A.class "export-preview", A.classList [ ( "checker", not form.includeBackground || scene.background == Domain.Scene.Transparent ) ] ]
        [ div [ A.class "export-preview-frame", A.style "aspect-ratio" (String.fromFloat scene.width ++ " / " ++ String.fromFloat scene.height) ] [ content ]
        , span [ A.class "hint" ]
            [ text
                (case form.format of
                    AnimatedSvg ->
                        "Live preview of the generated SMIL file."

                    SvgCss ->
                        "Live preview of the generated SVG with its embedded CSS."

                    HtmlPlayer ->
                        "The player renders the same evaluated frames; preview shows the current frame."

                    PngSequence ->
                        "First frame of the range."

                    _ ->
                        "Frame " ++ form.frame
                )
            ]
        ]


reportPane : ExportForm -> Capability.Report -> Html Msg
reportPane form report =
    div [ A.class "export-report" ]
        [ div [ A.class "report-summary" ]
            [ span [ A.class "pill exact" ] [ text (String.fromInt report.exactCount ++ " exact") ]
            , span [ A.class "pill baked" ] [ text (String.fromInt report.bakedCount ++ " baked") ]
            , span [ A.class "pill unsupported" ] [ text (String.fromInt report.unsupportedCount ++ " unsupported") ]
            , button [ A.class "link", E.onClick (ExportFormChanged (\f -> { f | showReport = not f.showReport })) ]
                [ text
                    (if form.showReport then
                        "Hide details"

                     else
                        "Show details"
                    )
                ]
            ]
        , if form.showReport then
            div [ A.class "report-list" ]
                (if List.isEmpty report.items then
                    [ span [ A.class "hint" ] [ text "Nothing to report." ] ]

                 else
                    report.items
                        |> List.filter (\i -> i.status /= Capability.Exact)
                        |> List.map
                            (\i ->
                                div [ A.class ("report-item " ++ String.toLower (Capability.statusLabel i.status)) ]
                                    [ span [ A.class "pill" ] [ text (Capability.statusLabel i.status) ]
                                    , button [ A.class "link", E.onClick (SelectNodes [ i.nodeId ] False) ] [ text i.nodeName ]
                                    , span [] [ text ((i.property |> Maybe.map (\p -> Property.pathLabel p ++ ": ") |> Maybe.withDefault "") ++ message i.status) ]
                                    ]
                            )
                        |> (\items ->
                                if List.isEmpty items then
                                    [ span [ A.class "hint" ] [ text "Every track exports exactly." ] ]

                                else
                                    items
                           )
                )

          else
            text ""
        ]


message : Capability.Status -> String
message s =
    case s of
        Capability.Exact ->
            ""

        Capability.Baked m ->
            m

        Capability.Unsupported m ->
            m


settingsPane : Model -> Scene -> ExportForm -> Html Msg
settingsPane model scene form =
    let
        change f =
            ExportFormChanged f

        textInput id labelText value toMsg =
            label [ A.class "text-field" ]
                [ span [ A.class "field-label" ] [ text labelText ]
                , input [ A.id id, A.type_ "text", A.value value, A.attribute "aria-label" labelText, E.onInput toMsg ] []
                ]

        common =
            [ UI.checkbox "Include background" form.includeBackground (\v -> change (\f -> { f | includeBackground = v })) ]

        metadata =
            [ textInput "export-title" "Title (<title>)" form.title (\v -> change (\f -> { f | title = v }))
            , textInput "export-desc" "Description (<desc>)" form.description (\v -> change (\f -> { f | description = v }))
            ]

        frameField =
            textInput "export-frame" ("Frame (0–" ++ String.fromInt scene.durationFrames ++ ")") form.frame (\v -> change (\f -> { f | frame = v }))

        scaleField =
            UI.select "Scale" (String.fromFloat form.scale) [ ( "1", "1×" ), ( "2", "2×" ), ( "3", "3×" ) ] (\v -> change (\f -> { f | scale = String.toFloat v |> Maybe.withDefault 1 }))

        skip =
            UI.checkbox "Skip affected tracks (export without unsupported animation)" form.skipUnsupported (\v -> change (\f -> { f | skipUnsupported = v }))
    in
    div [ A.class "settings-pane" ]
        (case form.format of
            StaticSvg ->
                common ++ [ frameField ] ++ metadata

            AnimatedSvg ->
                common ++ metadata ++ [ skip ]

            SvgCss ->
                common ++ metadata ++ [ skip, UI.checkbox "Pause animation under prefers-reduced-motion" form.reducedMotionPause (\v -> change (\f -> { f | reducedMotionPause = v })) ]

            HtmlPlayer ->
                common ++ metadata ++ [ skip, span [ A.class "hint" ] [ text "Bundle: index.html, framewise-player.js, animation.json, scene.svg and README.txt in a ZIP." ] ]

            PngStill ->
                common ++ [ frameField, scaleField ]

            PngSequence ->
                common
                    ++ [ textInput "export-start" "First frame" form.rangeStart (\v -> change (\f -> { f | rangeStart = v }))
                       , textInput "export-end" "Last frame" form.rangeEnd (\v -> change (\f -> { f | rangeEnd = v }))
                       , textInput "export-origin" "File index origin" form.indexOrigin (\v -> change (\f -> { f | indexOrigin = v }))
                       , scaleField
                       , span [ A.class "hint" ] [ text "Files are named <scene>_000000.png with a manifest.json recording fps and size." ]
                       ]

            _ ->
                [ span [ A.class "hint" ] [ text "This format is not available in this build; use a PNG sequence and an external encoder." ] ]
        )
        |> (\html ->
                let
                    _ =
                        model
                in
                html
           )


jobsPane : Model -> Html Msg
jobsPane model =
    if List.isEmpty model.exportJobs then
        span [ A.class "hint" ] [ text "No exports yet." ]

    else
        div [ A.class "job-list" ]
            (List.map
                (\job ->
                    div [ A.class ("job job-" ++ job.status) ]
                        [ span [ A.class "job-label" ] [ text job.label ]
                        , span [ A.class "job-status" ]
                            [ text
                                (job.status
                                    ++ (case job.progress of
                                            Just ( done, total ) ->
                                                " " ++ String.fromInt done ++ "/" ++ String.fromInt total

                                            Nothing ->
                                                ""
                                       )
                                )
                            ]
                        , span [ A.class "job-meta" ] [ text (Maybe.withDefault "" job.fileName ++ " " ++ Maybe.withDefault "" job.message) ]
                        , span [ A.class "job-rev" ] [ text ("rev " ++ String.fromInt job.revision) ]
                        , if job.status == "rendering" || job.status == "queued" || job.status == "encoding" then
                            button [ A.class "btn small", E.onClick (CancelExportJob job.id) ] [ text "Cancel" ]

                          else if job.status == "failed" then
                            button [ A.class "btn small", E.onClick (RetryExportJob job.id) ] [ text "Retry" ]

                          else
                            text ""
                        ]
                )
                model.exportJobs
            )
