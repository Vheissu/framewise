module Editor.TimelineView exposing (view)

{-| Bottom timeline: transport, frame readout, track rows with keyframe
diamonds, ruler with the work area strip, and playhead. Rows are limited to
animated nodes plus the current selection so the panel stays legible.
-}

import App.Edit as Edit
import App.Fields as Fields
import App.Model as Model exposing (Model)
import App.Msg exposing (Msg(..))
import App.Timeline as Timeline
import Dict
import Domain.Color
import Domain.Document exposing (Document)
import Domain.Easing exposing (Easing(..))
import Domain.Evaluate as Evaluate
import Domain.Fps as Fps
import Domain.Keyframe as Keyframe
import Domain.LayerTime as LayerTime
import Domain.Property as Property exposing (PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Editor.CanvasView exposing (pointerDecoder)
import Html exposing (Html, button, div, span, text)
import Html.Attributes as A
import Html.Events as E
import Html.Keyed
import Html.Lazy
import Json.Decode as D
import Render.Scene as Render
import Render.SvgDoc as SvgDoc
import UI.Fields as UI
import UI.Icons as Icons
import UI.Label as Label


view : Model -> Html Msg
view model =
    case Model.activeScene model of
        Nothing ->
            text ""

        Just scene ->
            let
                e =
                    model.editor
            in
            div
                [ A.class "timeline"
                , A.classList [ ( "focused", e.focus == Model.TimelineFocus ) ]
                , A.style "height" (String.fromFloat e.timelineHeight ++ "px")
                , E.on "pointerdown" (D.map TimelinePointerDown pointerDecoder)
                ]
                [ div [ A.class "splitter splitter-h", E.on "pointerdown" (D.map (SplitterDown "timeline") (D.field "clientY" D.float)), A.attribute "role" "separator", A.attribute "aria-orientation" "horizontal" ] []
                , transport model scene
                , div [ A.class "timeline-body" ]
                    [ trackList model scene
                    , Html.node "fw-rect-host"
                        [ A.class "timeline-tracks"
                        , E.on "fwrect" (D.map TimelineRect rectDecoder)
                        , E.custom "wheel"
                            (D.map (\( dx, ctrl ) -> { message = iif ctrl (TimelineZoom (iif (dx > 0) 0.9 1.1)) (TimelineScroll dx), stopPropagation = True, preventDefault = True })
                                (D.map2 Tuple.pair
                                    (D.oneOf
                                        [ D.field "deltaX" D.float
                                            |> D.andThen
                                                (\x ->
                                                    if x /= 0 then
                                                        D.succeed x

                                                    else
                                                        D.field "deltaY" D.float
                                                )
                                        , D.field "deltaY" D.float
                                        ]
                                    )
                                    (D.field "ctrlKey" D.bool)
                                )
                            )
                        ]
                        (trackArea model scene)
                    ]
                ]


iif : Bool -> a -> a -> a
iif c a b =
    if c then
        a

    else
        b


rectDecoder : D.Decoder { left : Float, top : Float, width : Float, height : Float }
rectDecoder =
    D.at [ "detail" ]
        (D.map4 (\l t w h -> { left = l, top = t, width = w, height = h })
            (D.field "left" D.float)
            (D.field "top" D.float)
            (D.field "width" D.float)
            (D.field "height" D.float)
        )



-- TRANSPORT


transport : Model -> Scene -> Html Msg
transport model scene =
    let
        e =
            model.editor

        pb =
            e.playback

        frame =
            Edit.currentFrame model

        loopIcon =
            case scene.playbackMode of
                Scene.PlayOnce ->
                    "once"

                Scene.Repeat ->
                    "loop"

                Scene.PingPong ->
                    "pingpong"

        nextLoop =
            case scene.playbackMode of
                Scene.PlayOnce ->
                    Scene.Repeat

                Scene.Repeat ->
                    Scene.PingPong

                Scene.PingPong ->
                    Scene.PlayOnce
    in
    div [ A.class "transport", A.attribute "role" "toolbar", A.attribute "aria-label" "Playback" ]
        [ div [ A.class "time-display", A.style "width" (String.fromFloat (Timeline.trackListWidth - 8) ++ "px") ]
            [ span [ A.class "timecode", A.title "Timecode" ] [ text (Fps.toTimecode scene.fps (round frame)) ]
            , div [ A.class "time-sub" ]
                [ UI.numberField model { id = "frame", label = "Frame", value = Just frame, step = 1, unit = "", animated = Nothing }
                , span [ A.class "fps-badge", A.title "Frame rate and duration" ] [ text (Fps.toLabel scene.fps ++ " fps · " ++ String.fromInt scene.durationFrames ++ " f · " ++ Fields.displayValue (Fps.framesToSeconds scene.fps (toFloat scene.durationFrames)) ++ " s") ]
                ]
            ]
        , div [ A.class "transport-group" ]
            [ UI.iconButton { icon = "skip-start", label = "Jump to start (Home)", active = False, onClick = SetPlayhead 0, disabled = False }
            , UI.iconButton { icon = "key-prev", label = "Previous keyframe (,)", active = False, onClick = JumpToKey -1, disabled = False }
            , UI.iconButton { icon = "step-back", label = "Previous frame (←)", active = False, onClick = StepFrame -1, disabled = False }
            , button
                [ A.class "icon-button play-button"
                , A.classList [ ( "active", pb.playing ) ]
                , A.title (iif pb.playing "Pause (Space)" "Play (Space)")
                , A.attribute "aria-label" (iif pb.playing "Pause" "Play")
                , E.onClick TogglePlay
                ]
                [ Icons.icon (iif pb.playing "pause" "play") ]
            , UI.iconButton { icon = "stop", label = "Stop and return to start", active = False, onClick = StopPlayback, disabled = False }
            , UI.iconButton { icon = "step-forward", label = "Next frame (→)", active = False, onClick = StepFrame 1, disabled = False }
            , UI.iconButton { icon = "key-next", label = "Next keyframe (.)", active = False, onClick = JumpToKey 1, disabled = False }
            , UI.iconButton { icon = "skip-end", label = "Jump to end (End)", active = False, onClick = SetPlayhead (toFloat scene.durationFrames), disabled = False }
            ]
        , div [ A.class "transport-group" ]
            [ UI.iconButton { icon = loopIcon, label = "Loop mode: " ++ Scene.playbackModeToCode scene.playbackMode ++ " (click to change)", active = scene.playbackMode /= Scene.PlayOnce, onClick = SetLoopMode nextLoop, disabled = False }
            , UI.iconButton { icon = "reverse", label = "Reverse playback", active = pb.reverse, onClick = ToggleReverse, disabled = False }
            , UI.select "Playback speed" (String.fromFloat pb.speed) [ ( "0.25", "0.25×" ), ( "0.5", "0.5×" ), ( "1", "1×" ), ( "1.5", "1.5×" ), ( "2", "2×" ) ] (\s -> SetSpeed (String.toFloat s |> Maybe.withDefault 1))
            , UI.iconButton { icon = "key", label = "Auto-keyframe: " ++ iif e.autoKey "on" "off", active = e.autoKey, onClick = ToggleAutoKey, disabled = False }
            , UI.iconButton { icon = "onion", label = "Onion skin", active = e.onionSkin, onClick = ToggleOnionSkin, disabled = False }
            , UI.iconButton { icon = "magnet", label = "Snap keys to frames", active = model.preferences.timelineSnap, onClick = PreferenceChanged (\p -> { p | timelineSnap = not p.timelineSnap }), disabled = False }
            , UI.iconButton { icon = "film", label = "Frame thumbnails", active = e.showFilmstrip, onClick = ToggleFilmstrip, disabled = False }
            , UI.iconButton { icon = "layers", label = "Show all properties for selected layers", active = e.showAllProperties, onClick = ToggleAllProperties, disabled = False }
            ]
        , div [ A.class "transport-group transport-right" ]
            [ UI.iconButton { icon = "minus", label = "Zoom timeline out", active = False, onClick = TimelineZoom 0.8, disabled = False }
            , UI.iconButton { icon = "plus", label = "Zoom timeline in", active = False, onClick = TimelineZoom 1.25, disabled = False }
            , UI.iconButton { icon = "fit", label = "Fit timeline", active = False, onClick = fitMsg model scene, disabled = False }
            , UI.iconButton { icon = "fullscreen", label = "Preview (Ctrl/Cmd+Enter)", active = False, onClick = OpenPreview, disabled = False }
            ]
        ]


fitMsg : Model -> Scene -> Msg
fitMsg model scene =
    let
        width =
            max 100 model.editor.timelineRect.width

        current =
            (Model.activeView model).timelinePixelsPerFrame

        target =
            (width - 2 * Timeline.timeOrigin - 8) / toFloat (max 1 scene.durationFrames)
    in
    TimelineZoom (target / current)



-- ROWS


trackList : Model -> Scene -> Html Msg
trackList model scene =
    let
        allRows =
            Timeline.rows model scene

        frame =
            Edit.currentFrame model

        sel =
            (Model.activeView model).selection
    in
    div [ A.class "track-list", A.style "width" (String.fromFloat Timeline.trackListWidth ++ "px") ]
        [ div [ A.class "track-list-header", A.style "height" (px (Timeline.lanesTop model)) ] [ span [] [ text "Layer" ], span [] [ text "Value" ] ]
        , if List.isEmpty allRows then
            div [ A.class "empty small" ] [ text "Select a layer and press K, or click a diamond in the inspector, to start animating." ]

          else
            div [ A.class "track-rows", A.attribute "role" "tree" ]
                (List.map
                    (\row ->
                        case row.property of
                            Nothing ->
                                div
                                    [ A.class "track-row node-row"
                                    , A.classList [ ( "selected", List.member row.node.id sel ) ]
                                    , A.style "height" (String.fromFloat Timeline.rowHeight ++ "px")
                                    , A.attribute "role" "treeitem"
                                    , E.onClick (SelectNodes [ row.node.id ] False)
                                    ]
                                    [ span [ A.class "layer-label", Label.style row.node.id ] []
                                    , span [ A.class "track-node-name" ] [ text row.node.name ]
                                    , button [ A.class "icon-button tiny", A.title "Remove all animation", A.attribute "aria-label" ("Remove animation from " ++ row.node.name), UI.stopPropagation "click" (RemoveAllAnimation row.node.id) ] [ Icons.icon "trash" ]
                                    ]

                            Just property ->
                                let
                                    value =
                                        Evaluate.evaluateNodeProperty scene frame row.node property

                                    hasKey =
                                        row.track |> Maybe.andThen (Keyframe.keyAt (round frame)) |> (/=) Nothing

                                    enabled =
                                        row.track |> Maybe.map .enabled |> Maybe.withDefault True
                                in
                                div
                                    [ A.class "track-row property-row"
                                    , A.classList [ ( "muted", not enabled ) ]
                                    , A.style "height" (String.fromFloat Timeline.rowHeight ++ "px")
                                    , A.attribute "role" "treeitem"
                                    , E.custom "contextmenu"
                                        (D.map2 (\x y -> { message = OpenContextMenu x y (Model.TrackContext (row.track |> Maybe.map .id |> Maybe.withDefault "")), stopPropagation = True, preventDefault = True })
                                            (D.field "clientX" D.float)
                                            (D.field "clientY" D.float)
                                        )
                                    ]
                                    [ button
                                        [ A.class "diamond"
                                        , A.classList [ ( "animated", row.track /= Nothing ), ( "at-playhead", hasKey ) ]
                                        , A.title (iif hasKey "Remove key at playhead" "Add key at playhead")
                                        , A.attribute "aria-label" (Property.pathLabel property ++ ": " ++ iif hasKey "remove key" "add key")
                                        , E.onClick (ToggleKeyAt row.node.id property)
                                        ]
                                        [ Icons.icon (iif hasKey "diamond-filled" "diamond") ]
                                    , span [ A.class "track-property-name" ] [ text (Property.pathLabel property) ]
                                    , span [ A.class "track-value" ] [ text (valueText value) ]
                                    , case row.track of
                                        Just t ->
                                            button [ A.class "track-toggle", A.title (iif t.enabled "Mute track" "Enable track"), A.attribute "aria-label" (iif t.enabled "Mute" "Enable"), A.attribute "aria-pressed" (iif t.enabled "false" "true"), E.onClick (SetTrackEnabled t.id (not t.enabled)) ] [ Icons.icon (iif t.enabled "eye" "eye-off") ]

                                        Nothing ->
                                            text ""
                                    ]
                    )
                    allRows
                )
        ]


valueText : Maybe PropertyValue -> String
valueText v =
    case v of
        Just (Scalar s) ->
            Fields.displayValue s

        Just (Angle a) ->
            Fields.displayValue a ++ "°"

        Just (PointValue p) ->
            Fields.displayValue p.x ++ ", " ++ Fields.displayValue p.y

        Just (SizeValue p) ->
            Fields.displayValue p.x ++ " × " ++ Fields.displayValue p.y

        Just (ColorValue c) ->
            Domain.Color.toHex c

        Just (BoolValue b) ->
            iif b "visible" "hidden"

        Just (StringValue s) ->
            String.left 16 s

        Just (PathValue _) ->
            "path"

        Just (NumberList l) ->
            String.fromInt (List.length l) ++ " values"

        Nothing ->
            ""



-- TRACK AREA


trackArea : Model -> Scene -> List (Html Msg)
trackArea model scene =
    let
        view_ =
            Model.activeView model

        ppf =
            view_.timelinePixelsPerFrame

        scroll =
            view_.timelineScroll

        frameX f =
            f * ppf - scroll + Timeline.timeOrigin

        duration =
            scene.durationFrames

        allRows =
            Timeline.rows model scene

        frame =
            Edit.currentFrame model

        rulerStep =
            [ 1, 2, 5, 10, 15, 30, 60, 120, 300, 600 ] |> List.filter (\st -> toFloat st * ppf >= 48) |> List.head |> Maybe.withDefault 600

        ticks =
            List.range 0 (duration // rulerStep) |> List.map ((*) rulerStep)

        -- unlabelled ticks between the numbered ones, at least 6px apart
        minorStep =
            [ 1, 2, 5, 10, 30, 60, 150 ]
                |> List.filter (\st -> st < rulerStep && modBy st rulerStep == 0 && toFloat st * ppf >= 6)
                |> List.head

        minorTicks =
            case minorStep of
                Just st ->
                    List.range 0 (duration // st)
                        |> List.map ((*) st)
                        |> List.filter (\t -> modBy rulerStep t /= 0)

                Nothing ->
                    []

        ( ws, we ) =
            Timeline.playbackRange scene

        rangeStrip =
            div
                [ A.class "range-strip"
                , A.style "height" (px Timeline.rangeStripHeight)
                , A.title "Work range: drag to set, drag the ends to trim, drag the middle to move, double-click to clear (B and N set the ends at the playhead)"
                , E.custom "pointerdown" (D.map (\ev -> { message = TimelineRangeDown ev, stopPropagation = True, preventDefault = False }) pointerDecoder)
                , E.custom "dblclick" (D.succeed { message = iif (scene.workRange == Nothing) NoOp (SetWorkRange Nothing), stopPropagation = True, preventDefault = False })
                ]
                (case scene.workRange of
                    Just _ ->
                        [ div [ A.class "range-bar", A.style "left" (px (frameX (toFloat ws))), A.style "width" (px (toFloat (we - ws) * ppf)) ]
                            [ div [ A.class "range-handle range-handle-start" ] []
                            , div [ A.class "range-handle range-handle-end" ] []
                            ]
                        ]

                    Nothing ->
                        []
                )

        -- dim the time outside the work range so the chosen part stands out
        rangeShades =
            case scene.workRange of
                Just _ ->
                    [ div [ A.class "range-shade", A.style "top" (px Timeline.rangeStripHeight), A.style "left" "0", A.style "width" (px (max 0 (frameX (toFloat ws)))) ] []
                    , div [ A.class "range-shade", A.style "top" (px Timeline.rangeStripHeight), A.style "left" (px (frameX (toFloat we))), A.style "right" "0" ] []
                    ]

                Nothing ->
                    []

        marquee =
            case model.editor.gesture of
                Model.MarqueeKeys g ->
                    let
                        left =
                            frameX (min g.startFrame g.currentFrame)

                        right =
                            frameX (max g.startFrame g.currentFrame)
                    in
                    [ div
                        [ A.class "key-marquee"
                        , A.style "left" (px left)
                        , A.style "width" (px (right - left))
                        , A.style "top" (px (min g.startY g.currentY))
                        , A.style "height" (px (abs (g.currentY - g.startY)))
                        ]
                        []
                    ]

                _ ->
                    []

        scrubbing =
            model.editor.gesture == Model.ScrubPlayhead

        barPress nodeId edge =
            E.custom "pointerdown" (D.map (\ev -> { message = LayerBarDown nodeId edge ev, stopPropagation = True, preventDefault = False }) pointerDecoder)

        layerBar nodeId =
            let
                span =
                    LayerTime.spanOf scene nodeId
            in
            div
                [ A.class "layer-bar"
                , Label.style nodeId
                , A.style "left" (px (frameX (toFloat span.inFrame)))
                , A.style "width" (px (toFloat (span.outFrame - span.inFrame) * ppf))
                , A.title ("In " ++ String.fromInt span.inFrame ++ " · Out " ++ String.fromInt span.outFrame ++ ". Drag to move the layer and its keys, drag an end to trim, Shift snaps.")
                , barPress nodeId Model.BarBody
                ]
                [ div [ A.class "bar-trim bar-trim-in", barPress nodeId Model.BarIn ] []
                , div [ A.class "bar-trim bar-trim-out", barPress nodeId Model.BarOut ] []
                ]

        keysOf row =
            case ( row.track, row.property ) of
                ( Just track, Just _ ) ->
                    List.map
                        (\k ->
                            let
                                ref =
                                    { trackId = track.id, keyId = k.id }

                                selected =
                                    List.member ref model.editor.selectedKeys

                                easingClass =
                                    case k.easing of
                                        Hold ->
                                            "hold"

                                        Linear ->
                                            "linear"

                                        Spring _ ->
                                            "spring"

                                        _ ->
                                            "eased"
                            in
                            button
                                [ A.class ("key " ++ easingClass)
                                , A.classList [ ( "selected", selected ), ( "out-of-range", k.frame > duration ) ]
                                , A.style "left" (px (frameX (toFloat k.frame)))
                                , A.title (Property.pathLabel track.target.property ++ " @ " ++ String.fromInt k.frame ++ " · " ++ Domain.Easing.label k.easing)
                                , A.attribute "aria-label" ("Keyframe at frame " ++ String.fromInt k.frame)
                                , E.custom "pointerdown" (D.map (\ev -> { message = KeyPointerDown ref ev, stopPropagation = True, preventDefault = False }) pointerDecoder)
                                , E.custom "contextmenu" (D.succeed { message = NoOp, stopPropagation = True, preventDefault = True })
                                , E.custom "click" (D.succeed { message = NoOp, stopPropagation = True, preventDefault = False })
                                ]
                                []
                        )
                        track.keyframes

                _ ->
                    []

        segmentBars row =
            case row.track of
                Just track ->
                    List.map2
                        (\a b ->
                            div [ A.class "key-segment", A.style "left" (px (frameX (toFloat a.frame))), A.style "width" (px (toFloat (b.frame - a.frame) * ppf)) ] []
                        )
                        track.keyframes
                        (List.drop 1 track.keyframes)

                Nothing ->
                    []
    in
    [ div
        [ A.class "ruler-row"
        , A.style "height" (px Timeline.rulerHeight)
        , E.custom "pointerdown" (D.map (\ev -> { message = TimelineRulerDown ev, stopPropagation = True, preventDefault = False }) pointerDecoder)
        ]
        (rangeStrip
            :: List.map (\t -> span [ A.class "tick-minor", A.style "left" (px (frameX (toFloat t))) ] []) minorTicks
            ++ List.map
                (\t ->
                    span [ A.class "tick", A.style "left" (px (frameX (toFloat t))) ] [ text (String.fromInt t) ]
                )
                ticks
            ++ [ div [ A.class "end-marker", A.style "top" (px Timeline.rangeStripHeight), A.style "left" (px (frameX (toFloat duration))) ] [] ]
        )
    , if model.editor.showFilmstrip then
        filmstrip model scene

      else
        text ""
    , div
        [ A.class "track-area-rows"
        , E.custom "pointerdown" (D.map (\ev -> { message = TimelineLanesDown ev, stopPropagation = True, preventDefault = False }) pointerDecoder)
        ]
        (List.map
            (\row ->
                div
                    [ A.class "track-lane"
                    , A.classList [ ( "node-lane", row.property == Nothing ), ( "selected", row.property == Nothing && List.member row.node.id view_.selection ) ]
                    , A.style "height" (px Timeline.rowHeight)
                    ]
                    (div [ A.class "lane-end", A.style "left" (px (frameX (toFloat duration))) ] []
                        :: (if row.property == Nothing then
                                [ layerBar row.node.id ]

                            else
                                []
                           )
                        ++ segmentBars row
                        ++ keysOf row
                    )
            )
            allRows
        )
    ]
        ++ rangeShades
        ++ marquee
        ++ [ div
                [ A.class "playhead-grip"
                , A.style "top" (px (Timeline.lanesTop model))
                , A.style "left" (px (frameX frame))
                , A.title "Drag to scrub (Shift snaps to keys)"
                , E.custom "pointerdown" (D.map (\ev -> { message = TimelineRulerDown ev, stopPropagation = True, preventDefault = False }) pointerDecoder)
                ]
                []
           , div
                [ A.class "playhead"
                , A.classList [ ( "dragging", scrubbing ) ]
                , A.style "top" (px Timeline.rangeStripHeight)
                , A.style "left" (px (frameX frame))
                ]
                [ div [ A.class "playhead-head" ] []
                , if scrubbing then
                    span [ A.class "playhead-label" ] [ text (Fields.displayValue frame) ]

                  else
                    text ""
                ]
           ]



-- FILMSTRIP


{-| A row of rendered frames under the ruler. Zooming in spreads the frames
out until every frame has its own thumbnail. Thumbnails only redraw when the
document changes, not when the playhead moves, and hold still during a drag
until it is released.
-}
filmstrip : Model -> Scene -> Html Msg
filmstrip model scene =
    case Model.activeDoc model of
        Just open ->
            let
                view_ =
                    Model.activeView model

                doc =
                    Maybe.withDefault open.document model.editor.gestureOrigin

                docScene =
                    Dict.get scene.id doc.scenes |> Maybe.withDefault scene
            in
            Html.Lazy.lazy6 filmstripFrames open.assetUrls doc docScene view_.timelinePixelsPerFrame view_.timelineScroll model.editor.timelineRect.width

        Nothing ->
            text ""


filmstripFrames : Dict.Dict String String -> Document -> Scene -> Float -> Float -> Float -> Html Msg
filmstripFrames assetUrls doc scene ppf scroll width =
    let
        thumbHeight =
            Timeline.filmstripHeight - 8

        thumbWidth =
            clamp 16 160 (thumbHeight * scene.width / max 1 scene.height)

        -- frames per thumbnail, on round numbers so thumbnails stay put while scrolling
        step =
            [ 1, 2, 5, 10, 15, 30, 60, 120, 300, 600 ]
                |> List.filter (\st -> toFloat st * ppf >= thumbWidth + 2)
                |> List.head
                |> Maybe.withDefault 600

        slot =
            toFloat step * ppf

        first =
            max 0 (floor ((scroll - Timeline.timeOrigin) / slot))

        last =
            ceiling ((scroll + width) / slot)

        frames =
            List.range first last
                |> List.map ((*) step)
                |> List.filter (\f -> f <= scene.durationFrames)
    in
    Html.Keyed.node "div"
        [ A.class "filmstrip"
        , A.style "height" (px Timeline.filmstripHeight)
        , A.title "Drag to scrub"
        , E.custom "pointerdown" (D.map (\ev -> { message = TimelineRulerDown ev, stopPropagation = True, preventDefault = False }) pointerDecoder)
        ]
        (List.map
            (\f ->
                ( String.fromInt f
                , div
                    [ A.class "film-frame"
                    , A.attribute "data-frame" (String.fromInt f)
                    , A.style "left" (px (toFloat f * ppf - scroll + Timeline.timeOrigin))
                    , A.style "width" (px thumbWidth)
                    , A.style "height" (px thumbHeight)
                    ]
                    [ Html.Lazy.lazy4 thumbnail assetUrls doc scene f ]
                )
            )
            frames
        )


thumbnail : Dict.Dict String String -> Document -> Scene -> Int -> Html Msg
thumbnail assetUrls doc scene frame =
    case Evaluate.evaluateScene doc scene.id (toFloat frame) of
        Just resolved ->
            SvgDoc.toHtml
                (Render.renderScene
                    { idPrefix = "film-" ++ String.fromInt frame
                    , assetUrls = assetUrls
                    , includeBackground = True
                    , includeIds = False
                    , title = Nothing
                    , description = Nothing
                    , standalone = False
                    }
                    resolved
                )

        Nothing ->
            text ""


px : Float -> String
px v =
    String.fromFloat (toFloat (round (v * 10)) / 10) ++ "px"
