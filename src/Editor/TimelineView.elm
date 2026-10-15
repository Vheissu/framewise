module Editor.TimelineView exposing (view)

{-| Bottom timeline: transport, frame readout, track rows with keyframe
diamonds, ruler and playhead. Rows are limited to animated nodes plus the
current selection so the panel stays legible.
-}

import App.Edit as Edit
import App.Fields as Fields
import App.Model as Model exposing (Model)
import App.Msg exposing (Msg(..))
import App.Timeline as Timeline
import Dict
import Domain.Color
import Domain.Easing exposing (Easing(..))
import Domain.Evaluate as Evaluate
import Domain.Fps as Fps
import Domain.Keyframe as Keyframe exposing (Track)
import Domain.Node as Node exposing (Node)
import Domain.Property as Property exposing (PropertyPath, PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Editor.CanvasView exposing (pointerDecoder)
import Html exposing (Html, button, div, span, text)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import Set
import UI.Fields as UI
import UI.Icons as Icons


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
        [ div [ A.class "transport-group" ]
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
            [ UI.numberField model { id = "frame", label = "Frame", value = Just frame, step = 1, unit = "", animated = Nothing }
            , span [ A.class "timecode", A.title "Timecode" ] [ text (Fps.toTimecode scene.fps (round frame)) ]
            , span [ A.class "fps-badge", A.title "Frame rate" ] [ text (Fps.toLabel scene.fps ++ " fps") ]
            , span [ A.class "duration-badge", A.title "Duration" ] [ text (String.fromInt scene.durationFrames ++ " f · " ++ Fields.displayValue (Fps.framesToSeconds scene.fps (toFloat scene.durationFrames)) ++ " s") ]
            ]
        , div [ A.class "transport-group" ]
            [ UI.iconButton { icon = loopIcon, label = "Loop mode: " ++ Scene.playbackModeToCode scene.playbackMode ++ " (click to change)", active = scene.playbackMode /= Scene.PlayOnce, onClick = SetLoopMode nextLoop, disabled = False }
            , UI.iconButton { icon = "reverse", label = "Reverse playback", active = pb.reverse, onClick = ToggleReverse, disabled = False }
            , UI.select "Playback speed" (String.fromFloat pb.speed) [ ( "0.25", "0.25×" ), ( "0.5", "0.5×" ), ( "1", "1×" ), ( "1.5", "1.5×" ), ( "2", "2×" ) ] (\s -> SetSpeed (String.toFloat s |> Maybe.withDefault 1))
            , UI.iconButton { icon = "key", label = "Auto-keyframe: " ++ iif e.autoKey "on" "off", active = e.autoKey, onClick = ToggleAutoKey, disabled = False }
            , UI.iconButton { icon = "onion", label = "Onion skin", active = e.onionSkin, onClick = ToggleOnionSkin, disabled = False }
            , UI.iconButton { icon = "magnet", label = "Snap keys to frames", active = model.preferences.timelineSnap, onClick = PreferenceChanged (\p -> { p | timelineSnap = not p.timelineSnap }), disabled = False }
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
            (width - 24) / toFloat (max 1 scene.durationFrames)
    in
    TimelineZoom (target / current)



-- ROWS


type alias Row =
    { node : Node
    , property : Maybe PropertyPath
    , track : Maybe Track
    , depth : Int
    }


rows : Model -> Scene -> List Row
rows model scene =
    let
        e =
            model.editor

        view_ =
            Model.activeView model

        sel =
            view_.selection

        animatedIds =
            Dict.values scene.tracks |> List.map (.target >> .nodeId) |> Set.fromList

        candidates =
            Scene.flattenOrder scene
                |> List.filter (\id -> Set.member id animatedIds || List.member id sel)
                |> List.filterMap (\id -> Dict.get id scene.nodes)

        nodeRows node =
            let
                tracks =
                    Scene.tracksFor node.id scene

                selected =
                    List.member node.id sel

                props =
                    if e.showAllProperties && selected then
                        Node.animatableProperties node

                    else
                        tracks |> List.map (.target >> .property)

                expanded =
                    Set.member ("tl:" ++ node.id) view_.expanded || selected || True
            in
            Row node Nothing Nothing 0
                :: (if expanded then
                        List.map (\p -> Row node (Just p) (tracks |> List.filter (\t -> t.target.property == p) |> List.head) 1) (dedupe props)

                    else
                        []
                   )
    in
    List.concatMap nodeRows candidates


dedupe : List a -> List a
dedupe =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []


rowHeight : Float
rowHeight =
    26


trackList : Model -> Scene -> Html Msg
trackList model scene =
    let
        allRows =
            rows model scene

        frame =
            Edit.currentFrame model

        sel =
            (Model.activeView model).selection
    in
    div [ A.class "track-list", A.style "width" (String.fromFloat Timeline.trackListWidth ++ "px") ]
        [ div [ A.class "track-list-header" ] [ text "Layers & properties" ]
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
                                    , A.style "height" (String.fromFloat rowHeight ++ "px")
                                    , A.attribute "role" "treeitem"
                                    , E.onClick (SelectNodes [ row.node.id ] False)
                                    ]
                                    [ span [ A.class "track-node-name" ] [ text row.node.name ]
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
                                    , A.style "height" (String.fromFloat rowHeight ++ "px")
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
            f * ppf - scroll

        duration =
            scene.durationFrames

        allRows =
            rows model scene

        frame =
            Edit.currentFrame model

        rulerStep =
            [ 1, 2, 5, 10, 15, 30, 60, 120, 300, 600 ] |> List.filter (\s -> toFloat s * ppf >= 48) |> List.head |> Maybe.withDefault 600

        ticks =
            List.range 0 (duration // rulerStep) |> List.map ((*) rulerStep)

        ( ws, we ) =
            Timeline.playbackRange scene

        workRange =
            case scene.workRange of
                Just _ ->
                    [ div [ A.class "work-range", A.style "left" (px (frameX (toFloat ws))), A.style "width" (px (toFloat (we - ws) * ppf)) ] [] ]

                Nothing ->
                    []

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
                                , E.custom "pointerdown" (D.map (\ev -> { message = KeyPointerDown ref ev, stopPropagation = True, preventDefault = True }) pointerDecoder)
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
        , E.custom "pointerdown" (D.map (\ev -> { message = TimelineRulerDown ev, stopPropagation = True, preventDefault = True }) pointerDecoder)
        ]
        (workRange
            ++ List.map
                (\t ->
                    span [ A.class "tick", A.style "left" (px (frameX (toFloat t))) ] [ text (String.fromInt t) ]
                )
                ticks
            ++ [ div [ A.class "end-marker", A.style "left" (px (frameX (toFloat duration))) ] [] ]
        )
    , div [ A.class "track-area-rows" ]
        (List.map
            (\row ->
                div
                    [ A.class "track-lane"
                    , A.classList [ ( "node-lane", row.property == Nothing ) ]
                    , A.style "height" (px rowHeight)
                    ]
                    (div [ A.class "lane-end", A.style "left" (px (frameX (toFloat duration))) ] []
                        :: segmentBars row
                        ++ keysOf row
                    )
            )
            allRows
        )
    , div [ A.class "playhead", A.style "left" (px (frameX frame)) ] [ div [ A.class "playhead-head" ] [] ]
    ]


px : Float -> String
px v =
    String.fromFloat (toFloat (round (v * 10)) / 10) ++ "px"
