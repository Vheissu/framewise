module App.Timeline exposing
    ( addKeyAtPlayhead
    , applyStagger
    , autoScroll
    , barDown
    , copyKeys
    , distributeKeys
    , edgeOverflow
    , filmstripHeight
    , frameAtX
    , isTimelineGesture
    , keyPointerDown
    , lanesDown
    , lanesTop
    , pasteKeys
    , playbackRange
    , pointerMove
    , pointerUp
    , rangeDown
    , rangeStripHeight
    , removeSelectedKeys
    , reverseKeys
    , rowHeight
    , rows
    , rulerDown
    , rulerHeight
    , scaleKeys
    , setKeyEasing
    , setPlayhead
    , setRangeEdgeAtPlayhead
    , shiftKeys
    , tick
    , timeOrigin
    , toggleKeyAt
    , togglePlay
    , trackListWidth
    )

{-| Timeline editing and playback. The playback clock derives the current
frame from an absolute origin on every animation frame, so it never drifts.
-}

import App.Edit as Edit exposing (Update, pure)
import App.Model as Model exposing (Gesture(..), KeyRef, Model)
import App.Msg exposing (Msg(..), PointerEvent)
import Dict
import DocumentIO.Decode as Decode
import DocumentIO.Encode as Encode
import Domain.Document as Document
import Domain.Easing as Easing exposing (Easing)
import Domain.Evaluate as Evaluate
import Domain.Fps as Fps
import Domain.Keyframe as Keyframe exposing (Track)
import Domain.LayerTime as LayerTime
import Domain.Loop as Loop
import Domain.Node as Node exposing (Node)
import Domain.Property as Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Json.Decode as D
import Json.Encode as E
import Set
import Shared.Ids exposing (NodeId)
import Time


trackListWidth : Float
trackListWidth =
    260


{-| Pixels between the left edge of the track area and frame 0, so keys on
the first frame are not cut in half by the panel edge.
-}
timeOrigin : Float
timeOrigin =
    10


frameAtX : Model -> Float -> Float
frameAtX model clientX =
    let
        view =
            Model.activeView model

        rect =
            model.editor.timelineRect
    in
    (clientX - rect.left - timeOrigin + view.timelineScroll) / view.timelinePixelsPerFrame


setPlayhead : Float -> Model -> Model
setPlayhead frame model =
    case Model.activeScene model of
        Just scene ->
            let
                clamped =
                    clamp 0 (toFloat scene.durationFrames) frame
            in
            Edit.mapActiveView (\v -> { v | playhead = clamped }) model

        Nothing ->
            model



-- PLAYBACK


playbackRange : Scene -> ( Int, Int )
playbackRange scene =
    case scene.workRange of
        Just r ->
            ( clamp 0 scene.durationFrames (min r.start r.end), clamp 0 scene.durationFrames (max r.start r.end) )

        Nothing ->
            ( 0, scene.durationFrames )


togglePlay : Model -> Model
togglePlay model =
    let
        editor =
            model.editor

        pb =
            editor.playback
    in
    if pb.playing then
        { model | editor = { editor | playback = { pb | playing = False } } }

    else
        let
            frame =
                Edit.currentFrame model

            startFrame =
                case Model.activeScene model of
                    Just scene ->
                        let
                            ( s, e ) =
                                playbackRange scene
                        in
                        if scene.playbackMode == Scene.PlayOnce && ((not pb.reverse && frame >= toFloat e) || (pb.reverse && frame <= toFloat s)) then
                            if pb.reverse then
                                toFloat e

                            else
                                toFloat s

                        else
                            frame

                    Nothing ->
                        frame
        in
        { model | editor = { editor | playback = { pb | playing = True, startTime = -1, startFrame = startFrame } } }


tick : Time.Posix -> Model -> Model
tick now model =
    let
        editor =
            model.editor

        pb =
            editor.playback

        nowMs =
            toFloat (Time.posixToMillis now)
    in
    if not pb.playing then
        model

    else if pb.startTime < 0 then
        { model | editor = { editor | playback = { pb | startTime = nowMs } } }

    else
        case Model.activeScene model of
            Nothing ->
                model

            Just scene ->
                let
                    ( rs, re ) =
                        playbackRange scene

                    rangeLen =
                        max 1 (re - rs)

                    elapsedSeconds =
                        (nowMs - pb.startTime) / 1000

                    direction =
                        if pb.reverse then
                            -1

                        else
                            1

                    rawFrame =
                        pb.startFrame + direction * pb.speed * Fps.secondsToFrames scene.fps elapsedSeconds

                    mode =
                        Maybe.withDefault scene.playbackMode pb.loopOverride

                    -- map into the work range
                    relative =
                        rawFrame - toFloat rs

                    mapped =
                        toFloat rs + Loop.mapFrame mode rangeLen relative

                    finished =
                        mode == Scene.PlayOnce && ((direction > 0 && relative >= toFloat rangeLen) || (direction < 0 && relative <= 0))
                in
                if finished then
                    setPlayhead mapped { model | editor = { editor | playback = { pb | playing = False } } }

                else
                    setPlayhead mapped model



-- KEYFRAMES


{-| Click on a property diamond: add a key at the playhead using the evaluated
value (no visual jump), or remove the key that is already there.
-}
toggleKeyAt : NodeId -> PropertyPath -> Model -> Update
toggleKeyAt nodeId property model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                frame =
                    round (Edit.currentFrame model)
            in
            case Scene.trackFor nodeId property scene of
                Just track ->
                    case Keyframe.keyAt frame track of
                        Just k ->
                            let
                                removed =
                                    Keyframe.remove k.id track

                                update s =
                                    if List.isEmpty removed.keyframes then
                                        -- keep the base value equal to the last evaluated value
                                        let
                                            evaluated =
                                                Dict.get nodeId s.nodes
                                                    |> Maybe.andThen (\n -> Evaluate.evaluateNodeProperty s (toFloat frame) n property)
                                        in
                                        { s | tracks = Dict.remove track.id s.tracks }
                                            |> (case evaluated of
                                                    Just v ->
                                                        Scene.updateNode nodeId (Edit.applyBaseValue property v)

                                                    Nothing ->
                                                        identity
                                               )

                                    else
                                        Scene.upsertTrack removed s
                            in
                            Edit.commit "Remove keyframe" (Document.updateScene scene.id update) model

                        Nothing ->
                            insertEvaluatedKey nodeId property frame scene model

                Nothing ->
                    insertEvaluatedKey nodeId property frame scene model


insertEvaluatedKey : NodeId -> PropertyPath -> Int -> Scene -> Model -> Update
insertEvaluatedKey nodeId property frame scene model =
    case Dict.get nodeId scene.nodes of
        Nothing ->
            pure model

        Just node ->
            case Evaluate.evaluateNodeProperty scene (toFloat frame) node property of
                Nothing ->
                    pure model

                Just value ->
                    let
                        ( ids, m2 ) =
                            Edit.nextIds 3 model

                        id i =
                            List.drop i ids |> List.head |> Maybe.withDefault ("k" ++ String.fromInt i)

                        defaultEasing =
                            if Property.isDiscrete property then
                                Easing.Hold

                            else
                                Easing.Preset Easing.EaseInOut

                        update s =
                            case Scene.trackFor nodeId property s of
                                Just track ->
                                    Scene.upsertTrack (Keyframe.insert { id = id 0, frame = frame, value = value, easing = inheritEasing frame track defaultEasing } track) s

                                Nothing ->
                                    let
                                        base =
                                            Keyframe.newTrack (id 1) nodeId property

                                        withBaseline =
                                            if frame /= 0 then
                                                case Evaluate.evaluateNodeProperty s 0 node property of
                                                    Just v0 ->
                                                        Keyframe.insert { id = id 2, frame = 0, value = v0, easing = defaultEasing } base

                                                    Nothing ->
                                                        base

                                            else
                                                base
                                    in
                                    Scene.upsertTrack (Keyframe.insert { id = id 0, frame = frame, value = value, easing = defaultEasing } withBaseline) s
                    in
                    Edit.commit "Add keyframe" (Document.updateScene scene.id update) m2


inheritEasing : Int -> Track -> Easing -> Easing
inheritEasing frame track default =
    (Keyframe.segmentAt (toFloat frame) track).before |> Maybe.map .easing |> Maybe.withDefault default


{-| K: key every animated property of the selection at the playhead, or the
position when nothing is animated yet.
-}
addKeyAtPlayhead : Model -> Update
addKeyAtPlayhead model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                frame =
                    round (Edit.currentFrame model)

                step nodeId ( m, cmds ) =
                    let
                        animated =
                            Scene.tracksFor nodeId scene |> List.map (.target >> .property)

                        props =
                            if List.isEmpty animated then
                                [ Position ]

                            else
                                animated
                    in
                    List.foldl
                        (\prop ( mm, cc ) ->
                            case Model.activeScene mm of
                                Just sc ->
                                    let
                                        ( m2, c2 ) =
                                            insertEvaluatedKey nodeId prop frame sc mm
                                    in
                                    ( m2, c2 :: cc )

                                Nothing ->
                                    ( mm, cc )
                        )
                        ( m, cmds )
                        props

                ( final, allCmds ) =
                    List.foldl step ( model, [] ) (Edit.selection model)
            in
            ( final, Cmd.batch allCmds )


selectedKeyTriples : Model -> Scene -> List ( Track, Keyframe.Keyframe )
selectedKeyTriples model scene =
    model.editor.selectedKeys
        |> List.filterMap
            (\ref ->
                Dict.get ref.trackId scene.tracks
                    |> Maybe.andThen (\t -> List.filter (\k -> k.id == ref.keyId) t.keyframes |> List.head |> Maybe.map (\k -> ( t, k )))
            )


removeSelectedKeys : Model -> Update
removeSelectedKeys model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                update s =
                    List.foldl
                        (\ref acc ->
                            case Dict.get ref.trackId acc.tracks of
                                Just t ->
                                    let
                                        removed =
                                            Keyframe.remove ref.keyId t
                                    in
                                    if List.isEmpty removed.keyframes then
                                        { acc | tracks = Dict.remove t.id acc.tracks }

                                    else
                                        Scene.upsertTrack removed acc

                                Nothing ->
                                    acc
                        )
                        s
                        model.editor.selectedKeys

                editor =
                    model.editor
            in
            Edit.commit "Remove keyframes" (Document.updateScene scene.id update) { model | editor = { editor | selectedKeys = [] } }


setKeyEasing : Easing -> Model -> Update
setKeyEasing easing model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                update s =
                    List.foldl
                        (\ref acc ->
                            case Dict.get ref.trackId acc.tracks of
                                Just t ->
                                    Scene.upsertTrack (Keyframe.setEasing ref.keyId easing t) acc

                                Nothing ->
                                    acc
                        )
                        s
                        model.editor.selectedKeys
            in
            Edit.commit ("Easing: " ++ Easing.label easing) (Document.updateScene scene.id update) model


shiftKeys : Int -> Model -> Update
shiftKeys delta model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            Edit.commitCoalesced "shiftKeys" "Shift keyframes" (Document.updateScene scene.id (shiftScene model.editor.selectedKeys delta)) model


shiftScene : List KeyRef -> Int -> Scene -> Scene
shiftScene refs delta scene =
    let
        byTrack =
            List.foldl (\ref acc -> Dict.update ref.trackId (\m -> Just (ref.keyId :: Maybe.withDefault [] m)) acc) Dict.empty refs
    in
    Dict.foldl
        (\trackId keyIds acc ->
            case Dict.get trackId acc.tracks of
                Just t ->
                    Scene.upsertTrack (Keyframe.shift keyIds delta t) acc

                Nothing ->
                    acc
        )
        scene
        byTrack


scaleKeys : Float -> Model -> Update
scaleKeys factor model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                anchor =
                    selectedKeyTriples model scene |> List.map (Tuple.second >> .frame) |> List.minimum |> Maybe.withDefault 0

                byTrack =
                    List.foldl (\ref acc -> Dict.update ref.trackId (\m -> Just (ref.keyId :: Maybe.withDefault [] m)) acc) Dict.empty model.editor.selectedKeys

                update s =
                    Dict.foldl
                        (\trackId keyIds acc ->
                            case Dict.get trackId acc.tracks of
                                Just t ->
                                    Scene.upsertTrack (Keyframe.scale keyIds anchor factor t) acc

                                Nothing ->
                                    acc
                        )
                        s
                        byTrack
            in
            Edit.commit "Scale keyframes" (Document.updateScene scene.id update) model


distributeKeys : Model -> Update
distributeKeys model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                triples =
                    selectedKeyTriples model scene |> List.sortBy (Tuple.second >> .frame)

                frames =
                    List.map (Tuple.second >> .frame) triples
            in
            case ( List.minimum frames, List.maximum frames ) of
                ( Just lo, Just hi ) ->
                    if List.length triples < 3 then
                        pure model

                    else
                        let
                            n =
                                List.length triples

                            update s =
                                List.foldl
                                    (\( i, ( t, k ) ) acc ->
                                        let
                                            target =
                                                lo + round (toFloat (i * (hi - lo)) / toFloat (n - 1))
                                        in
                                        case Dict.get t.id acc.tracks of
                                            Just current ->
                                                Scene.upsertTrack (Keyframe.setFrame k.id target current) acc

                                            Nothing ->
                                                acc
                                    )
                                    s
                                    (List.indexedMap Tuple.pair triples)
                        in
                        Edit.commit "Distribute keyframes" (Document.updateScene scene.id update) model

                _ ->
                    pure model


reverseKeys : Model -> Update
reverseKeys model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                triples =
                    selectedKeyTriples model scene

                frames =
                    List.map (Tuple.second >> .frame) triples
            in
            case ( List.minimum frames, List.maximum frames ) of
                ( Just lo, Just hi ) ->
                    let
                        update s =
                            -- reverse within each track: value at frame f moves to lo+hi-f
                            let
                                byTrack =
                                    List.foldl (\( t, k ) acc -> Dict.update t.id (\m -> Just (k :: Maybe.withDefault [] m)) acc) Dict.empty triples
                            in
                            Dict.foldl
                                (\trackId keys acc ->
                                    case Dict.get trackId acc.tracks of
                                        Just t ->
                                            let
                                                ids =
                                                    List.map .id keys

                                                others =
                                                    List.filter (\k -> not (List.member k.id ids)) t.keyframes

                                                -- easing travels with the segment, so reassign from the next key
                                                sorted =
                                                    List.sortBy .frame keys

                                                easings =
                                                    List.map .easing sorted

                                                reversedEasings =
                                                    List.reverse (List.drop 1 easings) ++ List.take 1 easings

                                                moved =
                                                    List.map2 (\k e -> { k | frame = lo + hi - k.frame, easing = e }) sorted reversedEasings
                                            in
                                            Scene.upsertTrack { t | keyframes = List.sortBy .frame (moved ++ others) } acc

                                        Nothing ->
                                            acc
                                )
                                s
                                byTrack
                    in
                    Edit.commit "Reverse keyframes" (Document.updateScene scene.id update) model

                _ ->
                    pure model


copyKeys : Model -> Model
copyKeys model =
    case Model.activeScene model of
        Nothing ->
            model

        Just scene ->
            let
                triples =
                    selectedKeyTriples model scene

                base =
                    triples |> List.map (Tuple.second >> .frame) |> List.minimum |> Maybe.withDefault 0

                clip =
                    List.map
                        (\( t, k ) -> ( t.target.property, k.frame - base, E.object [ ( "value", Encode.propertyValue k.value ), ( "easing", Encode.easing k.easing ) ] ))
                        triples

                editor =
                    model.editor
            in
            if List.isEmpty clip then
                model

            else
                Edit.toast "info" (String.fromInt (List.length clip) ++ " keyframe(s) copied") { model | editor = { editor | keyClipboard = Just clip } }


{-| Paste keys onto the selected nodes at the playhead, keeping relative
spacing. Properties the target does not support are rejected with a notice.
-}
pasteKeys : Model -> Update
pasteKeys model =
    case ( Model.activeScene model, model.editor.keyClipboard ) of
        ( Just scene, Just clip ) ->
            let
                frame =
                    round (Edit.currentFrame model)

                targets =
                    Edit.selection model

                decodeKey v =
                    D.decodeValue (D.map2 Tuple.pair (D.field "value" Decode.propertyValue) (D.field "easing" Decode.easing)) v

                ( finalModel, finalScene, rejected ) =
                    List.foldl
                        (\nodeId ( m, s, rej ) ->
                            case Dict.get nodeId s.nodes of
                                Nothing ->
                                    ( m, s, rej )

                                Just node ->
                                    List.foldl
                                        (\( prop, offset, v ) ( mm, ss, rr ) ->
                                            if not (Node.supportsProperty node prop) then
                                                ( mm, ss, rr + 1 )

                                            else
                                                case decodeKey v of
                                                    Ok ( value, easing ) ->
                                                        let
                                                            ( ids, m2 ) =
                                                                Edit.nextIds 2 mm

                                                            kid =
                                                                List.head ids |> Maybe.withDefault "k"

                                                            tid =
                                                                List.drop 1 ids |> List.head |> Maybe.withDefault "t"

                                                            track =
                                                                Scene.trackFor nodeId prop ss |> Maybe.withDefault (Keyframe.newTrack tid nodeId prop)
                                                        in
                                                        ( m2, Scene.upsertTrack (Keyframe.insert { id = kid, frame = frame + offset, value = value, easing = easing } track) ss, rr )

                                                    Err _ ->
                                                        ( mm, ss, rr + 1 )
                                        )
                                        ( m, s, rej )
                                        clip
                        )
                        ( model, scene, 0 )
                        targets

                ( m3, cmd ) =
                    Edit.commit "Paste keyframes" (Document.setScene finalScene) finalModel
            in
            if rejected > 0 then
                ( Edit.toast "warning" (String.fromInt rejected ++ " keyframe(s) skipped: property not supported by target") m3, cmd )

            else
                ( m3, cmd )

        _ ->
            pure model


applyStagger : { startFrame : String, spacing : String, order : String } -> Model -> Update
applyStagger form model =
    case ( Model.activeScene model, String.toInt form.startFrame, String.toInt form.spacing ) of
        ( Just scene, Just start, Just spacing ) ->
            let
                ordered =
                    case form.order of
                        "reverse" ->
                            List.reverse (Edit.selection model)

                        "layer" ->
                            Scene.flattenOrder scene |> List.filter (\id -> List.member id (Edit.selection model))

                        _ ->
                            Edit.selection model

                update s =
                    List.foldl
                        (\( i, nodeId ) acc ->
                            let
                                tracks =
                                    Scene.tracksFor nodeId acc

                                firstFrame =
                                    tracks |> List.concatMap Keyframe.frames |> List.minimum |> Maybe.withDefault 0

                                delta =
                                    start + i * spacing - firstFrame
                            in
                            List.foldl (\t a -> Scene.upsertTrack (Keyframe.shift (List.map .id t.keyframes) delta t) a) acc tracks
                        )
                        s
                        (List.indexedMap Tuple.pair ordered)
            in
            Edit.commit "Stagger" (Document.updateScene scene.id update) { model | dialog = Model.NoDialog }

        _ ->
            pure (Edit.toast "error" "Stagger needs whole-number frames" model)



-- POINTER


rulerDown : PointerEvent -> Model -> Update
rulerDown ev model =
    let
        editor0 =
            model.editor

        stopped =
            Edit.endPlayback model

        e2 =
            stopped.editor

        pointer =
            { x = ev.clientX, y = ev.clientY, shift = ev.shift }

        scrubbing =
            { stopped | editor = { e2 | gesture = ScrubPlayhead, focus = Model.TimelineFocus, timelinePointer = pointer } }
    in
    if ev.button /= 0 then
        pure { model | editor = { editor0 | focus = Model.TimelineFocus } }

    else
        pure (setPlayhead (scrubFrame scrubbing pointer) scrubbing)


snapFrame : Model -> Float -> Float
snapFrame model frame =
    if model.preferences.timelineSnap then
        toFloat (round frame)

    else
        frame


{-| The frame under the pointer while scrubbing. Shift pulls the playhead onto
a nearby keyframe, the scene ends or the work range edges, the way desktop
motion tools snap the current time indicator.
-}
scrubFrame : Model -> { x : Float, y : Float, shift : Bool } -> Float
scrubFrame model pointer =
    let
        raw =
            frameAtX model pointer.x
    in
    if pointer.shift then
        nearestMark model raw |> Maybe.withDefault (snapFrame model raw)

    else
        snapFrame model raw


nearestMark : Model -> Float -> Maybe Float
nearestMark model frame =
    nearestMarkWith [] model frame


nearestMarkWith : List Int -> Model -> Float -> Maybe Float
nearestMarkWith extra model frame =
    case Model.activeScene model of
        Nothing ->
            Nothing

        Just scene ->
            let
                reach =
                    8 / (Model.activeView model).timelinePixelsPerFrame

                ( ws, we ) =
                    playbackRange scene

                marks =
                    extra
                        ++ 0
                        :: scene.durationFrames
                        :: ws
                        :: we
                        :: List.concatMap (.keyframes >> List.map .frame) (Dict.values scene.tracks)
            in
            marks
                |> List.map toFloat
                |> List.filter (\m -> abs (m - frame) <= reach)
                |> List.sortBy (\m -> abs (m - frame))
                |> List.head


{-| Press on the work area strip above the ruler. Near an existing edge it
trims that edge, inside the range it slides the range, and anywhere else it
starts a new range.
-}
rangeDown : PointerEvent -> Model -> Update
rangeDown ev model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                editor =
                    model.editor

                pressFrame =
                    frameAtX model ev.clientX

                frame =
                    clamp 0 scene.durationFrames (round pressFrame)

                reach =
                    6 / (Model.activeView model).timelinePixelsPerFrame

                edit =
                    case scene.workRange of
                        Just _ ->
                            let
                                ( ws, we ) =
                                    playbackRange scene
                            in
                            if abs (pressFrame - toFloat ws) <= reach then
                                Model.RangeFrom we

                            else if abs (pressFrame - toFloat we) <= reach then
                                Model.RangeFrom ws

                            else if pressFrame > toFloat ws && pressFrame < toFloat we then
                                Model.RangeSlide { start = ws, end = we, grab = frame }

                            else
                                Model.RangeFrom frame

                        Nothing ->
                            Model.RangeFrom frame

                focused =
                    { model | editor = { editor | focus = Model.TimelineFocus, timelinePointer = { x = ev.clientX, y = ev.clientY, shift = ev.shift } } }
            in
            if ev.button /= 0 then
                pure focused

            else
                let
                    e2 =
                        focused.editor
                in
                pure (Edit.beginGesture { focused | editor = { e2 | gesture = DragWorkRange { edit = edit, pressFrame = pressFrame, originalScene = scene } } })


{-| Press on the empty part of the track lanes: rubber-band keyframes. Shift
adds to the current key selection.
-}
lanesDown : PointerEvent -> Model -> Update
lanesDown ev model =
    let
        editor =
            model.editor

        base =
            if ev.shift then
                editor.selectedKeys

            else
                []

        frame =
            frameAtX model ev.clientX

        y =
            ev.clientY - editor.timelineRect.top

        focused =
            { model
                | editor = { editor | focus = Model.TimelineFocus, timelinePointer = { x = ev.clientX, y = ev.clientY, shift = ev.shift } }
                , openMenu = Nothing
                , contextMenu = Nothing
            }

        e2 =
            focused.editor
    in
    if ev.button /= 0 then
        pure focused

    else
        pure { focused | editor = { e2 | selectedKeys = base, gesture = MarqueeKeys { startFrame = frame, startY = y, currentFrame = frame, currentY = y, base = base } } }


{-| Press on a layer bar: the body moves the selected layers in time, the
ends trim their in or out points. Pressing an unselected layer selects it
first (Shift adds it).
-}
barDown : NodeId -> Model.BarEdge -> PointerEvent -> Model -> Update
barDown nodeId edge ev model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                editor =
                    model.editor

                current =
                    Edit.selection model

                selection =
                    if List.member nodeId current then
                        current

                    else if ev.shift then
                        current ++ [ nodeId ]

                    else
                        [ nodeId ]

                -- a layer inside another selected layer moves with its parent
                topLevel =
                    List.filter (\id -> not (List.any (\other -> other /= id && Scene.isAncestorOf other id scene) selection)) selection

                nodeIds =
                    nodeId :: List.filter ((/=) nodeId) topLevel

                selected =
                    Edit.mapActiveView (\v -> { v | selection = selection })
                        { model
                            | editor = { editor | focus = Model.TimelineFocus, selectedKeys = [], timelinePointer = { x = ev.clientX, y = ev.clientY, shift = ev.shift } }
                            , openMenu = Nothing
                            , contextMenu = Nothing
                        }

                e2 =
                    selected.editor
            in
            if ev.button /= 0 then
                pure selected

            else
                pure (Edit.beginGesture { selected | editor = { e2 | gesture = DragLayerBar { nodeIds = nodeIds, edge = edge, startFrame = frameAtX model ev.clientX, delta = 0, originalScene = scene } } })


{-| With Shift held, pull the dragged edge (or either end of a moving layer)
onto the playhead, a keyframe or a range end when one is near.
-}
snapBarDelta : Model -> { a | nodeIds : List NodeId, edge : Model.BarEdge, originalScene : Scene } -> Float -> Int
snapBarDelta model g raw =
    case g.nodeIds of
        grabbed :: _ ->
            let
                span =
                    LayerTime.spanOf g.originalScene grabbed

                edges =
                    case g.edge of
                        Model.BarBody ->
                            [ span.inFrame, span.outFrame ]

                        Model.BarIn ->
                            [ span.inFrame ]

                        Model.BarOut ->
                            [ span.outFrame ]

                playhead =
                    round (Edit.currentFrame model)

                candidates =
                    edges
                        |> List.filterMap
                            (\e ->
                                nearestMarkWith [ playhead ] model (toFloat e + raw)
                                    |> Maybe.map (\m -> round m - e)
                            )
            in
            candidates
                |> List.sortBy (\d -> abs (toFloat d - raw))
                |> List.head
                |> Maybe.withDefault (round raw)

        [] ->
            round raw


keyPointerDown : KeyRef -> PointerEvent -> Model -> Update
keyPointerDown ref ev model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                editor =
                    model.editor

                current =
                    editor.selectedKeys

                newSel =
                    if ev.shift then
                        if List.member ref current then
                            List.filter ((/=) ref) current

                        else
                            ref :: current

                    else if List.member ref current then
                        current

                    else
                        [ ref ]

                keys =
                    newSel
                        |> List.filterMap
                            (\r ->
                                Dict.get r.trackId scene.tracks
                                    |> Maybe.andThen (\t -> List.filter (\k -> k.id == r.keyId) t.keyframes |> List.head)
                                    |> Maybe.map (\k -> ( r.trackId, r.keyId, k.frame ))
                            )

                withSelection =
                    { model | editor = { editor | selectedKeys = newSel, focus = Model.TimelineFocus, timelinePointer = { x = ev.clientX, y = ev.clientY, shift = ev.shift } } }

                -- selecting a key also selects its node so the inspector follows
                nodeId =
                    Dict.get ref.trackId scene.tracks |> Maybe.map (.target >> .nodeId)

                withNode =
                    case nodeId of
                        Just nid ->
                            if List.member nid (Edit.selection withSelection) then
                                withSelection

                            else
                                Edit.mapActiveView (\v -> { v | selection = [ nid ] }) withSelection

                        Nothing ->
                            withSelection
            in
            if ev.button == 2 then
                pure { withNode | contextMenu = Just { x = ev.clientX, y = ev.clientY, target = Model.KeyframeContext ref } }

            else
                let
                    e2 =
                        withNode.editor
                in
                pure (Edit.beginGesture { withNode | editor = { e2 | gesture = DragKeys { keys = keys, startFrame = frameAtX model ev.clientX, delta = 0, originalScene = scene } } })


{-| True while a timeline drag owns the pointer, so window-level moves and
releases are routed here rather than to the canvas.
-}
isTimelineGesture : Model -> Bool
isTimelineGesture model =
    case model.editor.gesture of
        ScrubPlayhead ->
            True

        DragWorkRange _ ->
            True

        MarqueeKeys _ ->
            True

        DragKeys _ ->
            True

        DragLayerBar _ ->
            True

        _ ->
            False


pointerMove : { x : Float, y : Float, shift : Bool } -> Model -> Update
pointerMove pointer model0 =
    let
        editor0 =
            model0.editor

        model =
            { model0 | editor = { editor0 | timelinePointer = pointer } }
    in
    case model.editor.gesture of
        ScrubPlayhead ->
            pure (setPlayhead (scrubFrame model pointer) model)

        DragWorkRange g ->
            let
                duration =
                    g.originalScene.durationFrames

                raw =
                    if pointer.shift then
                        nearestMark model (frameAtX model pointer.x) |> Maybe.withDefault (frameAtX model pointer.x)

                    else
                        frameAtX model pointer.x

                frame =
                    clamp 0 duration (round raw)

                range =
                    case g.edit of
                        Model.RangeFrom fixed ->
                            if frame == fixed then
                                g.originalScene.workRange

                            else
                                Just { start = min fixed frame, end = max fixed frame }

                        Model.RangeSlide r ->
                            let
                                length =
                                    r.end - r.start

                                start =
                                    clamp 0 (duration - length) (r.start + frame - r.grab)
                            in
                            Just { start = start, end = start + length }
            in
            case Model.activeDoc model of
                Just open ->
                    pure
                        (Edit.transient
                            (\_ ->
                                Document.setScene
                                    (let
                                        original =
                                            g.originalScene
                                     in
                                     { original | workRange = range }
                                    )
                                    (Maybe.withDefault open.document model.editor.gestureOrigin)
                            )
                            model
                        )

                Nothing ->
                    pure model

        MarqueeKeys g ->
            let
                editor =
                    model.editor

                moved =
                    { g | currentFrame = frameAtX model pointer.x, currentY = pointer.y - editor.timelineRect.top }

                inside =
                    keysInMarquee model moved

                selection =
                    g.base ++ List.filter (\r -> not (List.member r g.base)) inside
            in
            pure { model | editor = { editor | gesture = MarqueeKeys moved, selectedKeys = selection } }

        DragLayerBar g ->
            let
                raw =
                    frameAtX model pointer.x - g.startFrame

                delta =
                    if pointer.shift then
                        snapBarDelta model g raw

                    else
                        round raw

                scene =
                    g.originalScene

                moved =
                    case g.edge of
                        Model.BarBody ->
                            LayerTime.shift g.nodeIds (clamp (LayerTime.minShift g.nodeIds scene) (max 0 (LayerTime.maxShift g.nodeIds scene)) delta) scene

                        Model.BarIn ->
                            List.foldl (LayerTime.trimEdge True delta) scene g.nodeIds

                        Model.BarOut ->
                            List.foldl (LayerTime.trimEdge False delta) scene g.nodeIds

                editor =
                    model.editor
            in
            if delta == g.delta then
                pure model

            else
                case Model.activeDoc model of
                    Just open ->
                        pure
                            (Edit.transient (\_ -> Document.setScene moved (Maybe.withDefault open.document editor.gestureOrigin))
                                { model | editor = { editor | gesture = DragLayerBar { g | delta = delta } } }
                            )

                    Nothing ->
                        pure model

        DragKeys g ->
            let
                delta =
                    round (frameAtX model pointer.x - g.startFrame)

                -- never drag a key before frame 0
                minFrame =
                    g.keys |> List.map (\( _, _, f ) -> f) |> List.minimum |> Maybe.withDefault 0

                clampedDelta =
                    max -minFrame delta

                editor =
                    model.editor

                refs =
                    List.map (\( t, k, _ ) -> { trackId = t, keyId = k }) g.keys
            in
            if clampedDelta == g.delta then
                pure model

            else
                case Model.activeDoc model of
                    Just open ->
                        pure
                            (Edit.transient (\_ -> Document.setScene (shiftScene refs clampedDelta g.originalScene) (Maybe.withDefault open.document editor.gestureOrigin))
                                { model | editor = { editor | gesture = DragKeys { g | delta = clampedDelta } } }
                            )

                    Nothing ->
                        pure model

        _ ->
            pure model


keysInMarquee : Model -> { a | startFrame : Float, startY : Float, currentFrame : Float, currentY : Float } -> List KeyRef
keysInMarquee model g =
    case Model.activeScene model of
        Nothing ->
            []

        Just scene ->
            let
                ppf =
                    (Model.activeView model).timelinePixelsPerFrame

                -- half a key diamond, so touching a key's edge picks it
                slack =
                    4.5

                ( x0, x1 ) =
                    ( min g.startFrame g.currentFrame * ppf - slack, max g.startFrame g.currentFrame * ppf + slack )

                ( y0, y1 ) =
                    ( min g.startY g.currentY - slack, max g.startY g.currentY + slack )
            in
            rows model scene
                |> List.indexedMap
                    (\i row ->
                        let
                            centre =
                                lanesTop model + (toFloat i + 0.5) * rowHeight
                        in
                        case ( row.track, row.property ) of
                            ( Just track, Just _ ) ->
                                if centre >= y0 && centre <= y1 then
                                    track.keyframes
                                        |> List.filter (\k -> toFloat k.frame * ppf >= x0 && toFloat k.frame * ppf <= x1)
                                        |> List.map (\k -> { trackId = track.id, keyId = k.id })

                                else
                                    []

                            _ ->
                                []
                    )
                |> List.concat


pointerUp : Model -> Update
pointerUp model =
    let
        editor =
            model.editor
    in
    case editor.gesture of
        ScrubPlayhead ->
            pure { model | editor = { editor | gesture = NoGesture } }

        DragWorkRange g ->
            let
                unchanged =
                    Maybe.map2 (\origin open -> origin == open.document) editor.gestureOrigin (Model.activeDoc model)
                        |> Maybe.withDefault True
            in
            if unchanged then
                -- a click on the strip without dragging moves the playhead there
                pure (setPlayhead (snapFrame model g.pressFrame) (Edit.cancelGesture model))

            else
                Edit.commitGesture "Work range" model

        MarqueeKeys _ ->
            pure { model | editor = { editor | gesture = NoGesture } }

        DragKeys g ->
            if g.delta == 0 then
                pure (Edit.cancelGesture model)

            else
                Edit.commitGesture "Move keyframes" model

        DragLayerBar g ->
            if g.delta == 0 then
                pure (Edit.cancelGesture model)

            else
                Edit.commitGesture (iif (g.edge == Model.BarBody) "Move layer" "Trim layer") model

        _ ->
            pure model


{-| How far the pointer is past the left or right edge of the track area
during a timeline drag, in pixels; zero while it is inside.
-}
edgeOverflow : Model -> Float
edgeOverflow model =
    let
        p =
            model.editor.timelinePointer

        rect =
            model.editor.timelineRect
    in
    if not (isTimelineGesture model) then
        0

    else if p.x < rect.left then
        p.x - rect.left

    else if p.x > rect.left + rect.width then
        p.x - (rect.left + rect.width)

    else
        0


{-| Scroll the track area while a drag holds the pointer past its edge, then
replay the pointer so the playhead, range or keys follow the new view. The
speed grows with the distance past the edge.
-}
autoScroll : Float -> Model -> Update
autoScroll dt model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                over =
                    edgeOverflow model

                view =
                    Model.activeView model

                maxScroll =
                    max 0 (toFloat scene.durationFrames * view.timelinePixelsPerFrame + 2 * timeOrigin - model.editor.timelineRect.width)

                scroll =
                    clamp 0 maxScroll (view.timelineScroll + clamp -60 60 (over * dt / 60))
            in
            if over == 0 || scroll == view.timelineScroll then
                pure model

            else
                pointerMove model.editor.timelinePointer (Edit.mapActiveView (\v -> { v | timelineScroll = scroll }) model)


{-| Move one end of the work range to the playhead (B for the start, N for the
end, as in After Effects). The other end stays put unless it would cross.
-}
setRangeEdgeAtPlayhead : Bool -> Model -> Update
setRangeEdgeAtPlayhead isStart model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                duration =
                    scene.durationFrames

                frame =
                    clamp 0 duration (round (Edit.currentFrame model))

                ( ws, we ) =
                    playbackRange scene

                range =
                    if isStart then
                        let
                            start =
                                min frame (duration - 1)
                        in
                        { start = start, end = max we (start + 1) }

                    else
                        let
                            end =
                                max frame 1
                        in
                        { start = min ws (end - 1), end = end }
            in
            Edit.commit
                (iif isStart "Set work range start" "Set work range end")
                (Document.updateScene scene.id (\s -> { s | workRange = Just range }))
                model


iif : Bool -> a -> a -> a
iif c a b =
    if c then
        a

    else
        b



-- ROWS


{-| Height of the ruler: the work area strip on top, frame numbers below. The
track list header matches it so the rows line up.
-}
rulerHeight : Float
rulerHeight =
    rangeStripHeight + 22


rangeStripHeight : Float
rangeStripHeight =
    9


filmstripHeight : Float
filmstripHeight =
    40


{-| Where the first track lane starts below the top of the track area: the
ruler, plus the filmstrip when it is shown.
-}
lanesTop : Model -> Float
lanesTop model =
    if model.editor.showFilmstrip then
        rulerHeight + filmstripHeight

    else
        rulerHeight


rowHeight : Float
rowHeight =
    22


type alias Row =
    { node : Node
    , property : Maybe PropertyPath
    , track : Maybe Track
    , depth : Int
    }


{-| Timeline rows: every animated node plus the current selection, each
followed by one row per animated (or, with "show all", animatable) property.
-}
rows : Model -> Scene -> List Row
rows model scene =
    let
        e =
            model.editor

        sel =
            (Model.activeView model).selection

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

                props =
                    if e.showAllProperties && List.member node.id sel then
                        Node.animatableProperties node

                    else
                        tracks |> List.map (.target >> .property)
            in
            Row node Nothing Nothing 0
                :: List.map (\p -> Row node (Just p) (tracks |> List.filter (\t -> t.target.property == p) |> List.head) 1) (dedupe props)
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
