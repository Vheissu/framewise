module App.Edit exposing
    ( Update
    , applyBaseValue
    , beginGesture
    , cancelGesture
    , commit
    , commitCoalesced
    , commitGesture
    , currentFrame
    , documentJson
    , endPlayback
    , focusAnnounce
    , mapActiveDoc
    , mapActiveScene
    , mapActiveView
    , newNodeAt
    , nextId
    , nextIds
    , pure
    , scheduleAutosave
    , selectedNodes
    , selection
    , setAnimatedProperty
    , setSelection
    , toast
    , transient
    , updateDocument
    )

{-| Core editing primitives shared by all update modules. Every committed
change goes through `commit`, which records history, bumps the revision and
schedules an autosave.
-}

import App.Model exposing (Model, OpenDocument, SceneView, Toast)
import App.Msg exposing (Msg(..))
import App.Ports as Ports
import Dict
import DocumentIO.Encode as Encode
import Domain.Document as Document exposing (Document)
import Domain.Easing
import Domain.History as History
import Domain.Keyframe as Keyframe exposing (Track)
import Domain.Node as Node exposing (Node, NodeGeometry(..))
import Domain.Paint as Paint
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Domain.Transform
import Domain.Validation as Validation
import Domain.Vec2 exposing (Vec2)
import Json.Encode as E
import Process
import Shared.Ids exposing (DocumentId, NodeId)
import Task


type alias Update =
    ( Model, Cmd Msg )


pure : Model -> Update
pure model =
    ( model, Cmd.none )



-- IDS


nextId : Model -> ( String, Model )
nextId model =
    case model.ids of
        id :: rest ->
            ( id, { model | ids = rest } )

        [] ->
            ( "local-" ++ String.fromInt model.idCounter
            , { model | idCounter = model.idCounter + 1 }
            )


nextIds : Int -> Model -> ( List String, Model )
nextIds n model =
    List.foldl
        (\_ ( acc, m ) ->
            let
                ( id, m2 ) =
                    nextId m
            in
            ( acc ++ [ id ], m2 )
        )
        ( [], model )
        (List.range 1 n)



-- ACTIVE DOCUMENT HELPERS


mapActiveDoc : (OpenDocument -> OpenDocument) -> Model -> Model
mapActiveDoc f model =
    case model.activeDocument of
        Just id ->
            { model | documents = Dict.update id (Maybe.map f) model.documents }

        Nothing ->
            model


mapActiveScene : (Scene -> Scene) -> Document -> Scene -> Document
mapActiveScene f doc scene =
    Document.updateScene scene.id f doc


mapActiveView : (SceneView -> SceneView) -> Model -> Model
mapActiveView f model =
    mapActiveDoc
        (\d ->
            { d
                | sceneViews =
                    Dict.update d.activeSceneId
                        (\mv -> Just (f (Maybe.withDefault App.Model.defaultSceneView mv)))
                        d.sceneViews
            }
        )
        model


selection : Model -> List NodeId
selection model =
    (App.Model.activeView model).selection


selectedNodes : Model -> List Node
selectedNodes model =
    case App.Model.activeScene model of
        Just scene ->
            List.filterMap (\id -> Dict.get id scene.nodes) (selection model)

        Nothing ->
            []


setSelection : List NodeId -> Model -> Model
setSelection ids model =
    let
        editor =
            model.editor
    in
    { model | editor = { editor | selectedKeys = [], renamingNode = Nothing } }
        |> mapActiveView (\v -> { v | selection = ids })


currentFrame : Model -> Float
currentFrame model =
    (App.Model.activeView model).playhead



-- COMMITS


{-| Apply a document transformation to the active document as one undoable
step.
-}
commit : String -> (Document -> Document) -> Model -> Update
commit description f model =
    case App.Model.activeDoc model of
        Nothing ->
            pure model

        Just open ->
            let
                newDoc =
                    f open.document
            in
            if newDoc == open.document then
                pure model

            else
                finishCommit (History.commit description open.document open.history) newDoc model


{-| Like `commit`, but consecutive commits sharing `key` merge into one undo
step (typing, nudging, slider drags).
-}
commitCoalesced : String -> String -> (Document -> Document) -> Model -> Update
commitCoalesced key description f model =
    case App.Model.activeDoc model of
        Nothing ->
            pure model

        Just open ->
            let
                newDoc =
                    f open.document
            in
            if newDoc == open.document then
                pure model

            else
                finishCommit (History.commitCoalesced key description open.document open.history) newDoc model


finishCommit : History.History Document -> Document -> Model -> Update
finishCommit history newDoc model =
    let
        updated =
            mapActiveDoc
                (\d ->
                    { d
                        | document = newDoc
                        , revision = d.revision + 1
                        , history = history
                        , validation = Validation.validateDocument newDoc
                    }
                )
                model
    in
    case App.Model.activeDoc updated of
        Just d ->
            ( updated, Cmd.batch [ scheduleAutosave d.document.id d.revision model, dirtyGuard updated ] )

        Nothing ->
            pure updated


{-| Replace the active document wholesale (used by undo/redo).
-}
updateDocument : Document -> History.History Document -> Model -> Update
updateDocument doc history model =
    finishCommit history doc model


{-| Apply a change without recording history, for live drag previews.
-}
transient : (Document -> Document) -> Model -> Model
transient f model =
    mapActiveDoc (\d -> { d | document = f d.document }) model


beginGesture : Model -> Model
beginGesture model =
    let
        editor =
            model.editor
    in
    { model | editor = { editor | gestureOrigin = App.Model.activeDoc model |> Maybe.map .document } }


{-| Finish a gesture: record the document as it was when the gesture began
as the undo point.
-}
commitGesture : String -> Model -> Update
commitGesture description model =
    let
        editor =
            model.editor
    in
    case ( editor.gestureOrigin, App.Model.activeDoc model ) of
        ( Just origin, Just open ) ->
            let
                cleared =
                    { model | editor = { editor | gestureOrigin = Nothing, gesture = App.Model.NoGesture } }
            in
            if origin == open.document then
                pure cleared

            else
                finishCommit (History.commit description origin open.history) open.document cleared

        _ ->
            pure { model | editor = { editor | gestureOrigin = Nothing, gesture = App.Model.NoGesture } }


cancelGesture : Model -> Model
cancelGesture model =
    let
        editor =
            model.editor

        restored =
            case editor.gestureOrigin of
                Just origin ->
                    mapActiveDoc (\d -> { d | document = origin }) model

                Nothing ->
                    model
    in
    { restored | editor = { editor | gestureOrigin = Nothing, gesture = App.Model.NoGesture } }



-- AUTOSAVE


scheduleAutosave : DocumentId -> Int -> Model -> Cmd Msg
scheduleAutosave docId revision model =
    Process.sleep (toFloat model.preferences.autosaveIdleMs)
        |> Task.perform (\_ -> AutosaveTick docId revision)


dirtyGuard : Model -> Cmd Msg
dirtyGuard model =
    let
        anyDirty =
            Dict.values model.documents
                |> List.any (\d -> Just d.revision /= d.savedRevision && d.revision /= 0)
    in
    Ports.send (Ports.request "guard" "session.dirty" (E.object [ ( "dirty", E.bool anyDirty ) ]))


documentJson : Document -> E.Value
documentJson =
    Encode.document



-- PROPERTY EDITS


{-| Set a node property respecting the animation model:

  - no track: set the base value (or, with auto-key at a non-zero frame,
    create a track with a frame-0 baseline plus a key at the playhead)
  - track with keys: with auto-key or an existing key at the playhead, write
    the key at the playhead; otherwise follow the configured off-key policy
    (edit nearest key, or add a key).

-}
setAnimatedProperty : Model -> NodeId -> PropertyPath -> PropertyValue -> Scene -> ( Scene, Model )
setAnimatedProperty model nodeId property value scene =
    case Dict.get nodeId scene.nodes of
        Nothing ->
            ( scene, model )

        Just node ->
            let
                frame =
                    round (currentFrame model)

                existing =
                    Scene.trackFor nodeId property scene
            in
            case existing of
                Just track ->
                    if List.isEmpty track.keyframes then
                        ( Scene.setNode (applyBaseValue property value node) scene, model )

                    else if model.editor.autoKey || Keyframe.keyAt frame track /= Nothing then
                        writeKey model frame value track scene

                    else if model.preferences.offKeyPolicy == "add" then
                        writeKey model frame value track scene

                    else
                        -- nearest key
                        let
                            nearest =
                                track.keyframes
                                    |> List.sortBy (\k -> abs (k.frame - frame))
                                    |> List.head
                        in
                        case nearest of
                            Just k ->
                                ( Scene.upsertTrack (Keyframe.setValue k.id value track) scene, model )

                            Nothing ->
                                writeKey model frame value track scene

                Nothing ->
                    if model.editor.autoKey && frame /= 0 && Node.supportsProperty node property then
                        let
                            ( ids, m2 ) =
                                nextIds 3 model

                            baseline =
                                baseValueOf node property

                            trackId =
                                List.head ids |> Maybe.withDefault "t"

                            k0Id =
                                List.drop 1 ids |> List.head |> Maybe.withDefault "k0"

                            k1Id =
                                List.drop 2 ids |> List.head |> Maybe.withDefault "k1"

                            track =
                                Keyframe.newTrack trackId nodeId property

                            withBaseline =
                                case baseline of
                                    Just b ->
                                        Keyframe.insert { id = k0Id, frame = 0, value = b, easing = Domain.Easing.Preset Domain.Easing.EaseInOut } track

                                    Nothing ->
                                        track

                            withKey =
                                Keyframe.insert { id = k1Id, frame = frame, value = value, easing = Domain.Easing.Preset Domain.Easing.EaseInOut } withBaseline
                        in
                        ( Scene.upsertTrack withKey scene, m2 )

                    else
                        ( Scene.setNode (applyBaseValue property value node) scene, model )


writeKey : Model -> Int -> PropertyValue -> Track -> Scene -> ( Scene, Model )
writeKey model frame value track scene =
    case Keyframe.keyAt frame track of
        Just k ->
            ( Scene.upsertTrack (Keyframe.setValue k.id value track) scene, model )

        Nothing ->
            let
                ( id, m2 ) =
                    nextId model

                easing =
                    -- inherit the easing of the preceding key for continuity
                    (Keyframe.segmentAt (toFloat frame) track).before
                        |> Maybe.map .easing
                        |> Maybe.withDefault (Domain.Easing.Preset Domain.Easing.EaseInOut)
            in
            ( Scene.upsertTrack (Keyframe.insert { id = id, frame = frame, value = value, easing = easing } track) scene, m2 )


baseValueOf : Node -> PropertyPath -> Maybe PropertyValue
baseValueOf node property =
    case property of
        Position ->
            Just (PointValue node.transform.translation)

        Scale ->
            Just (PointValue node.transform.scale)

        Rotation ->
            Just (Angle node.transform.rotation)

        Skew ->
            Just (PointValue node.transform.skew)

        Pivot ->
            Just (PointValue node.transform.pivot)

        Opacity ->
            Just (Scalar node.opacity)

        Visible ->
            Just (BoolValue (not node.hidden))

        FillColor ->
            Paint.paintColor node.fill |> Maybe.map ColorValue

        StrokeColor ->
            Paint.paintColor node.stroke.paint |> Maybe.map ColorValue

        StrokeWidth ->
            Just (Scalar node.stroke.width)

        DashOffset ->
            Just (Scalar node.stroke.dashOffset)

        RectSize ->
            case node.geometry of
                Rectangle r ->
                    Just (SizeValue r.size)

                _ ->
                    Nothing

        RectCornerRadius ->
            case node.geometry of
                Rectangle r ->
                    Just (Scalar r.cornerRadius)

                _ ->
                    Nothing

        EllipseRadii ->
            case node.geometry of
                Ellipse e ->
                    Just (SizeValue e.radii)

                _ ->
                    Nothing

        PathGeometryProp ->
            case node.geometry of
                Path p ->
                    Just (PathValue p)

                _ ->
                    Nothing

        FontSize ->
            case node.geometry of
                Text t ->
                    Just (Scalar t.fontSize)

                _ ->
                    Nothing

        TextContent ->
            case node.geometry of
                Text t ->
                    Just (StringValue t.content)

                _ ->
                    Nothing

        MotionProgress ->
            Just (Scalar 0)

        BlurRadius ->
            node.effects
                |> List.filterMap
                    (\e ->
                        case e of
                            Node.Blur r ->
                                Just (Scalar r)

                            _ ->
                                Nothing
                    )
                |> List.head


{-| Write a value into the node's base (non-animated) state.
-}
applyBaseValue : PropertyPath -> PropertyValue -> Node -> Node
applyBaseValue property value node =
    let
        t =
            node.transform

        s =
            node.stroke
    in
    case ( property, value ) of
        ( Position, PointValue p ) ->
            { node | transform = { t | translation = p } }

        ( Scale, PointValue p ) ->
            { node | transform = { t | scale = p } }

        ( Rotation, Angle a ) ->
            { node | transform = { t | rotation = a } }

        ( Skew, PointValue p ) ->
            { node | transform = { t | skew = p } }

        ( Pivot, PointValue p ) ->
            { node | transform = { t | pivot = p } }

        ( Opacity, Scalar o ) ->
            { node | opacity = clamp 0 1 o }

        ( Visible, BoolValue v ) ->
            { node | hidden = not v }

        ( FillColor, ColorValue c ) ->
            { node | fill = Paint.setPaintColor c node.fill }

        ( StrokeColor, ColorValue c ) ->
            { node | stroke = { s | paint = Paint.setPaintColor c s.paint } }

        ( StrokeWidth, Scalar w ) ->
            { node | stroke = { s | width = max 0 w } }

        ( DashOffset, Scalar d ) ->
            { node | stroke = { s | dashOffset = d } }

        ( RectSize, SizeValue size ) ->
            case node.geometry of
                Rectangle r ->
                    { node | geometry = Rectangle { r | size = { x = max 0 size.x, y = max 0 size.y } } }

                _ ->
                    node

        ( RectCornerRadius, Scalar c ) ->
            case node.geometry of
                Rectangle r ->
                    { node | geometry = Rectangle { r | cornerRadius = max 0 c } }

                _ ->
                    node

        ( EllipseRadii, SizeValue radii ) ->
            case node.geometry of
                Ellipse e ->
                    { node | geometry = Ellipse { e | radii = { x = max 0 radii.x, y = max 0 radii.y } } }

                _ ->
                    node

        ( PathGeometryProp, PathValue p ) ->
            case node.geometry of
                Path _ ->
                    { node | geometry = Path p }

                _ ->
                    node

        ( FontSize, Scalar f ) ->
            case node.geometry of
                Text tx ->
                    { node | geometry = Text { tx | fontSize = max 0.1 f } }

                _ ->
                    node

        ( TextContent, StringValue str ) ->
            case node.geometry of
                Text tx ->
                    { node | geometry = Text { tx | content = str } }

                _ ->
                    node

        ( BlurRadius, Scalar r ) ->
            { node
                | effects =
                    List.map
                        (\e ->
                            case e of
                                Node.Blur _ ->
                                    Node.Blur (max 0 r)

                                other ->
                                    other
                        )
                        node.effects
            }

        _ ->
            node


{-| Create a node positioned at a scene point, named with a running index.
-}
newNodeAt : String -> NodeGeometry -> Vec2 -> Scene -> Model -> ( Node, Model )
newNodeAt baseName geometry position scene model =
    let
        ( id, m2 ) =
            nextId model

        count =
            Dict.values scene.nodes
                |> List.filter (\n -> String.startsWith baseName n.name)
                |> List.length

        name =
            if count == 0 then
                baseName

            else
                baseName ++ " " ++ String.fromInt (count + 1)

        node =
            Node.new id name geometry
    in
    ( { node | transform = Domain.Transform.translated position }, m2 )



-- UI FEEDBACK


toast : String -> String -> Model -> Model
toast kind message model =
    { model
        | toasts = model.toasts ++ [ Toast model.toastSeq message kind ]
        , toastSeq = model.toastSeq + 1
        , liveAnnouncement = message
    }


focusAnnounce : String -> Model -> Model
focusAnnounce message model =
    { model | liveAnnouncement = message }


endPlayback : Model -> Model
endPlayback model =
    let
        editor =
            model.editor

        pb =
            editor.playback
    in
    { model | editor = { editor | playback = { pb | playing = False } } }
