module Export.Portable exposing (encode, version)

{-| The versioned portable animation JSON consumed by the Framewise player.
It is a subset of the native document: one scene, its nodes in paint order,
their base values, tracks and motion paths. The player's evaluator and the
Elm evaluator share golden fixtures (see tests/golden).
-}

import Dict
import DocumentIO.Encode as Encode
import Domain.Node exposing (Node)
import Domain.Scene as Scene exposing (Scene)
import Json.Encode as E


version : Int
version =
    1


encode : Scene -> E.Value
encode scene =
    E.object
        [ ( "version", E.int version )
        , ( "scene"
          , E.object
                [ ( "id", E.string scene.id )
                , ( "name", E.string scene.name )
                , ( "width", E.float scene.width )
                , ( "height", E.float scene.height )
                , ( "fps", E.object [ ( "numerator", E.int scene.fps.numerator ), ( "denominator", E.int scene.fps.denominator ) ] )
                , ( "durationFrames", E.int scene.durationFrames )
                , ( "playbackMode", E.string (Scene.playbackModeToCode scene.playbackMode) )
                ]
          )
        , ( "nodes", E.list Encode.node (List.filterMap (\id -> Dict.get id scene.nodes) (Scene.flattenOrder scene)) )
        , ( "tracks", E.list Encode.track (Dict.values scene.tracks) )
        , ( "motionPaths"
          , E.list
                (\mp ->
                    E.object
                        [ ( "id", E.string mp.id )
                        , ( "geometry", Encode.pathGeometry mp.geometry )
                        ]
                )
                (Dict.values scene.motionPaths)
          )
        ]
