module App.Timeline exposing
    ( addKeyAtPlayhead
    , applyStagger
    , copyKeys
    , distributeKeys
    , frameAtX
    , keyPointerDown
    , pasteKeys
    , playbackRange
    , pointerMove
    , pointerUp
    , removeSelectedKeys
    , reverseKeys
    , rulerDown
    , scaleKeys
    , setKeyEasing
    , setPlayhead
    , shiftKeys
    , tick
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
import Domain.Loop as Loop
import Domain.Node as Node
import Domain.Property as Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Json.Decode as D
import Json.Encode as E
import Shared.Ids exposing (NodeId)
import Time


trackListWidth : Float
trackListWidth =
    260


frameAtX : Model -> Float -> Float
frameAtX model clientX =
    let
        view =
            Model.activeView model

        rect =
            model.editor.timelineRect
    in
    (clientX - rect.left + view.timelineScroll) / view.timelinePixelsPerFrame


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
        frame =
            frameAtX model ev.clientX

        stopped =
            Edit.endPlayback model

        e2 =
            stopped.editor
    in
    pure (setPlayhead (snapFrame model frame) { stopped | editor = { e2 | gesture = ScrubPlayhead, focus = Model.TimelineFocus } })


snapFrame : Model -> Float -> Float
snapFrame model frame =
    if model.preferences.timelineSnap then
        toFloat (round frame)

    else
        frame


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
                    { model | editor = { editor | selectedKeys = newSel, focus = Model.TimelineFocus } }

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


pointerMove : Float -> Model -> Update
pointerMove clientX model =
    case model.editor.gesture of
        ScrubPlayhead ->
            pure (setPlayhead (snapFrame model (frameAtX model clientX)) model)

        DragKeys g ->
            let
                delta =
                    round (frameAtX model clientX - g.startFrame)

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


pointerUp : Model -> Update
pointerUp model =
    let
        editor =
            model.editor
    in
    case editor.gesture of
        ScrubPlayhead ->
            pure { model | editor = { editor | gesture = NoGesture } }

        DragKeys g ->
            if g.delta == 0 then
                pure (Edit.cancelGesture model)

            else
                Edit.commitGesture "Move keyframes" model

        _ ->
            pure model
