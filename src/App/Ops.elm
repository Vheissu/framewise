module App.Ops exposing
    ( alignSelection
    , clipboardPayload
    , convertToPath
    , deleteSelection
    , distributeSelection
    , duplicateSelection
    , flipSelection
    , groupSelection
    , pasteClipboard
    , reorderSelection
    , resetTransform
    , reversePath
    , toggleClosedPath
    , ungroupSelection
    )

{-| Structural node operations on the active scene. Each returns an `Update`
that commits exactly one history entry.
-}

import App.Canvas as Canvas
import App.Edit as Edit exposing (Update, pure)
import App.Model as Model exposing (Model)
import App.Msg exposing (Msg)
import Dict
import DocumentIO.Decode as Decode
import DocumentIO.Encode as Encode
import Domain.Document as Document
import Domain.Evaluate as Evaluate
import Domain.Keyframe as Keyframe
import Domain.Matrix as Matrix
import Domain.Node as Node exposing (Node, NodeGeometry(..))
import Domain.Path as Path
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Domain.Transform as Transform
import Domain.Vec2 as Vec2
import Json.Decode as D
import Json.Encode as E
import Set
import Shared.Ids exposing (NodeId)


{-| Delete the selection, then select the nearest surviving sibling.
-}
deleteSelection : Model -> Update
deleteSelection model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                sel =
                    Edit.selection model

                nextSelection =
                    case sel of
                        first :: _ ->
                            let
                                siblings =
                                    Scene.siblingsOf first scene

                                idx =
                                    indexOf first siblings

                                survivors =
                                    List.filter (\id -> not (List.member id sel)) siblings
                            in
                            case List.drop (max 0 (idx - 1)) survivors |> List.head of
                                Just s ->
                                    [ s ]

                                Nothing ->
                                    case Dict.get first scene.nodes |> Maybe.andThen .parentId of
                                        Just pid ->
                                            if List.member pid sel then
                                                []

                                            else
                                                [ pid ]

                                        Nothing ->
                                            []

                        [] ->
                            []

                editor =
                    model.editor

                clearedIsolation =
                    case editor.isolation of
                        Just iso ->
                            if List.member iso sel || List.any (\id -> Scene.isAncestorOf id iso scene) sel then
                                { model | editor = { editor | isolation = Nothing } }

                            else
                                model

                        Nothing ->
                            model

                ( m2, cmd ) =
                    Edit.commit "Delete" (Document.updateScene scene.id (Scene.deleteNodes sel)) clearedIsolation
            in
            ( Edit.setSelection nextSelection m2, cmd )


indexOf : a -> List a -> Int
indexOf x list =
    List.indexedMap Tuple.pair list
        |> List.filter (\( _, v ) -> v == x)
        |> List.head
        |> Maybe.map Tuple.first
        |> Maybe.withDefault 0


{-| Group (or clip-group) the selection. The new group is placed where the
front-most selected node was; children keep their world positions because the
group starts with an identity transform.
-}
groupSelection : Bool -> Model -> Update
groupSelection clip model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                sel =
                    Edit.selection model
                        |> List.filter (\id -> not (List.any (\other -> other /= id && Scene.isAncestorOf other id scene) (Edit.selection model)))
            in
            case sel of
                [] ->
                    pure model

                first :: _ ->
                    let
                        parent =
                            Dict.get first scene.nodes |> Maybe.andThen .parentId

                        sameParent =
                            List.all (\id -> (Dict.get id scene.nodes |> Maybe.andThen .parentId) == parent) sel
                    in
                    if not sameParent then
                        pure (Edit.toast "warning" "Select objects that share the same parent to group them" model)

                    else
                        let
                            ( gid, m2 ) =
                                Edit.nextId model

                            siblings =
                                Scene.childrenOf parent scene

                            -- paint order of the selection follows the layer order
                            ordered =
                                List.filter (\id -> List.member id sel) siblings

                            insertIndex =
                                ordered |> List.map (\id -> indexOf id siblings) |> List.maximum |> Maybe.withDefault 0

                            count =
                                Dict.values scene.nodes |> List.filter Node.isContainer |> List.length

                            group =
                                Node.new gid
                                    (if clip then
                                        "Clip Group " ++ String.fromInt (count + 1)

                                     else
                                        "Group " ++ String.fromInt (count + 1)
                                    )
                                    (if clip then
                                        ClippingGroup

                                     else
                                        Group
                                    )

                            update s =
                                let
                                    withGroup =
                                        Scene.insertNode parent (insertIndex + 1) group s
                                in
                                List.foldl (\( i, id ) acc -> Scene.moveNode id (Just gid) i acc) withGroup (List.indexedMap Tuple.pair ordered)

                            ( m3, cmd ) =
                                Edit.commit
                                    (if clip then
                                        "Clip to shape"

                                     else
                                        "Group"
                                    )
                                    (Document.updateScene scene.id update)
                                    m2
                        in
                        ( Edit.setSelection [ gid ] m3 |> Edit.mapActiveView (\v -> { v | expanded = Set.insert gid v.expanded }), cmd )


{-| Ungroup selected groups, flattening the group transform into each child so
nothing moves on screen.
-}
ungroupSelection : Model -> Update
ungroupSelection model =
    case ( Model.activeScene model, Canvas.resolvedNow model ) of
        ( Just scene, Just resolved ) ->
            let
                groups =
                    Edit.selection model
                        |> List.filterMap (\id -> Dict.get id scene.nodes)
                        |> List.filter Node.isContainer

                update s =
                    List.foldl (ungroupOne resolved) s groups

                released =
                    List.concatMap .childIds groups

                editor =
                    model.editor

                m1 =
                    if List.any (\g -> Just g.id == editor.isolation) groups then
                        { model | editor = { editor | isolation = Nothing } }

                    else
                        model

                ( m2, cmd ) =
                    Edit.commit "Ungroup" (Document.updateScene scene.id update) m1
            in
            if List.isEmpty groups then
                pure model

            else
                ( Edit.setSelection released m2, cmd )

        _ ->
            pure model


ungroupOne : Evaluate.ResolvedScene -> Node -> Scene -> Scene
ungroupOne resolved group scene =
    let
        siblings =
            Scene.childrenOf group.parentId scene

        baseIndex =
            indexOf group.id siblings

        groupLocal =
            Dict.get group.id resolved.byId |> Maybe.map .localMatrix |> Maybe.withDefault Matrix.identity

        flattenChild childId s =
            case Dict.get childId s.nodes of
                Just child ->
                    let
                        childLocal =
                            Dict.get childId resolved.byId |> Maybe.map .localMatrix |> Maybe.withDefault (Transform.toMatrix child.transform)

                        combined =
                            Matrix.multiply groupLocal childLocal

                        comps =
                            Matrix.decompose child.transform.pivot combined

                        t =
                            child.transform

                        newTransform =
                            { t | translation = comps.translation, scale = comps.scale, rotation = comps.rotation, skew = comps.skew }

                        inheritOpacity =
                            child.opacity * group.opacity
                    in
                    Scene.setNode { child | transform = newTransform, opacity = inheritOpacity } s

                Nothing ->
                    s

        moved =
            List.foldl
                (\( i, childId ) s -> Scene.moveNode childId group.parentId (baseIndex + i) (flattenChild childId s))
                scene
                (List.indexedMap Tuple.pair group.childIds)
    in
    Scene.deleteNodes [ group.id ] moved


{-| Duplicate the selection (with tracks) just above the originals.
-}
duplicateSelection : Model -> Update
duplicateSelection model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                sel =
                    Edit.selection model
                        |> List.filter (\id -> not (List.any (\other -> other /= id && Scene.isAncestorOf other id scene) (Edit.selection model)))

                allIds =
                    List.concatMap (\id -> id :: Scene.descendants id scene) sel

                trackIds =
                    allIds |> List.concatMap (\id -> Scene.tracksFor id scene) |> List.map .id

                keyCount =
                    allIds |> List.concatMap (\id -> Scene.tracksFor id scene) |> List.map (.keyframes >> List.length) |> List.sum

                ( fresh, m2 ) =
                    Edit.nextIds (List.length allIds + List.length trackIds + keyCount) model

                mapping =
                    Dict.fromList (List.map2 Tuple.pair (allIds ++ trackIds) fresh)

                remainingIds =
                    List.drop (List.length allIds + List.length trackIds) fresh

                idFor old =
                    Dict.get old mapping |> Maybe.withDefault old

                ( update, newTop ) =
                    let
                        copyTracks ( s, pool ) =
                            List.foldl
                                (\track ( acc, p ) ->
                                    let
                                        ( keyIds, rest ) =
                                            ( List.take (List.length track.keyframes) p, List.drop (List.length track.keyframes) p )

                                        copied =
                                            { track
                                                | id = idFor track.id
                                                , target = { nodeId = idFor track.target.nodeId, property = track.target.property }
                                                , keyframes = List.map2 (\k kid -> { k | id = kid }) track.keyframes keyIds
                                            }
                                    in
                                    ( Scene.upsertTrack copied acc, rest )
                                )
                                ( s, pool )
                                (allIds |> List.concatMap (\id -> Scene.tracksFor id scene))

                        copyNode id s =
                            case Dict.get id scene.nodes of
                                Just n ->
                                    let
                                        copied =
                                            { n
                                                | id = idFor n.id
                                                , childIds = List.map idFor n.childIds
                                                , parentId =
                                                    if List.member id sel then
                                                        n.parentId

                                                    else
                                                        Maybe.map idFor n.parentId
                                                , name =
                                                    if List.member id sel then
                                                        n.name ++ " copy"

                                                    else
                                                        n.name
                                            }
                                    in
                                    { s | nodes = Dict.insert copied.id copied s.nodes }

                                Nothing ->
                                    s

                        attach id s =
                            case Dict.get id scene.nodes of
                                Just n ->
                                    let
                                        siblings =
                                            Scene.childrenOf n.parentId s

                                        idx =
                                            indexOf id siblings
                                    in
                                    case n.parentId of
                                        Nothing ->
                                            { s | rootNodeIds = insertAt (idx + 1) (idFor id) s.rootNodeIds }

                                        Just pid ->
                                            Scene.updateNode pid (\p -> { p | childIds = insertAt (idx + 1) (idFor id) p.childIds }) s

                                Nothing ->
                                    s

                        doUpdate s =
                            let
                                withNodes =
                                    List.foldl copyNode s allIds

                                attached =
                                    List.foldl attach withNodes sel
                            in
                            Tuple.first (copyTracks ( attached, remainingIds ))
                    in
                    ( doUpdate, List.map idFor sel )

                ( m3, cmd ) =
                    Edit.commit "Duplicate" (Document.updateScene scene.id update) m2
            in
            if List.isEmpty sel then
                pure model

            else
                ( Edit.setSelection newTop m3, cmd )


insertAt : Int -> a -> List a -> List a
insertAt index item list =
    let
        i =
            clamp 0 (List.length list) index
    in
    List.take i list ++ [ item ] ++ List.drop i list


reorderSelection : String -> Model -> Update
reorderSelection how model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                sel =
                    Edit.selection model

                update s =
                    List.foldl
                        (\id acc ->
                            case how of
                                "up" ->
                                    Scene.reorderWithinParent id 1 acc

                                "down" ->
                                    Scene.reorderWithinParent id -1 acc

                                "front" ->
                                    Scene.reorderWithinParent id 100000 acc

                                _ ->
                                    Scene.reorderWithinParent id -100000 acc
                        )
                        s
                        (if how == "up" || how == "front" then
                            List.reverse (orderBySiblings scene sel)

                         else
                            orderBySiblings scene sel
                        )
            in
            Edit.commit "Reorder" (Document.updateScene scene.id update) model


orderBySiblings : Scene -> List NodeId -> List NodeId
orderBySiblings scene ids =
    Scene.flattenOrder scene |> List.filter (\id -> List.member id ids)


convertToPath : Model -> Update
convertToPath model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                update s =
                    List.foldl
                        (\id acc ->
                            Scene.updateNode id
                                (\n ->
                                    case ( n.geometry, Node.toPathGeometry n.geometry ) of
                                        ( Path _, _ ) ->
                                            n

                                        ( _, Just p ) ->
                                            { n | geometry = Path p }

                                        _ ->
                                            n
                                )
                                acc
                                -- geometry tracks no longer apply to a path
                                |> (\sc -> { sc | tracks = Dict.filter (\_ t -> not (t.target.nodeId == id && List.member t.target.property [ RectSize, RectCornerRadius, EllipseRadii ])) sc.tracks })
                        )
                        s
                        (Edit.selection model)
            in
            Edit.commit "Convert to path" (Document.updateScene scene.id update) model


toggleClosedPath : Model -> Update
toggleClosedPath model =
    pathOp "Toggle closed" Path.toggleClosed model


reversePath : Model -> Update
reversePath model =
    pathOp "Reverse path" reverseGeometry model


reverseGeometry : Path.PathGeometry -> Path.PathGeometry
reverseGeometry g =
    { subpaths =
        List.map
            (\s ->
                let
                    pts =
                        s.start :: List.map segEnd s.segments

                    newStart =
                        List.reverse pts |> List.head |> Maybe.withDefault s.start

                    -- walk segments backwards, swapping control points
                    reversedSegments =
                        List.reverse (List.map2 Tuple.pair pts s.segments)
                            |> List.map
                                (\( from, seg ) ->
                                    case seg of
                                        Path.LineTo _ ->
                                            Path.LineTo from

                                        Path.CubicTo c1 c2 _ ->
                                            Path.CubicTo c2 c1 from
                                )
                in
                { s | start = newStart, segments = reversedSegments }
            )
            g.subpaths
    }


segEnd : Path.Segment -> Vec2.Vec2
segEnd seg =
    case seg of
        Path.LineTo e ->
            e

        Path.CubicTo _ _ e ->
            e


pathOp : String -> (Path.PathGeometry -> Path.PathGeometry) -> Model -> Update
pathOp description f model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                update s =
                    List.foldl
                        (\id acc ->
                            Scene.updateNode id
                                (\n ->
                                    case n.geometry of
                                        Path p ->
                                            { n | geometry = Path (f p) }

                                        _ ->
                                            n
                                )
                                acc
                        )
                        s
                        (Edit.selection model)
            in
            Edit.commit description (Document.updateScene scene.id update) model


flipSelection : Bool -> Model -> Update
flipSelection horizontal model =
    case ( Model.activeScene model, Canvas.resolvedNow model, Canvas.selectionBounds model ) of
        ( Just scene, Just resolved, Just b ) ->
            let
                center =
                    { x = (b.minX + b.maxX) / 2, y = (b.minY + b.maxY) / 2 }

                m =
                    Matrix.compose
                        [ Matrix.translation -center.x -center.y
                        , if horizontal then
                            Matrix.scaling -1 1

                          else
                            Matrix.scaling 1 -1
                        , Matrix.translation center.x center.y
                        ]

                update s =
                    List.foldl
                        (\id acc ->
                            case ( Dict.get id acc.nodes, Dict.get id resolved.byId ) of
                                ( Just node, Just res ) ->
                                    let
                                        parentWorld =
                                            node.parentId |> Maybe.andThen (\pid -> Dict.get pid resolved.byId) |> Maybe.map .worldMatrix |> Maybe.withDefault Matrix.identity

                                        parentInv =
                                            Matrix.invert parentWorld |> Maybe.withDefault Matrix.identity

                                        newLocal =
                                            Matrix.compose [ res.localMatrix, parentWorld, m, parentInv ]

                                        comps =
                                            Matrix.decompose node.transform.pivot newLocal

                                        t =
                                            node.transform
                                    in
                                    Scene.setNode { node | transform = { t | translation = comps.translation, scale = comps.scale, rotation = comps.rotation, skew = comps.skew } } acc

                                _ ->
                                    acc
                        )
                        s
                        (Edit.selection model)
            in
            Edit.commit "Flip" (Document.updateScene scene.id update) model

        _ ->
            pure model


resetTransform : Model -> Update
resetTransform model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                update s =
                    List.foldl
                        (\id acc ->
                            Scene.updateNode id
                                (\n ->
                                    let
                                        t =
                                            n.transform
                                    in
                                    { n | transform = { t | scale = { x = 1, y = 1 }, rotation = 0, skew = Vec2.zero } }
                                )
                                acc
                        )
                        s
                        (Edit.selection model)
            in
            Edit.commit "Reset transform" (Document.updateScene scene.id update) model


{-| Align selected nodes to each other, or to the artboard for a single node.
-}
alignSelection : String -> Model -> Update
alignSelection how model =
    case ( Model.activeScene model, Canvas.resolvedNow model ) of
        ( Just scene, Just resolved ) ->
            let
                sel =
                    Edit.selection model

                boundsOf id =
                    Dict.get id resolved.byId |> Maybe.andThen (Evaluate.worldBounds resolved)

                reference =
                    if List.length sel <= 1 then
                        Just { minX = 0, minY = 0, maxX = scene.width, maxY = scene.height }

                    else
                        case List.filterMap boundsOf sel of
                            [] ->
                                Nothing

                            first :: rest ->
                                Just (List.foldl (\b a -> { minX = min a.minX b.minX, minY = min a.minY b.minY, maxX = max a.maxX b.maxX, maxY = max a.maxY b.maxY }) first rest)
            in
            case reference of
                Nothing ->
                    pure model

                Just ref ->
                    let
                        update s =
                            List.foldl
                                (\id acc ->
                                    case ( boundsOf id, Dict.get id acc.nodes ) of
                                        ( Just b, Just node ) ->
                                            let
                                                delta =
                                                    case how of
                                                        "left" ->
                                                            { x = ref.minX - b.minX, y = 0 }

                                                        "centerH" ->
                                                            { x = (ref.minX + ref.maxX) / 2 - (b.minX + b.maxX) / 2, y = 0 }

                                                        "right" ->
                                                            { x = ref.maxX - b.maxX, y = 0 }

                                                        "top" ->
                                                            { x = 0, y = ref.minY - b.minY }

                                                        "centerV" ->
                                                            { x = 0, y = (ref.minY + ref.maxY) / 2 - (b.minY + b.maxY) / 2 }

                                                        _ ->
                                                            { x = 0, y = ref.maxY - b.maxY }
                                            in
                                            moveBy model resolved node delta acc

                                        _ ->
                                            acc
                                )
                                s
                                sel
                    in
                    Edit.commit "Align" (Document.updateScene scene.id update) model

        _ ->
            pure model


moveBy : Model -> Evaluate.ResolvedScene -> Node -> Vec2.Vec2 -> Scene -> Scene
moveBy model resolved node worldDelta scene =
    let
        parentInv =
            node.parentId
                |> Maybe.andThen (\pid -> Dict.get pid resolved.byId)
                |> Maybe.map .worldMatrix
                |> Maybe.andThen Matrix.invert
                |> Maybe.withDefault Matrix.identity

        localDelta =
            Matrix.applyVector parentInv worldDelta

        current =
            Evaluate.evaluateNodeProperty scene (Edit.currentFrame model) node Position
    in
    case current of
        Just (PointValue p) ->
            Tuple.first (Edit.setAnimatedProperty model node.id Position (PointValue (Vec2.add p localDelta)) scene)

        _ ->
            scene


distributeSelection : String -> Model -> Update
distributeSelection axis model =
    case ( Model.activeScene model, Canvas.resolvedNow model ) of
        ( Just scene, Just resolved ) ->
            let
                items =
                    Edit.selection model
                        |> List.filterMap (\id -> Dict.get id resolved.byId |> Maybe.andThen (Evaluate.worldBounds resolved) |> Maybe.map (\b -> ( id, b )))
                        |> List.sortBy
                            (\( _, b ) ->
                                if axis == "h" then
                                    (b.minX + b.maxX) / 2

                                else
                                    (b.minY + b.maxY) / 2
                            )

                n =
                    List.length items
            in
            if n < 3 then
                pure model

            else
                let
                    centers =
                        List.map
                            (\( _, b ) ->
                                if axis == "h" then
                                    (b.minX + b.maxX) / 2

                                else
                                    (b.minY + b.maxY) / 2
                            )
                            items

                    first =
                        List.head centers |> Maybe.withDefault 0

                    last =
                        List.reverse centers |> List.head |> Maybe.withDefault 0

                    stepSize =
                        (last - first) / toFloat (n - 1)

                    update s =
                        List.foldl
                            (\( i, ( id, b ) ) acc ->
                                case Dict.get id acc.nodes of
                                    Just node ->
                                        let
                                            target =
                                                first + stepSize * toFloat i

                                            current =
                                                if axis == "h" then
                                                    (b.minX + b.maxX) / 2

                                                else
                                                    (b.minY + b.maxY) / 2

                                            delta =
                                                if axis == "h" then
                                                    { x = target - current, y = 0 }

                                                else
                                                    { x = 0, y = target - current }
                                        in
                                        moveBy model resolved node delta acc

                                    Nothing ->
                                        acc
                            )
                            s
                            (List.indexedMap Tuple.pair items)
                in
                Edit.commit "Distribute" (Document.updateScene scene.id update) model

        _ ->
            pure model



-- CLIPBOARD


{-| Serialize the selection (subtrees and their tracks) to the internal
clipboard schema.
-}
clipboardPayload : Model -> Maybe E.Value
clipboardPayload model =
    case Model.activeScene model of
        Nothing ->
            Nothing

        Just scene ->
            let
                sel =
                    Edit.selection model
                        |> List.filter (\id -> not (List.any (\other -> other /= id && Scene.isAncestorOf other id scene) (Edit.selection model)))

                allIds =
                    List.concatMap (\id -> id :: Scene.descendants id scene) sel

                nodes =
                    List.filterMap (\id -> Dict.get id scene.nodes) allIds

                tracks =
                    List.concatMap (\id -> Scene.tracksFor id scene) allIds

                motionPaths =
                    nodes |> List.filterMap .motion |> List.filterMap (\m -> Dict.get m.pathId scene.motionPaths)
            in
            if List.isEmpty sel then
                Nothing

            else
                Just
                    (E.object
                        [ ( "format", E.string "framewise-clipboard" )
                        , ( "version", E.int 1 )
                        , ( "roots", E.list E.string sel )
                        , ( "nodes", E.list Encode.node nodes )
                        , ( "tracks", E.list Encode.track tracks )
                        , ( "motionPaths", E.list (\mp -> E.object [ ( "id", E.string mp.id ), ( "name", E.string mp.name ), ( "geometry", Encode.pathGeometry mp.geometry ), ( "revision", E.int mp.revision ) ]) motionPaths )
                        ]
                    )


type alias ClipData =
    { roots : List String
    , nodes : List Node
    , tracks : List Keyframe.Track
    , motionPaths : List Scene.MotionPath
    }


clipDecoder : D.Decoder ClipData
clipDecoder =
    D.map4 ClipData
        (D.field "roots" (D.list D.string))
        (D.field "nodes" (D.list Decode.node))
        (D.oneOf [ D.field "tracks" (D.list Decode.track), D.succeed [] ])
        (D.oneOf
            [ D.field "motionPaths"
                (D.list
                    (D.map4 Scene.MotionPath
                        (D.field "id" D.string)
                        (D.field "name" D.string)
                        (D.field "geometry" Decode.pathGeometryDecoder)
                        (D.oneOf [ D.field "revision" D.int, D.succeed 0 ])
                    )
                )
            , D.succeed []
            ]
        )


{-| Paste clipboard content with remapped ids. `inPlace` keeps coordinates;
otherwise the content is offset slightly so the copy is visible.
-}
pasteClipboard : E.Value -> Bool -> Model -> Update
pasteClipboard value inPlace model =
    case ( Model.activeScene model, D.decodeValue clipDecoder value ) of
        ( Just scene, Ok clip ) ->
            let
                oldIds =
                    List.map .id clip.nodes ++ List.map .id clip.tracks ++ List.concatMap (.keyframes >> List.map .id) clip.tracks ++ List.map .id clip.motionPaths

                ( fresh, m2 ) =
                    Edit.nextIds (List.length oldIds) model

                mapping =
                    Dict.fromList (List.map2 Tuple.pair oldIds fresh)

                idFor old =
                    Dict.get old mapping |> Maybe.withDefault old

                offset =
                    if inPlace then
                        Vec2.zero

                    else
                        { x = 16, y = 16 }

                parent =
                    model.editor.isolation

                remapNode n =
                    let
                        isRoot =
                            List.member n.id clip.roots

                        t =
                            n.transform
                    in
                    { n
                        | id = idFor n.id
                        , childIds = List.map idFor n.childIds
                        , parentId =
                            if isRoot then
                                parent

                            else
                                Maybe.map idFor n.parentId
                        , motion = Maybe.map (\m -> { m | pathId = idFor m.pathId }) n.motion
                        , transform =
                            if isRoot then
                                { t | translation = Vec2.add t.translation offset }

                            else
                                t
                    }

                remapTrack t =
                    { t
                        | id = idFor t.id
                        , target = { nodeId = idFor t.target.nodeId, property = t.target.property }
                        , keyframes =
                            List.map
                                (\k ->
                                    { k
                                        | id = idFor k.id
                                        , value =
                                            case ( k.value, List.member t.target.nodeId clip.roots, t.target.property ) of
                                                ( PointValue p, True, Position ) ->
                                                    PointValue (Vec2.add p offset)

                                                _ ->
                                                    k.value
                                    }
                                )
                                t.keyframes
                    }

                newRoots =
                    List.map idFor clip.roots

                update s =
                    let
                        withNodes =
                            List.foldl (\n acc -> { acc | nodes = Dict.insert n.id (remapNode n) acc.nodes }) s clip.nodes

                        attached =
                            List.foldl
                                (\rid acc ->
                                    case parent of
                                        Nothing ->
                                            { acc | rootNodeIds = acc.rootNodeIds ++ [ rid ] }

                                        Just pid ->
                                            Scene.updateNode pid (\p -> { p | childIds = p.childIds ++ [ rid ] }) acc
                                )
                                withNodes
                                newRoots

                        withTracks =
                            List.foldl (\t acc -> Scene.upsertTrack (remapTrack t) acc) attached clip.tracks
                    in
                    List.foldl (\mp acc -> { acc | motionPaths = Dict.insert (idFor mp.id) { mp | id = idFor mp.id } acc.motionPaths }) withTracks clip.motionPaths

                ( m3, cmd ) =
                    Edit.commit "Paste" (Document.updateScene scene.id update) m2
            in
            ( Edit.setSelection newRoots m3, cmd )

        ( _, Err _ ) ->
            pure (Edit.toast "error" "Clipboard content is not a Framewise selection" model)

        _ ->
            pure model
