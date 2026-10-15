module CodecTest exposing (suite)

import App.Examples as Examples
import Dict
import DocumentIO.Decode as Decode
import DocumentIO.Encode as Encode
import Domain.Node
import Domain.Validation as Validation
import Expect
import Json.Decode as D
import Json.Encode as E
import Test exposing (..)


suite : Test
suite =
    describe "document codec"
        [ test "every bundled example round-trips through encode/decode" <|
            \_ ->
                Expect.all
                    (List.map
                        (\ex _ ->
                            case Examples.build ex.id "doc" "scene" "0" of
                                Just doc ->
                                    case D.decodeValue Decode.document (Encode.document doc) of
                                        Ok decoded ->
                                            Expect.equal doc decoded

                                        Err e ->
                                            Expect.fail (ex.id ++ ": " ++ D.errorToString e)

                                Nothing ->
                                    Expect.fail ("missing example " ++ ex.id)
                        )
                        Examples.all
                    )
                    ()
        , test "every bundled example passes validation" <|
            \_ ->
                Expect.all
                    (List.map
                        (\ex _ ->
                            case Examples.build ex.id "doc" "scene" "0" of
                                Just doc ->
                                    Expect.equal [] (List.filter (\i -> i.severity == Validation.Error) (Validation.validateDocument doc))

                                Nothing ->
                                    Expect.fail "missing example"
                        )
                        Examples.all
                    )
                    ()
        , test "unknown schema versions are rejected" <|
            \_ ->
                let
                    json =
                        E.object [ ( "id", E.string "d" ), ( "schemaVersion", E.int 99 ), ( "metadata", E.object [ ( "name", E.string "x" ) ] ), ( "sceneOrder", E.list E.string [] ), ( "scenes", E.list identity [] ) ]
                in
                Expect.err (D.decodeValue Decode.document json)
        , test "invalid enum codes are rejected" <|
            \_ -> Expect.err (D.decodeValue Decode.easing (E.object [ ( "type", E.string "preset" ), ( "name", E.string "wobble" ) ]))
        , test "non-finite numbers are rejected" <|
            \_ ->
                Expect.err (D.decodeString Decode.propertyValue "{\"type\":\"scalar\",\"value\":1e999}")
        , test "keyframe values must match the track property type" <|
            \_ ->
                let
                    json =
                        E.object
                            [ ( "id", E.string "t" )
                            , ( "target", E.object [ ( "nodeId", E.string "n" ), ( "property", E.string "compositing.opacity" ) ] )
                            , ( "keyframes", E.list identity [ E.object [ ( "id", E.string "k" ), ( "frame", E.int 0 ), ( "value", E.object [ ( "type", E.string "point" ), ( "value", E.object [ ( "x", E.float 0 ), ( "y", E.float 0 ) ] ) ] ) ] ] )
                            ]
                in
                Expect.err (D.decodeValue Decode.track json)
        , test "path-d geometry from the importer is parsed" <|
            \_ ->
                let
                    json =
                        E.object
                            [ ( "id", E.string "n" )
                            , ( "name", E.string "p" )
                            , ( "kind", E.string "path-d" )
                            , ( "geometry", E.object [ ( "d", E.string "M0 0 L10 10" ) ] )
                            , ( "transform", E.object [ ( "translation", E.object [ ( "x", E.float 0 ), ( "y", E.float 0 ) ] ), ( "scale", E.object [ ( "x", E.float 1 ), ( "y", E.float 1 ) ] ), ( "rotation", E.float 0 ) ] )
                            ]
                in
                case D.decodeValue Decode.node json of
                    Ok node ->
                        Expect.equal "path" (Domain.Node.kindCode node.geometry)

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "validation reports duplicate frames and broken parent links" <|
            \_ ->
                case Examples.build "bouncing-ball" "doc" "scene" "0" of
                    Just doc ->
                        let
                            broken =
                                { doc
                                    | scenes =
                                        Dict.map
                                            (\_ s ->
                                                { s
                                                    | tracks = Dict.map (\_ t -> { t | keyframes = t.keyframes ++ List.take 1 t.keyframes }) s.tracks
                                                    , rootNodeIds = "ghost" :: s.rootNodeIds
                                                }
                                            )
                                            doc.scenes
                                }

                            issues =
                                Validation.validateDocument broken
                        in
                        Expect.all
                            [ \_ -> Expect.equal True (List.any (\i -> String.contains "same frame" i.message) issues)
                            , \_ -> Expect.equal True (List.any (\i -> i.objectId == "ghost") issues)
                            ]
                            ()

                    Nothing ->
                        Expect.fail "missing example"
        ]
