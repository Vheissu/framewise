module Domain.Document exposing
    ( AssetMeta
    , Document
    , Metadata
    , addScene
    , currentSchemaVersion
    , duplicateScene
    , getScene
    , new
    , orderedScenes
    , removeScene
    , reorderScene
    , setScene
    , updateScene
    )

import Dict exposing (Dict)
import Domain.Scene as Scene exposing (Scene)
import Shared.Ids exposing (AssetId, DocumentId, SceneId)


currentSchemaVersion : Int
currentSchemaVersion =
    1


type alias Metadata =
    { name : String
    , description : String
    , createdAt : String
    , modifiedAt : String
    }


type alias AssetMeta =
    { id : AssetId
    , name : String
    , mimeType : String
    , byteLength : Int
    , sha256 : String
    , width : Int
    , height : Int
    }


type alias Document =
    { id : DocumentId
    , schemaVersion : Int
    , metadata : Metadata
    , sceneOrder : List SceneId
    , scenes : Dict SceneId Scene
    , assets : Dict AssetId AssetMeta
    }


new : DocumentId -> String -> String -> Scene -> Document
new id name createdAt scene =
    { id = id
    , schemaVersion = currentSchemaVersion
    , metadata = { name = name, description = "", createdAt = createdAt, modifiedAt = createdAt }
    , sceneOrder = [ scene.id ]
    , scenes = Dict.singleton scene.id scene
    , assets = Dict.empty
    }


getScene : SceneId -> Document -> Maybe Scene
getScene id doc =
    Dict.get id doc.scenes


setScene : Scene -> Document -> Document
setScene scene doc =
    { doc | scenes = Dict.insert scene.id scene doc.scenes }


updateScene : SceneId -> (Scene -> Scene) -> Document -> Document
updateScene id f doc =
    case Dict.get id doc.scenes of
        Just s ->
            setScene (f s) doc

        Nothing ->
            doc


orderedScenes : Document -> List Scene
orderedScenes doc =
    List.filterMap (\id -> Dict.get id doc.scenes) doc.sceneOrder


addScene : Scene -> Document -> Document
addScene scene doc =
    { doc
        | scenes = Dict.insert scene.id scene doc.scenes
        , sceneOrder = doc.sceneOrder ++ [ scene.id ]
    }


removeScene : SceneId -> Document -> Document
removeScene id doc =
    if List.length doc.sceneOrder <= 1 then
        doc

    else
        { doc
            | scenes = Dict.remove id doc.scenes
            , sceneOrder = List.filter ((/=) id) doc.sceneOrder
        }


reorderScene : SceneId -> Int -> Document -> Document
reorderScene id delta doc =
    let
        order =
            doc.sceneOrder

        idx =
            List.indexedMap Tuple.pair order
                |> List.filter (\( _, v ) -> v == id)
                |> List.head
                |> Maybe.map Tuple.first
                |> Maybe.withDefault -1

        target =
            clamp 0 (List.length order - 1) (idx + delta)
    in
    if idx < 0 || target == idx then
        doc

    else
        let
            without =
                List.filter ((/=) id) order
        in
        { doc | sceneOrder = List.take target without ++ [ id ] ++ List.drop target without }


{-| Duplicate a scene with fresh ids. `idFor` maps an old id to a new one and
is supplied by the caller (ids come from the platform bridge).
-}
duplicateScene : SceneId -> SceneId -> (String -> String) -> Document -> Document
duplicateScene sourceId newId idFor doc =
    case Dict.get sourceId doc.scenes of
        Nothing ->
            doc

        Just scene ->
            let
                remapNode n =
                    { n
                        | id = idFor n.id
                        , parentId = Maybe.map idFor n.parentId
                        , childIds = List.map idFor n.childIds
                        , motion = Maybe.map (\m -> { m | pathId = idFor m.pathId }) n.motion
                    }

                remapTrack t =
                    { t
                        | id = idFor t.id
                        , target = { nodeId = idFor t.target.nodeId, property = t.target.property }
                        , keyframes = List.map (\k -> { k | id = idFor k.id }) t.keyframes
                    }

                remapPath p =
                    { p | id = idFor p.id }

                copy =
                    { scene
                        | id = newId
                        , name = scene.name ++ " copy"
                        , rootNodeIds = List.map idFor scene.rootNodeIds
                        , nodes = Dict.fromList (List.map (\n -> ( idFor n.id, remapNode n )) (Dict.values scene.nodes))
                        , tracks = Dict.fromList (List.map (\t -> ( idFor t.id, remapTrack t )) (Dict.values scene.tracks))
                        , motionPaths = Dict.fromList (List.map (\p -> ( idFor p.id, remapPath p )) (Dict.values scene.motionPaths))
                    }
            in
            addScene copy doc
