module Domain.Scene exposing
    ( Background(..)
    , Guide
    , Marker
    , MotionPath
    , PlaybackMode(..)
    , Scene
    , WorkRange
    , ancestors
    , childrenOf
    , deleteNodes
    , descendants
    , flattenOrder
    , getNode
    , insertNode
    , isAncestorOf
    , moveNode
    , new
    , orderedTopLevel
    , playbackModeFromCode
    , playbackModeToCode
    , removeTracksFor
    , reorderWithinParent
    , setNode
    , siblingsOf
    , trackFor
    , tracksFor
    , updateNode
    , upsertTrack
    )

{-| A scene is an independent composition: a tree of nodes, animation tracks
and motion paths. The tree is stored once canonically as `rootNodeIds` plus
`childIds`; `parentId` is kept reciprocal by the operations in this module.
-}

import Dict exposing (Dict)
import Domain.Color exposing (Rgba)
import Domain.Fps exposing (Fps)
import Domain.Keyframe as Keyframe exposing (Track)
import Domain.Node exposing (Node)
import Domain.Path exposing (PathGeometry)
import Domain.Property exposing (PropertyPath)
import Shared.Ids exposing (MotionPathId, NodeId, SceneId, TrackId)


type Background
    = Transparent
    | SolidBackground Rgba


type PlaybackMode
    = PlayOnce
    | Repeat
    | PingPong


type alias Marker =
    { frame : Int, label : String }


type alias WorkRange =
    { start : Int, end : Int }


type alias Guide =
    { horizontal : Bool, position : Float }


type alias MotionPath =
    { id : MotionPathId
    , name : String
    , geometry : PathGeometry
    , revision : Int
    }


type alias Scene =
    { id : SceneId
    , name : String
    , width : Float
    , height : Float
    , background : Background
    , fps : Fps
    , durationFrames : Int
    , playbackMode : PlaybackMode
    , markers : List Marker
    , workRange : Maybe WorkRange
    , rootNodeIds : List NodeId
    , nodes : Dict NodeId Node
    , tracks : Dict TrackId Track
    , motionPaths : Dict MotionPathId MotionPath
    , guides : List Guide
    , description : String
    }


new : SceneId -> String -> Float -> Float -> Fps -> Int -> Background -> Scene
new id name width height fps durationFrames background =
    { id = id
    , name = name
    , width = width
    , height = height
    , background = background
    , fps = fps
    , durationFrames = durationFrames
    , playbackMode = Repeat
    , markers = []
    , workRange = Nothing
    , rootNodeIds = []
    , nodes = Dict.empty
    , tracks = Dict.empty
    , motionPaths = Dict.empty
    , guides = []
    , description = ""
    }


playbackModeToCode : PlaybackMode -> String
playbackModeToCode m =
    case m of
        PlayOnce ->
            "once"

        Repeat ->
            "repeat"

        PingPong ->
            "pingpong"


playbackModeFromCode : String -> Maybe PlaybackMode
playbackModeFromCode s =
    case s of
        "once" ->
            Just PlayOnce

        "repeat" ->
            Just Repeat

        "pingpong" ->
            Just PingPong

        _ ->
            Nothing



-- NODE TREE


getNode : NodeId -> Scene -> Maybe Node
getNode id scene =
    Dict.get id scene.nodes


setNode : Node -> Scene -> Scene
setNode node scene =
    { scene | nodes = Dict.insert node.id node scene.nodes }


updateNode : NodeId -> (Node -> Node) -> Scene -> Scene
updateNode id f scene =
    case Dict.get id scene.nodes of
        Just n ->
            setNode (f n) scene

        Nothing ->
            scene


childrenOf : Maybe NodeId -> Scene -> List NodeId
childrenOf parent scene =
    case parent of
        Nothing ->
            scene.rootNodeIds

        Just pid ->
            Dict.get pid scene.nodes |> Maybe.map .childIds |> Maybe.withDefault []


siblingsOf : NodeId -> Scene -> List NodeId
siblingsOf id scene =
    case Dict.get id scene.nodes of
        Just n ->
            childrenOf n.parentId scene

        Nothing ->
            []


orderedTopLevel : Scene -> List Node
orderedTopLevel scene =
    List.filterMap (\id -> Dict.get id scene.nodes) scene.rootNodeIds


{-| Depth-first paint order of all node ids.
-}
flattenOrder : Scene -> List NodeId
flattenOrder scene =
    List.concatMap (flattenFrom scene) scene.rootNodeIds


flattenFrom : Scene -> NodeId -> List NodeId
flattenFrom scene id =
    case Dict.get id scene.nodes of
        Just n ->
            id :: List.concatMap (flattenFrom scene) n.childIds

        Nothing ->
            []


descendants : NodeId -> Scene -> List NodeId
descendants id scene =
    case Dict.get id scene.nodes of
        Just n ->
            List.concatMap (flattenFrom scene) n.childIds

        Nothing ->
            []


ancestors : NodeId -> Scene -> List NodeId
ancestors id scene =
    case Dict.get id scene.nodes |> Maybe.andThen .parentId of
        Just pid ->
            pid :: ancestors pid scene

        Nothing ->
            []


isAncestorOf : NodeId -> NodeId -> Scene -> Bool
isAncestorOf maybeAncestor id scene =
    List.member maybeAncestor (ancestors id scene)


{-| Insert a node under a parent at an index (clamped). Index 0 is the back
of the paint order (first painted).
-}
insertNode : Maybe NodeId -> Int -> Node -> Scene -> Scene
insertNode parent index node scene =
    let
        placed =
            { node | parentId = parent }

        withNode =
            { scene | nodes = Dict.insert node.id placed scene.nodes }
    in
    case parent of
        Nothing ->
            { withNode | rootNodeIds = insertAt index node.id (List.filter ((/=) node.id) withNode.rootNodeIds) }

        Just pid ->
            updateNode pid
                (\p -> { p | childIds = insertAt index node.id (List.filter ((/=) node.id) p.childIds) })
                withNode


insertAt : Int -> a -> List a -> List a
insertAt index item list =
    let
        i =
            clamp 0 (List.length list) index
    in
    List.take i list ++ [ item ] ++ List.drop i list


detach : NodeId -> Scene -> Scene
detach id scene =
    case Dict.get id scene.nodes of
        Nothing ->
            scene

        Just n ->
            case n.parentId of
                Nothing ->
                    { scene | rootNodeIds = List.filter ((/=) id) scene.rootNodeIds }

                Just pid ->
                    updateNode pid (\p -> { p | childIds = List.filter ((/=) id) p.childIds }) scene


{-| Delete nodes with their descendants, tracks and motion attachments.
-}
deleteNodes : List NodeId -> Scene -> Scene
deleteNodes ids scene =
    let
        all =
            List.concatMap (\id -> id :: descendants id scene) ids
                |> dedupe

        detached =
            List.foldl detach scene ids

        withoutTracks =
            List.foldl removeTracksFor detached all
    in
    { withoutTracks | nodes = List.foldl Dict.remove withoutTracks.nodes all }


dedupe : List comparable -> List comparable
dedupe =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []


{-| Move a node to a new parent and index. Rejects cycles (moving into own
descendant) by returning the scene unchanged.
-}
moveNode : NodeId -> Maybe NodeId -> Int -> Scene -> Scene
moveNode id newParent index scene =
    let
        invalid =
            newParent
                == Just id
                || (case newParent of
                        Just p ->
                            isAncestorOf id p scene

                        Nothing ->
                            False
                   )
    in
    if invalid then
        scene

    else
        case Dict.get id scene.nodes of
            Nothing ->
                scene

            Just node ->
                let
                    sameParent =
                        node.parentId == newParent

                    currentIndex =
                        indexOf id (childrenOf node.parentId scene)

                    adjustedIndex =
                        if sameParent && currentIndex < index then
                            index - 1

                        else
                            index

                    detached =
                        detach id scene
                in
                insertNode newParent adjustedIndex node detached


indexOf : a -> List a -> Int
indexOf x list =
    List.indexedMap Tuple.pair list
        |> List.filter (\( _, v ) -> v == x)
        |> List.head
        |> Maybe.map Tuple.first
        |> Maybe.withDefault -1


{-| Reorder a node among its siblings by a delta (+1 towards front).
-}
reorderWithinParent : NodeId -> Int -> Scene -> Scene
reorderWithinParent id delta scene =
    case Dict.get id scene.nodes of
        Nothing ->
            scene

        Just node ->
            let
                siblings =
                    childrenOf node.parentId scene

                current =
                    indexOf id siblings

                target =
                    clamp 0 (List.length siblings - 1) (current + delta)
            in
            if current < 0 || target == current then
                scene

            else
                let
                    without =
                        List.filter ((/=) id) siblings

                    reordered =
                        insertAt target id without
                in
                case node.parentId of
                    Nothing ->
                        { scene | rootNodeIds = reordered }

                    Just pid ->
                        updateNode pid (\p -> { p | childIds = reordered }) scene



-- TRACKS


tracksFor : NodeId -> Scene -> List Track
tracksFor nodeId scene =
    Dict.values scene.tracks |> List.filter (\t -> t.target.nodeId == nodeId)


trackFor : NodeId -> PropertyPath -> Scene -> Maybe Track
trackFor nodeId property scene =
    Dict.values scene.tracks
        |> List.filter (\t -> t.target.nodeId == nodeId && t.target.property == property)
        |> List.head


upsertTrack : Track -> Scene -> Scene
upsertTrack track scene =
    { scene | tracks = Dict.insert track.id track scene.tracks }


removeTracksFor : NodeId -> Scene -> Scene
removeTracksFor nodeId scene =
    { scene | tracks = Dict.filter (\_ t -> t.target.nodeId /= nodeId) scene.tracks }
