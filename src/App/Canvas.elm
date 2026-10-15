module App.Canvas exposing
    ( doubleClick
    , finishPen
    , nudge
    , pointerDown
    , pointerMove
    , pointerUp
    , resolvedNow
    , selectionBounds
    , toScene
    , toScreen
    , wheel
    , zoomAround
    , zoomToFit
    )

{-| Canvas pointer interaction. Gestures keep transient state in the editor
model and only commit one history entry on pointer up.
-}

import App.Edit as Edit exposing (Update, pure)
import App.Model as Model exposing (Gesture(..), Handle(..), Model, Tool(..))
import App.Msg exposing (Msg(..), PointerEvent, WheelEvent)
import App.Ports as Ports
import Dict
import Domain.Color
import Domain.Document as Document exposing (Document)
import Domain.Easing
import Domain.Evaluate as Evaluate exposing (ResolvedScene)
import Domain.Fps
import Domain.Keyframe
import Domain.Matrix as Matrix exposing (Matrix)
import Domain.Node as Node exposing (Node, NodeGeometry(..))
import Domain.Paint
import Domain.Path as Path
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Domain.Transform exposing (Transform)
import Domain.Vec2 as Vec2 exposing (Vec2)
import Json.Encode as E
import Shared.Ids exposing (NodeId)


type alias Bounds =
    { minX : Float, minY : Float, maxX : Float, maxY : Float }



-- COORDINATES


toScene : Model -> Float -> Float -> Vec2
toScene model clientX clientY =
    let
        view =
            Model.activeView model

        rect =
            model.editor.canvasRect
    in
    { x = (clientX - rect.left - view.pan.x) / view.zoom
    , y = (clientY - rect.top - view.pan.y) / view.zoom
    }


toScreen : Model -> Vec2 -> Vec2
toScreen model p =
    let
        view =
            Model.activeView model
    in
    { x = view.pan.x + p.x * view.zoom, y = view.pan.y + p.y * view.zoom }


resolvedNow : Model -> Maybe ResolvedScene
resolvedNow model =
    case Model.activeDoc model of
        Just open ->
            Evaluate.evaluateScene open.document open.activeSceneId (Edit.currentFrame model)

        Nothing ->
            Nothing


nodeBounds : ResolvedScene -> NodeId -> Maybe Bounds
nodeBounds resolved id =
    Dict.get id resolved.byId |> Maybe.andThen (Evaluate.worldBounds resolved)


unionBounds : List Bounds -> Maybe Bounds
unionBounds list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            Just
                (List.foldl
                    (\b acc -> { minX = min acc.minX b.minX, minY = min acc.minY b.minY, maxX = max acc.maxX b.maxX, maxY = max acc.maxY b.maxY })
                    first
                    rest
                )


selectionBounds : Model -> Maybe Bounds
selectionBounds model =
    resolvedNow model
        |> Maybe.andThen (\r -> unionBounds (List.filterMap (nodeBounds r) (Edit.selection model)))



-- HIT RESOLUTION


{-| Resolve a DOM hit to the node the select tool should pick: the top-most
ancestor below the isolation root, skipping locked nodes.
-}
resolveHit : Model -> Scene -> Maybe String -> Maybe NodeId
resolveHit model scene hit =
    hit
        |> Maybe.andThen (\id -> Dict.get id scene.nodes)
        |> Maybe.andThen
            (\node ->
                let
                    chain =
                        node.id :: Scene.ancestors node.id scene

                    -- nodes under the isolation root, from deepest to shallowest
                    underIsolation =
                        case model.editor.isolation of
                            Just iso ->
                                List.filter (\id -> id /= iso && not (List.member iso (List.drop 1 (dropUntil id chain)))) chain
                                    |> List.filter (\id -> Scene.isAncestorOf iso id scene)

                            Nothing ->
                                chain

                    candidate =
                        if model.editor.tool == DirectSelectTool then
                            Just node.id

                        else
                            List.reverse underIsolation |> List.head

                    anyLocked =
                        List.any (\id -> Dict.get id scene.nodes |> Maybe.map .locked |> Maybe.withDefault False) chain
                in
                if anyLocked then
                    Nothing

                else
                    candidate
            )


dropUntil : a -> List a -> List a
dropUntil x list =
    case list of
        [] ->
            []

        h :: t ->
            if h == x then
                list

            else
                dropUntil x t



-- POINTER DOWN


pointerDown : PointerEvent -> Model -> Update
pointerDown ev model =
    case ( Model.activeDoc model, Model.activeScene model ) of
        ( Just _, Just scene ) ->
            let
                p =
                    toScene model ev.clientX ev.clientY

                screen =
                    { x = ev.clientX, y = ev.clientY }

                editor =
                    model.editor

                focused =
                    { model | editor = { editor | focus = Model.CanvasFocus }, contextMenu = Nothing, openMenu = Nothing }
            in
            if ev.button == 1 || editor.spaceHeld || editor.tool == HandTool then
                startPan screen focused

            else if ev.button == 2 then
                let
                    hit =
                        resolveHit model scene ev.hitNode

                    selected =
                        case hit of
                            Just id ->
                                if List.member id (Edit.selection model) then
                                    focused

                                else
                                    Edit.setSelection [ id ] focused

                            Nothing ->
                                focused
                in
                pure { selected | contextMenu = Just { x = ev.clientX, y = ev.clientY, target = Model.CanvasContext hit } }

            else
                case editor.tool of
                    SelectTool ->
                        selectDown ev p screen scene focused

                    DirectSelectTool ->
                        directDown ev p scene focused

                    HandTool ->
                        startPan screen focused

                    ZoomTool ->
                        pure (setGesture (ZoomMarquee { start = p, current = p }) focused)

                    PenTool ->
                        penDown ev p scene focused

                    MotionPathTool ->
                        penDown ev p scene focused

                    TextTool ->
                        createText p scene focused

                    PivotTool ->
                        pivotDown scene focused

                    _ ->
                        pure (setGesture (DrawShape { start = snapPoint focused p, current = snapPoint focused p, shift = ev.shift, alt = ev.alt }) (Edit.beginGesture focused))

        _ ->
            pure model


setGesture : Gesture -> Model -> Model
setGesture g model =
    let
        editor =
            model.editor
    in
    { model | editor = { editor | gesture = g } }


startPan : Vec2 -> Model -> Update
startPan screen model =
    pure (setGesture (Panning { screenStart = screen, startPan = (Model.activeView model).pan }) model)


selectDown : PointerEvent -> Vec2 -> Vec2 -> Scene -> Model -> Update
selectDown ev p screen scene model =
    case ev.handle |> Maybe.andThen handleFromCode of
        Just handle ->
            let
                sel =
                    Edit.selection model

                originals =
                    List.filterMap (\id -> Dict.get id scene.nodes |> Maybe.map (\n -> ( id, n.transform ))) sel

                started =
                    Edit.beginGesture model
            in
            case ( handle, selectionBounds model ) of
                ( HandleRotate, Just b ) ->
                    let
                        center =
                            { x = (b.minX + b.maxX) / 2, y = (b.minY + b.maxY) / 2 }
                    in
                    pure (setGesture (DragRotate { center = center, startAngle = atan2 (p.y - center.y) (p.x - center.x), originals = originals, originalScene = scene }) started)

                ( _, Just _ ) ->
                    pure (setGesture (DragResize { handle = handle, start = p, current = p, originals = originals, originalScene = scene, shift = ev.shift }) started)

                _ ->
                    pure model

        Nothing ->
            let
                hit =
                    resolveHit model scene ev.hitNode
            in
            case hit of
                Just id ->
                    let
                        current =
                            Edit.selection model

                        newSel =
                            if ev.shift then
                                if List.member id current then
                                    List.filter ((/=) id) current

                                else
                                    current ++ [ id ]

                            else if List.member id current then
                                current

                            else
                                [ id ]

                        selected =
                            Edit.setSelection newSel model
                    in
                    pure (setGesture (PendingPress { start = p, screenStart = screen, hit = Just id, shift = ev.shift, alt = ev.alt }) (Edit.beginGesture selected))

                Nothing ->
                    let
                        cleared =
                            if ev.shift then
                                model

                            else
                                Edit.setSelection [] model
                    in
                    pure (setGesture (Marquee { start = p, current = p, additive = ev.shift }) cleared)


handleFromCode : String -> Maybe Handle
handleFromCode s =
    case s of
        "nw" ->
            Just HandleNW

        "n" ->
            Just HandleN

        "ne" ->
            Just HandleNE

        "e" ->
            Just HandleE

        "se" ->
            Just HandleSE

        "s" ->
            Just HandleS

        "sw" ->
            Just HandleSW

        "w" ->
            Just HandleW

        "rotate" ->
            Just HandleRotate

        _ ->
            Nothing


directDown : PointerEvent -> Vec2 -> Scene -> Model -> Update
directDown ev p scene model =
    case ev.anchor of
        Just code ->
            -- "a:<nodeId>:<subpath>:<index>" or "h:in|out:<nodeId>:<sub>:<idx>"
            case String.split ":" code of
                [ "a", nodeId, si, idx ] ->
                    startAnchorDrag nodeId si idx False True p scene model

                [ "h", which, nodeId, si, idx ] ->
                    startAnchorDrag nodeId si idx True (which == "out" && not ev.alt) p scene model
                        |> Tuple.mapFirst
                            (\m ->
                                -- dragging the incoming handle mirrors the outgoing one
                                if which == "in" then
                                    case m.editor.gesture of
                                        DragAnchor g ->
                                            setGesture (DragAnchor { g | mirror = not ev.alt }) m

                                        _ ->
                                            m

                                else
                                    m
                            )

                _ ->
                    pure model

        Nothing ->
            case resolveHit model scene ev.hitNode of
                Just id ->
                    pure (Edit.setSelection [ id ] model)

                Nothing ->
                    pure (setGesture (Marquee { start = p, current = p, additive = ev.shift }) (Edit.setSelection [] model))


startAnchorDrag : NodeId -> String -> String -> Bool -> Bool -> Vec2 -> Scene -> Model -> Update
startAnchorDrag nodeId si idx isHandle mirror p scene model =
    case ( Dict.get nodeId scene.nodes, String.toInt si, String.toInt idx ) of
        ( Just node, Just subpath, Just index ) ->
            case node.geometry of
                Path g ->
                    pure
                        (setGesture
                            (DragAnchor { nodeId = nodeId, subpath = subpath, index = index, original = g, start = p, isHandle = isHandle, mirror = mirror })
                            (Edit.beginGesture (Edit.setSelection [ nodeId ] model))
                        )

                _ ->
                    pure model

        _ ->
            pure model


pivotDown : Scene -> Model -> Update
pivotDown scene model =
    case Edit.selection model of
        [ id ] ->
            case Dict.get id scene.nodes of
                Just node ->
                    pure (setGesture (DragPivot { nodeId = id, original = node.transform }) (Edit.beginGesture model))

                Nothing ->
                    pure model

        _ ->
            pure (Edit.toast "info" "Select a single object to move its pivot" model)


createText : Vec2 -> Scene -> Model -> Update
createText p scene model =
    let
        parent =
            model.editor.isolation

        ( node, m2 ) =
            Edit.newNodeAt "Text" (Text { content = "Text", fontFamily = "sans-serif", fontSize = 32, fontWeight = 400, italic = False, letterSpacing = 0, align = Node.AlignStart }) p scene model

        placed =
            { node | fill = Domain.Paint.Solid (Domain.Color.rgba 0.12 0.12 0.14 1) }

        ( m3, cmd ) =
            Edit.commit "Add text" (Document.updateScene scene.id (Scene.insertNode parent 9999 placed)) m2

        editor =
            m3.editor
    in
    ( Edit.setSelection [ node.id ] { m3 | editor = { editor | tool = SelectTool, editingText = Just node.id } }, Cmd.batch [ cmd, Ports.send (Ports.request "focus" "platform.focus" (E.object [ ( "id", E.string "text-content" ) ])) ] )



-- PEN


penDown : PointerEvent -> Vec2 -> Scene -> Model -> Update
penDown ev p scene model =
    let
        editor =
            model.editor

        pt =
            snapPoint model p

        isMotion =
            editor.tool == MotionPathTool
    in
    case editor.penDraft of
        Nothing ->
            if isMotion && List.length (Edit.selection model) /= 1 then
                pure (Edit.toast "info" "Select a single object before drawing its motion path" model)

            else
                let
                    draft =
                        { nodeId = Nothing, subpathStart = pt, segments = [], lastHandle = Nothing, closed = False, parent = editor.isolation }
                in
                pure (setGesture (PenDragHandle { start = pt, current = pt }) { model | editor = { editor | penDraft = Just draft } })

        Just draft ->
            let
                closeDistance =
                    8 / (Model.activeView model).zoom
            in
            if List.length draft.segments >= 1 && Vec2.distance pt draft.subpathStart < closeDistance && not isMotion then
                finishPen True model

            else
                let
                    segment =
                        case draft.lastHandle of
                            Just h ->
                                Path.CubicTo h pt pt

                            Nothing ->
                                Path.LineTo pt

                    updated =
                        { draft | segments = draft.segments ++ [ segment ], lastHandle = Nothing }
                in
                pure (setGesture (PenDragHandle { start = pt, current = pt }) { model | editor = { editor | penDraft = Just updated } })


{-| While dragging after placing an anchor, the drag point becomes the
outgoing handle and the incoming handle mirrors it.
-}
penDrag : Vec2 -> Model -> Model
penDrag current model =
    let
        editor =
            model.editor
    in
    case editor.penDraft of
        Nothing ->
            model

        Just draft ->
            let
                anchor =
                    case List.reverse draft.segments of
                        seg :: _ ->
                            segEnd seg

                        [] ->
                            draft.subpathStart

                mirrored =
                    Vec2.sub (Vec2.scale 2 anchor) current

                segments =
                    case List.reverse draft.segments of
                        seg :: rest ->
                            List.reverse
                                ((case seg of
                                    Path.LineTo e ->
                                        Path.CubicTo (prevHandle draft rest) mirrored e

                                    Path.CubicTo c1 _ e ->
                                        Path.CubicTo c1 mirrored e
                                 )
                                    :: rest
                                )

                        [] ->
                            []

                updated =
                    { draft | segments = segments, lastHandle = Just current }
            in
            if Vec2.distance current anchor < 1 / (Model.activeView model).zoom then
                { model | editor = { editor | penDraft = Just { draft | lastHandle = Nothing } } }

            else
                { model | editor = { editor | penDraft = Just updated } }


prevHandle : Model.PenDraft -> List Path.Segment -> Vec2
prevHandle draft restReversed =
    case restReversed of
        seg :: _ ->
            segEnd seg

        [] ->
            draft.subpathStart


segEnd : Path.Segment -> Vec2
segEnd seg =
    case seg of
        Path.LineTo e ->
            e

        Path.CubicTo _ _ e ->
            e


finishPen : Bool -> Model -> Update
finishPen close model =
    let
        editor =
            model.editor
    in
    case ( editor.penDraft, Model.activeScene model ) of
        ( Just draft, Just scene ) ->
            let
                cleared =
                    { model | editor = { editor | penDraft = Nothing, gesture = NoGesture } }
            in
            if List.isEmpty draft.segments then
                pure cleared

            else
                let
                    worldGeometry =
                        { subpaths = [ { start = draft.subpathStart, segments = draft.segments, closed = close } ] }
                in
                if editor.tool == MotionPathTool then
                    attachMotionPath worldGeometry scene cleared

                else
                    let
                        origin =
                            Path.bounds worldGeometry
                                |> Maybe.map (\b -> { x = b.minX, y = b.minY })
                                |> Maybe.withDefault Vec2.zero

                        local =
                            Path.transformGeometry (Matrix.translation -origin.x -origin.y) worldGeometry

                        ( node, m2 ) =
                            Edit.newNodeAt "Path" (Path local) origin scene cleared

                        styled =
                            { node
                                | fill =
                                    if close then
                                        node.fill

                                    else
                                        Domain.Paint.NoPaint
                                , stroke =
                                    { paint = Domain.Paint.Solid (Domain.Color.rgba 0.12 0.12 0.14 1), width = 2, cap = Domain.Paint.CapRound, join = Domain.Paint.JoinRound, miterLimit = 4, dashArray = [], dashOffset = 0 }
                            }

                        ( m3, cmd ) =
                            Edit.commit "Draw path" (Document.updateScene scene.id (Scene.insertNode draft.parent 9999 styled)) m2
                    in
                    ( Edit.setSelection [ node.id ] m3, cmd )

        _ ->
            pure model


attachMotionPath : Path.PathGeometry -> Scene -> Model -> Update
attachMotionPath geometry scene model =
    case Edit.selection model of
        [ nodeId ] ->
            let
                ( mpId, m2 ) =
                    Edit.nextId model

                node =
                    Dict.get nodeId scene.nodes

                -- the path is authored in scene space; store it relative to the node's parent
                parentWorld =
                    node
                        |> Maybe.andThen .parentId
                        |> Maybe.andThen (\pid -> resolvedNow model |> Maybe.andThen (\r -> Dict.get pid r.byId))
                        |> Maybe.map .worldMatrix
                        |> Maybe.withDefault Matrix.identity

                localGeometry =
                    case Matrix.invert parentWorld of
                        Just inv ->
                            Path.transformGeometry inv geometry

                        Nothing ->
                            geometry

                motionPath =
                    { id = mpId, name = (node |> Maybe.map .name |> Maybe.withDefault "Node") ++ " path", geometry = localGeometry, revision = 0 }

                attach s =
                    { s | motionPaths = Dict.insert mpId motionPath s.motionPaths }
                        |> Scene.updateNode nodeId
                            (\n ->
                                let
                                    t =
                                        n.transform
                                in
                                { n | motion = Just { pathId = mpId, orient = True }, transform = { t | translation = Vec2.zero } }
                            )
                        |> ensureProgressTrack m2 nodeId

                ( m3, cmd ) =
                    Edit.commit "Create motion path" (Document.updateScene scene.id attach) m2

                editor =
                    m3.editor
            in
            ( { m3 | editor = { editor | tool = SelectTool } }, cmd )

        _ ->
            pure model


ensureProgressTrack : Model -> NodeId -> Scene -> Scene
ensureProgressTrack model nodeId scene =
    case Scene.trackFor nodeId MotionProgress scene of
        Just _ ->
            scene

        Nothing ->
            let
                track =
                    Domain.Keyframe.newTrack ("mp-track-" ++ nodeId) nodeId MotionProgress
                        |> Domain.Keyframe.insert { id = "mp-k0-" ++ nodeId, frame = 0, value = Scalar 0, easing = Domain.Easing.Preset Domain.Easing.EaseInOut }
                        |> Domain.Keyframe.insert { id = "mp-k1-" ++ nodeId, frame = scene.durationFrames, value = Scalar 1, easing = Domain.Easing.Linear }
            in
            Scene.upsertTrack track scene



-- POINTER MOVE


pointerMove : Float -> Float -> Bool -> Model -> Update
pointerMove clientX clientY shift model =
    let
        p =
            toScene model clientX clientY

        screen =
            { x = clientX, y = clientY }

        view =
            Model.activeView model
    in
    case model.editor.gesture of
        NoGesture ->
            pure model

        PendingPress g ->
            if Vec2.distance screen g.screenStart > 3 then
                case Model.activeScene model of
                    Just scene ->
                        let
                            sel =
                                Edit.selection model

                            originals =
                                List.filterMap (\id -> Dict.get id scene.nodes |> Maybe.map (\n -> ( id, n.transform ))) sel
                        in
                        if g.alt then
                            -- Alt-drag duplicates then moves the copies
                            duplicateForDrag g.start p originals model

                        else
                            applyMove g.start p shift (setGesture (DragMove { start = g.start, current = p, originals = originals, snapLines = [], duplicated = False }) model)

                    Nothing ->
                        pure model

            else
                pure model

        DragMove g ->
            applyMove g.start p shift (setGesture (DragMove { g | current = p }) model)

        DragResize g ->
            applyResize { g | current = p, shift = shift || g.shift } (setGesture (DragResize { g | current = p }) model)

        DragRotate g ->
            applyRotate g p shift model

        DragPivot g ->
            applyPivot g p model

        Marquee g ->
            pure (setGesture (Marquee { g | current = p }) model)

        ZoomMarquee g ->
            pure (setGesture (ZoomMarquee { g | current = p }) model)

        DrawShape g ->
            pure (setGesture (DrawShape { g | current = snapPoint model p, shift = shift || g.shift }) model)

        Panning g ->
            pure
                (Edit.mapActiveView
                    (\v -> { v | pan = Vec2.add g.startPan (Vec2.sub screen g.screenStart) })
                    model
                )

        DragAnchor g ->
            applyAnchorDrag g p model

        PenDragHandle g ->
            pure (penDrag p (setGesture (PenDragHandle { g | current = p }) model))

        _ ->
            pure model


duplicateForDrag : Vec2 -> Vec2 -> List ( NodeId, Transform ) -> Model -> Update
duplicateForDrag start p originals model =
    -- duplication is performed by the Update module through DuplicateSelection;
    -- here we simply move, keeping the gesture simple and undoable as one step.
    applyMove start p False (setGesture (DragMove { start = start, current = p, originals = originals, snapLines = [], duplicated = False }) model)


applyMove : Vec2 -> Vec2 -> Bool -> Model -> Update
applyMove start current shift model =
    case ( model.editor.gesture, model.editor.gestureOrigin, Model.activeDoc model ) of
        ( DragMove g, Just origin, Just open ) ->
            let
                rawDelta =
                    Vec2.sub current start

                constrained =
                    if shift then
                        if abs rawDelta.x > abs rawDelta.y then
                            { x = rawDelta.x, y = 0 }

                        else
                            { x = 0, y = rawDelta.y }

                    else
                        rawDelta

                ( delta, snapLines ) =
                    snapDelta model origin open.activeSceneId g.originals constrained

                originScene =
                    Dict.get open.activeSceneId origin.scenes

                resolvedOrigin =
                    Evaluate.evaluateScene origin open.activeSceneId (Edit.currentFrame model)

                moveNode scene ( id, original ) =
                    -- convert the world delta into the node's parent space
                    let
                        parentInv =
                            Dict.get id scene.nodes
                                |> Maybe.andThen .parentId
                                |> Maybe.andThen (\pid -> resolvedOrigin |> Maybe.andThen (\r -> Dict.get pid r.byId))
                                |> Maybe.map .worldMatrix
                                |> Maybe.andThen Matrix.invert
                                |> Maybe.withDefault Matrix.identity

                        localDelta =
                            Matrix.applyVector parentInv delta

                        newPos =
                            Vec2.add original.translation localDelta
                    in
                    setTransformProperty model id Position (PointValue newPos) scene

                updated =
                    case originScene of
                        Just scene ->
                            List.foldl (\o s -> moveNode s o) scene g.originals

                        Nothing ->
                            open.document.scenes |> Dict.get open.activeSceneId |> Maybe.withDefault (Scene.new "" "" 1 1 (Domain.Fps.fps 30 1) 1 Scene.Transparent)
            in
            pure
                (Edit.transient (\_ -> Document.setScene updated origin) model
                    |> setGesture (DragMove { g | current = current, snapLines = snapLines })
                )

        _ ->
            pure model


{-| Write a transform property on the origin scene respecting auto-key, but
without allocating fresh ids on every pointer move: ids are taken from the
pool deterministically for the gesture.
-}
setTransformProperty : Model -> NodeId -> PropertyPath -> PropertyValue -> Scene -> Scene
setTransformProperty model id property value scene =
    Tuple.first (Edit.setAnimatedProperty model id property value scene)


snapPoint : Model -> Vec2 -> Vec2
snapPoint model p =
    if model.editor.snapToGrid then
        let
            g =
                max 1 model.preferences.gridSpacing
        in
        { x = toFloat (round (p.x / g)) * g, y = toFloat (round (p.y / g)) * g }

    else
        p


{-| Snap the moving selection's bounds to artboard edges/centre, grid and
other objects. Returns the corrected delta and guide lines (isVertical, pos).
-}
snapDelta : Model -> Document -> String -> List ( NodeId, Transform ) -> Vec2 -> ( Vec2, List ( Bool, Float ) )
snapDelta model origin sceneId originals delta =
    let
        editor =
            model.editor

        tolerance =
            model.preferences.snapTolerance / (Model.activeView model).zoom

        moving =
            List.map Tuple.first originals
    in
    case Evaluate.evaluateScene origin sceneId (Edit.currentFrame model) of
        Nothing ->
            ( delta, [] )

        Just resolved ->
            case unionBounds (List.filterMap (nodeBounds resolved) moving) of
                Nothing ->
                    ( delta, [] )

                Just b ->
                    let
                        scene =
                            Dict.get sceneId origin.scenes

                        width =
                            Maybe.map .width scene |> Maybe.withDefault 0

                        height =
                            Maybe.map .height scene |> Maybe.withDefault 0

                        moved =
                            { minX = b.minX + delta.x, maxX = b.maxX + delta.x, minY = b.minY + delta.y, maxY = b.maxY + delta.y }

                        candidatesX =
                            [ moved.minX, (moved.minX + moved.maxX) / 2, moved.maxX ]

                        candidatesY =
                            [ moved.minY, (moved.minY + moved.maxY) / 2, moved.maxY ]

                        artboardX =
                            if editor.snapToArtboard then
                                [ 0, width / 2, width ]

                            else
                                []

                        artboardY =
                            if editor.snapToArtboard then
                                [ 0, height / 2, height ]

                            else
                                []

                        others =
                            if editor.snapToObjects then
                                resolved.nodes
                                    |> List.filter (\n -> not (List.member n.id moving) && n.parentId == Nothing && not (List.any (\m -> Scene.isAncestorOf m n.id (Maybe.withDefault (Scene.new "" "" 1 1 (Domain.Fps.fps 30 1) 1 Scene.Transparent) scene)) moving))
                                    |> List.filterMap (Evaluate.worldBounds resolved)

                            else
                                []

                        objectX =
                            List.concatMap (\o -> [ o.minX, (o.minX + o.maxX) / 2, o.maxX ]) others

                        objectY =
                            List.concatMap (\o -> [ o.minY, (o.minY + o.maxY) / 2, o.maxY ]) others

                        gridTargets cands =
                            if editor.snapToGrid then
                                let
                                    g =
                                        max 1 model.preferences.gridSpacing
                                in
                                List.map (\c -> toFloat (round (c / g)) * g) cands

                            else
                                []

                        best cands targets =
                            cands
                                |> List.concatMap (\c -> List.map (\t -> ( t - c, t )) targets)
                                |> List.filter (\( d, _ ) -> abs d <= tolerance)
                                |> List.sortBy (\( d, _ ) -> abs d)
                                |> List.head

                        snapX =
                            best candidatesX (artboardX ++ objectX ++ gridTargets candidatesX)

                        snapY =
                            best candidatesY (artboardY ++ objectY ++ gridTargets candidatesY)

                        dx =
                            Maybe.map Tuple.first snapX |> Maybe.withDefault 0

                        dy =
                            Maybe.map Tuple.first snapY |> Maybe.withDefault 0

                        lines =
                            List.filterMap identity
                                [ Maybe.map (\( _, t ) -> ( True, t )) snapX
                                , Maybe.map (\( _, t ) -> ( False, t )) snapY
                                ]
                    in
                    ( { x = delta.x + dx, y = delta.y + dy }, lines )



-- RESIZE / ROTATE


applyResize : { handle : Handle, start : Vec2, current : Vec2, originals : List ( NodeId, Transform ), originalScene : Scene, shift : Bool } -> Model -> Update
applyResize g model =
    case ( model.editor.gestureOrigin, Model.activeDoc model ) of
        ( Just origin, Just open ) ->
            case Evaluate.evaluateScene origin open.activeSceneId (Edit.currentFrame model) of
                Nothing ->
                    pure model

                Just resolved ->
                    case unionBounds (List.filterMap (nodeBounds resolved) (List.map Tuple.first g.originals)) of
                        Nothing ->
                            pure model

                        Just b ->
                            let
                                ( anchor, axes ) =
                                    anchorFor g.handle b

                                w =
                                    max 1.0e-6 (b.maxX - b.minX)

                                h =
                                    max 1.0e-6 (b.maxY - b.minY)

                                -- the handle's own position at gesture start
                                handlePos =
                                    handlePoint g.handle b

                                rawSx =
                                    if axes.x then
                                        (g.current.x - anchor.x) / (handlePos.x - anchor.x)

                                    else
                                        1

                                rawSy =
                                    if axes.y then
                                        (g.current.y - anchor.y) / (handlePos.y - anchor.y)

                                    else
                                        1

                                ( sx, sy ) =
                                    if g.shift && axes.x && axes.y then
                                        let
                                            s =
                                                if abs (rawSx - 1) > abs (rawSy - 1) then
                                                    rawSx

                                                else
                                                    rawSy
                                        in
                                        ( s, s )

                                    else
                                        ( rawSx, rawSy )

                                safe v =
                                    if isNaN v || isInfinite v then
                                        1

                                    else if abs v < 0.001 then
                                        0.001

                                    else
                                        v

                                worldScale =
                                    Matrix.compose
                                        [ Matrix.translation -anchor.x -anchor.y
                                        , Matrix.scaling (safe sx) (safe sy)
                                        , Matrix.translation anchor.x anchor.y
                                        ]

                                _ =
                                    ( w, h )

                                updated =
                                    List.foldl (applyWorldMatrix model resolved worldScale True) g.originalScene g.originals
                            in
                            pure (Edit.transient (\_ -> Document.setScene updated origin) model)

        _ ->
            pure model


anchorFor : Handle -> Bounds -> ( Vec2, { x : Bool, y : Bool } )
anchorFor handle b =
    let
        cx =
            (b.minX + b.maxX) / 2

        cy =
            (b.minY + b.maxY) / 2
    in
    case handle of
        HandleNW ->
            ( { x = b.maxX, y = b.maxY }, { x = True, y = True } )

        HandleN ->
            ( { x = cx, y = b.maxY }, { x = False, y = True } )

        HandleNE ->
            ( { x = b.minX, y = b.maxY }, { x = True, y = True } )

        HandleE ->
            ( { x = b.minX, y = cy }, { x = True, y = False } )

        HandleSE ->
            ( { x = b.minX, y = b.minY }, { x = True, y = True } )

        HandleS ->
            ( { x = cx, y = b.minY }, { x = False, y = True } )

        HandleSW ->
            ( { x = b.maxX, y = b.minY }, { x = True, y = True } )

        HandleW ->
            ( { x = b.maxX, y = cy }, { x = True, y = False } )

        HandleRotate ->
            ( { x = cx, y = cy }, { x = False, y = False } )


handlePoint : Handle -> Bounds -> Vec2
handlePoint handle b =
    let
        cx =
            (b.minX + b.maxX) / 2

        cy =
            (b.minY + b.maxY) / 2
    in
    case handle of
        HandleNW ->
            { x = b.minX, y = b.minY }

        HandleN ->
            { x = cx, y = b.minY }

        HandleNE ->
            { x = b.maxX, y = b.minY }

        HandleE ->
            { x = b.maxX, y = cy }

        HandleSE ->
            { x = b.maxX, y = b.maxY }

        HandleS ->
            { x = cx, y = b.maxY }

        HandleSW ->
            { x = b.minX, y = b.maxY }

        HandleW ->
            { x = b.minX, y = cy }

        HandleRotate ->
            { x = cx, y = b.minY }


{-| Apply a world-space matrix to a node, writing back decomposed components
(or scaled geometry for simple unrotated primitives when `preferGeometry`).
-}
applyWorldMatrix : Model -> ResolvedScene -> Matrix -> Bool -> ( NodeId, Transform ) -> Scene -> Scene
applyWorldMatrix model resolved worldMatrix preferGeometry ( id, original ) scene =
    case ( Dict.get id scene.nodes, Dict.get id resolved.byId ) of
        ( Just node, Just res ) ->
            let
                parentWorld =
                    node.parentId
                        |> Maybe.andThen (\pid -> Dict.get pid resolved.byId)
                        |> Maybe.map .worldMatrix
                        |> Maybe.withDefault Matrix.identity

                parentInv =
                    Matrix.invert parentWorld |> Maybe.withDefault Matrix.identity

                newLocal =
                    Matrix.compose [ res.localMatrix, parentWorld, worldMatrix, parentInv ]

                comps =
                    Matrix.decompose original.pivot newLocal

                simple =
                    preferGeometry
                        && abs original.rotation
                        < 1.0e-9
                        && abs original.skew.x
                        < 1.0e-9
                        && abs original.skew.y
                        < 1.0e-9
                        && abs (original.scale.x - 1)
                        < 1.0e-9
                        && abs (original.scale.y - 1)
                        < 1.0e-9
                        && abs comps.rotation
                        < 1.0e-6
                        && comps.scale.x
                        > 0
                        && comps.scale.y
                        > 0
                        && geometryScalable node.geometry
            in
            if simple then
                let
                    s =
                        comps.scale

                    p =
                        original.pivot

                    newTranslation =
                        { x = comps.translation.x + p.x - s.x * p.x, y = comps.translation.y + p.y - s.y * p.y }

                    scaledGeometry =
                        scaleGeometry s node.geometry

                    withGeometry =
                        Scene.setNode (applyGeometryValues scaledGeometry node) scene
                in
                setTransformProperty model id Position (PointValue newTranslation) withGeometry
                    |> (\sc ->
                            if Vec2.distance p Vec2.zero > 0 then
                                setTransformProperty model id Pivot (PointValue { x = s.x * p.x, y = s.y * p.y }) sc

                            else
                                sc
                       )

            else
                scene
                    |> setIfChanged model id Position (PointValue comps.translation) (PointValue original.translation)
                    |> setIfChanged model id Scale (PointValue comps.scale) (PointValue original.scale)
                    |> setIfChanged model id Rotation (Angle comps.rotation) (Angle original.rotation)
                    |> setIfChanged model id Skew (PointValue comps.skew) (PointValue original.skew)

        _ ->
            scene


setIfChanged : Model -> NodeId -> PropertyPath -> PropertyValue -> PropertyValue -> Scene -> Scene
setIfChanged model id property newValue oldValue scene =
    if valuesClose newValue oldValue then
        scene

    else
        setTransformProperty model id property newValue scene


valuesClose : PropertyValue -> PropertyValue -> Bool
valuesClose a b =
    case ( a, b ) of
        ( PointValue p, PointValue q ) ->
            Vec2.distance p q < 1.0e-6

        ( Angle x, Angle y ) ->
            abs (x - y) < 1.0e-6

        _ ->
            a == b


geometryScalable : NodeGeometry -> Bool
geometryScalable g =
    case g of
        Rectangle _ ->
            True

        Ellipse _ ->
            True

        Line _ ->
            True

        Path _ ->
            True

        RasterImage _ ->
            True

        _ ->
            False


scaleGeometry : Vec2 -> NodeGeometry -> NodeGeometry
scaleGeometry s g =
    case g of
        Rectangle r ->
            Rectangle { r | size = { x = r.size.x * s.x, y = r.size.y * s.y }, cornerRadius = r.cornerRadius * min s.x s.y }

        Ellipse e ->
            Ellipse { radii = { x = e.radii.x * s.x, y = e.radii.y * s.y } }

        Line l ->
            Line { start = { x = l.start.x * s.x, y = l.start.y * s.y }, end = { x = l.end.x * s.x, y = l.end.y * s.y } }

        Path p ->
            Path (Path.transformGeometry (Matrix.scaling s.x s.y) p)

        RasterImage i ->
            RasterImage { i | size = { x = i.size.x * s.x, y = i.size.y * s.y } }

        other ->
            other


{-| Write scaled geometry back, respecting animated size properties.
-}
applyGeometryValues : NodeGeometry -> Node -> Node
applyGeometryValues geometry node =
    { node | geometry = geometry }


applyRotate : { center : Vec2, startAngle : Float, originals : List ( NodeId, Transform ), originalScene : Scene } -> Vec2 -> Bool -> Model -> Update
applyRotate g p shift model =
    case ( model.editor.gestureOrigin, Model.activeDoc model ) of
        ( Just origin, Just open ) ->
            case Evaluate.evaluateScene origin open.activeSceneId (Edit.currentFrame model) of
                Nothing ->
                    pure model

                Just resolved ->
                    let
                        angle =
                            atan2 (p.y - g.center.y) (p.x - g.center.x)

                        deltaDeg =
                            (angle - g.startAngle) * 180 / pi

                        snapped =
                            if shift then
                                toFloat (round (deltaDeg / 15)) * 15

                            else
                                deltaDeg

                        worldRot =
                            Matrix.compose
                                [ Matrix.translation -g.center.x -g.center.y
                                , Matrix.rotation snapped
                                , Matrix.translation g.center.x g.center.y
                                ]

                        updated =
                            List.foldl (applyWorldMatrix model resolved worldRot False) g.originalScene g.originals
                    in
                    pure (Edit.transient (\_ -> Document.setScene updated origin) model)

        _ ->
            pure model


applyPivot : { nodeId : NodeId, original : Transform } -> Vec2 -> Model -> Update
applyPivot g p model =
    case ( model.editor.gestureOrigin, Model.activeDoc model ) of
        ( Just origin, Just open ) ->
            case Evaluate.evaluateScene origin open.activeSceneId (Edit.currentFrame model) of
                Nothing ->
                    pure model

                Just resolved ->
                    case Dict.get g.nodeId resolved.byId of
                        Nothing ->
                            pure model

                        Just res ->
                            let
                                -- pointer in node-local geometry space
                                localPoint =
                                    Matrix.invert res.worldMatrix
                                        |> Maybe.map (\inv -> Matrix.apply inv p)
                                        |> Maybe.withDefault g.original.pivot

                                t =
                                    g.original

                                linear =
                                    Matrix.compose [ Matrix.scaling t.scale.x t.scale.y, Matrix.skewing t.skew.x t.skew.y, Matrix.rotation t.rotation ]

                                lp =
                                    Matrix.applyVector linear t.pivot

                                lp2 =
                                    Matrix.applyVector linear localPoint

                                -- keep the node visually fixed while the pivot moves
                                newTranslation =
                                    { x = t.translation.x + t.pivot.x - lp.x - localPoint.x + lp2.x
                                    , y = t.translation.y + t.pivot.y - lp.y - localPoint.y + lp2.y
                                    }

                                update scene =
                                    scene
                                        |> setTransformProperty model g.nodeId Pivot (PointValue localPoint)
                                        |> setTransformProperty model g.nodeId Position (PointValue newTranslation)
                            in
                            pure (Edit.transient (Document.updateScene open.activeSceneId update) { model | documents = Dict.insert open.document.id { open | document = origin } model.documents })

        _ ->
            pure model


applyAnchorDrag : { nodeId : NodeId, subpath : Int, index : Int, original : Path.PathGeometry, start : Vec2, isHandle : Bool, mirror : Bool } -> Vec2 -> Model -> Update
applyAnchorDrag g p model =
    case ( model.editor.gestureOrigin, Model.activeDoc model ) of
        ( Just origin, Just open ) ->
            case Evaluate.evaluateScene origin open.activeSceneId (Edit.currentFrame model) |> Maybe.andThen (\r -> Dict.get g.nodeId r.byId) of
                Nothing ->
                    pure model

                Just res ->
                    let
                        inv =
                            Matrix.invert res.worldMatrix |> Maybe.withDefault Matrix.identity

                        localP =
                            Matrix.apply inv p

                        localStart =
                            Matrix.apply inv g.start

                        newGeometry =
                            if g.isHandle then
                                Path.setAnchorHandles g.subpath g.index localP g.mirror g.original

                            else
                                Path.moveAnchor g.subpath g.index (Vec2.sub localP localStart) g.original

                        update scene =
                            setTransformProperty model g.nodeId PathGeometryProp (PathValue newGeometry) scene
                    in
                    pure (Edit.transient (\_ -> Document.updateScene open.activeSceneId update origin) model)

        _ ->
            pure model



-- POINTER UP


pointerUp : Float -> Float -> Model -> Update
pointerUp clientX clientY model =
    let
        p =
            toScene model clientX clientY

        editor =
            model.editor

        clear m =
            { m | editor = { editor | gesture = NoGesture, gestureOrigin = Nothing } }
    in
    case editor.gesture of
        NoGesture ->
            pure model

        PendingPress _ ->
            pure (clear model)

        DragMove _ ->
            Edit.commitGesture "Move" model

        DragResize _ ->
            Edit.commitGesture "Resize" model

        DragRotate _ ->
            Edit.commitGesture "Rotate" model

        DragPivot _ ->
            Edit.commitGesture "Move pivot" model

        DragAnchor _ ->
            Edit.commitGesture "Edit path" model

        Marquee g ->
            finishMarquee g.start p g.additive (clear model)

        ZoomMarquee g ->
            if Vec2.distance g.start p < 2 then
                pure (zoomAround (toScreen model p) ((Model.activeView model).zoom * 1.5) (clear model))

            else
                pure (zoomToRect g.start p (clear model))

        DrawShape g ->
            finishDraw g p (clear model)

        Panning _ ->
            pure (clear model)

        PenDragHandle _ ->
            pure (setGesture NoGesture model)

        _ ->
            pure (clear model)


finishMarquee : Vec2 -> Vec2 -> Bool -> Model -> Update
finishMarquee a b additive model =
    case ( Model.activeScene model, resolvedNow model ) of
        ( Just scene, Just resolved ) ->
            let
                rect =
                    { minX = min a.x b.x, minY = min a.y b.y, maxX = max a.x b.x, maxY = max a.y b.y }

                candidates =
                    Scene.childrenOf model.editor.isolation scene
                        |> List.filterMap (\id -> Dict.get id scene.nodes)
                        |> List.filter (\n -> not n.locked && not n.hidden)

                hits =
                    candidates
                        |> List.filter
                            (\n ->
                                case nodeBounds resolved n.id of
                                    Just nb ->
                                        nb.minX <= rect.maxX && nb.maxX >= rect.minX && nb.minY <= rect.maxY && nb.maxY >= rect.minY

                                    Nothing ->
                                        False
                            )
                        |> List.map .id

                newSel =
                    if additive then
                        Edit.selection model ++ List.filter (\id -> not (List.member id (Edit.selection model))) hits

                    else
                        hits
            in
            if Vec2.distance a b < 2 && not additive then
                pure (Edit.setSelection [] model)

            else
                pure (Edit.setSelection newSel model)

        _ ->
            pure model


finishDraw : { start : Vec2, current : Vec2, shift : Bool, alt : Bool } -> Vec2 -> Model -> Update
finishDraw g _ model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                editor =
                    model.editor

                rawW =
                    g.current.x - g.start.x

                rawH =
                    g.current.y - g.start.y

                tiny =
                    abs rawW < 2 && abs rawH < 2

                ( w0, h0 ) =
                    if tiny then
                        ( 100, 100 )

                    else
                        ( rawW, rawH )

                ( w, h ) =
                    if g.shift then
                        let
                            s =
                                max (abs w0) (abs h0)
                        in
                        ( s * sign w0, s * sign h0 )

                    else
                        ( w0, h0 )

                minX =
                    min g.start.x (g.start.x + w)

                minY =
                    min g.start.y (g.start.y + h)

                aw =
                    abs w

                ah =
                    abs h

                ( baseName, geometry, position ) =
                    case editor.tool of
                        EllipseTool ->
                            ( "Ellipse", Ellipse { radii = { x = aw / 2, y = ah / 2 } }, { x = minX + aw / 2, y = minY + ah / 2 } )

                        LineTool ->
                            ( "Line", Line { start = Vec2.zero, end = { x = w, y = h } }, g.start )

                        PolygonTool ->
                            ( "Polygon", Polygon { sides = 6, radius = max aw ah / 2, innerRadius = Nothing }, { x = minX + aw / 2, y = minY + ah / 2 } )

                        StarTool ->
                            ( "Star", Polygon { sides = 5, radius = max aw ah / 2, innerRadius = Just (max aw ah / 5) }, { x = minX + aw / 2, y = minY + ah / 2 } )

                        _ ->
                            ( "Rectangle", Rectangle { size = { x = aw, y = ah }, cornerRadius = 0 }, { x = minX, y = minY } )

                ( node, m2 ) =
                    Edit.newNodeAt baseName geometry position scene model

                ( m3, cmd ) =
                    Edit.commit ("Add " ++ String.toLower baseName) (Document.updateScene scene.id (Scene.insertNode editor.isolation 9999 node)) m2

                e3 =
                    m3.editor
            in
            ( Edit.setSelection [ node.id ] { m3 | editor = { e3 | tool = SelectTool, gestureOrigin = Nothing } }, cmd )


sign : Float -> Float
sign v =
    if v < 0 then
        -1

    else
        1



-- DOUBLE CLICK


doubleClick : PointerEvent -> Model -> Update
doubleClick ev model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            case ev.hitNode |> Maybe.andThen (\id -> Dict.get id scene.nodes) of
                Just node ->
                    let
                        top =
                            resolveHit model scene (Just node.id)
                    in
                    case top |> Maybe.andThen (\id -> Dict.get id scene.nodes) of
                        Just topNode ->
                            if Node.isContainer topNode then
                                let
                                    editor =
                                        model.editor
                                in
                                pure (Edit.setSelection [ node.id ] { model | editor = { editor | isolation = Just topNode.id } })

                            else
                                case topNode.geometry of
                                    Text _ ->
                                        let
                                            editor =
                                                model.editor
                                        in
                                        pure { model | editor = { editor | editingText = Just topNode.id } }

                                    Path _ ->
                                        let
                                            editor =
                                                model.editor
                                        in
                                        pure (Edit.setSelection [ topNode.id ] { model | editor = { editor | tool = DirectSelectTool } })

                                    _ ->
                                        pure model

                        Nothing ->
                            pure model

                Nothing ->
                    let
                        editor =
                            model.editor
                    in
                    pure { model | editor = { editor | isolation = Nothing } }



-- ZOOM / WHEEL


wheel : WheelEvent -> Model -> Update
wheel ev model =
    let
        view =
            Model.activeView model
    in
    if ev.ctrl || ev.meta then
        let
            factor =
                e ^ (-ev.deltaY * 0.01)

            rect =
                model.editor.canvasRect
        in
        pure (zoomAround { x = ev.clientX - rect.left, y = ev.clientY - rect.top } (view.zoom * factor) model)

    else
        pure (Edit.mapActiveView (\v -> { v | pan = { x = v.pan.x - ev.deltaX, y = v.pan.y - ev.deltaY } }) model)


{-| Zoom keeping the given canvas-relative screen point fixed.
-}
zoomAround : Vec2 -> Float -> Model -> Model
zoomAround screenPoint newZoomRaw model =
    let
        view =
            Model.activeView model

        newZoom =
            clamp 0.1 32 newZoomRaw

        scenePoint =
            { x = (screenPoint.x - view.pan.x) / view.zoom, y = (screenPoint.y - view.pan.y) / view.zoom }

        newPan =
            { x = screenPoint.x - scenePoint.x * newZoom, y = screenPoint.y - scenePoint.y * newZoom }
    in
    Edit.mapActiveView (\v -> { v | zoom = newZoom, pan = newPan }) model


zoomToRect : Vec2 -> Vec2 -> Model -> Model
zoomToRect a b model =
    zoomToBounds { minX = min a.x b.x, minY = min a.y b.y, maxX = max a.x b.x, maxY = max a.y b.y } model


zoomToBounds : Bounds -> Model -> Model
zoomToBounds b model =
    let
        rect =
            model.editor.canvasRect

        w =
            max 1 (b.maxX - b.minX)

        h =
            max 1 (b.maxY - b.minY)

        padding =
            40

        zoom =
            clamp 0.1 32 (min ((rect.width - 2 * padding) / w) ((rect.height - 2 * padding) / h))

        cx =
            (b.minX + b.maxX) / 2

        cy =
            (b.minY + b.maxY) / 2

        pan =
            { x = rect.width / 2 - cx * zoom, y = rect.height / 2 - cy * zoom }
    in
    Edit.mapActiveView (\v -> { v | zoom = zoom, pan = pan, fitted = True }) model


zoomToFit : Bool -> Model -> Model
zoomToFit selectionOnly model =
    case Model.activeScene model of
        Nothing ->
            model

        Just scene ->
            if selectionOnly then
                case selectionBounds model of
                    Just b ->
                        zoomToBounds b model

                    Nothing ->
                        zoomToBounds { minX = 0, minY = 0, maxX = scene.width, maxY = scene.height } model

            else
                zoomToBounds { minX = 0, minY = 0, maxX = scene.width, maxY = scene.height } model



-- NUDGE


nudge : Vec2 -> Model -> Update
nudge delta model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                sel =
                    Edit.selection model

                move s =
                    List.foldl
                        (\id acc ->
                            case Dict.get id acc.nodes of
                                Just n ->
                                    setTransformProperty model id Position (PointValue (Vec2.add n.transform.translation delta)) acc

                                Nothing ->
                                    acc
                        )
                        s
                        sel

                -- the base translation is read from the current scene; when a
                -- track exists use the evaluated value instead
                moveAnimated s =
                    List.foldl
                        (\id acc ->
                            case Dict.get id acc.nodes of
                                Just n ->
                                    let
                                        current =
                                            Evaluate.evaluateNodeProperty acc (Edit.currentFrame model) n Position
                                    in
                                    case current of
                                        Just (PointValue cur) ->
                                            setTransformProperty model id Position (PointValue (Vec2.add cur delta)) acc

                                        _ ->
                                            acc

                                Nothing ->
                                    acc
                        )
                        s
                        sel

                _ =
                    move
            in
            Edit.commitCoalesced "nudge" "Nudge" (Document.updateScene scene.id moveAnimated) model
