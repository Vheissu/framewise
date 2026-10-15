module EvaluateTest exposing (suite)

import App.Examples as Examples
import Dict
import Domain.Document as Document
import Domain.Easing
import Domain.Evaluate as Evaluate
import Domain.Fps as Fps
import Domain.Keyframe as Keyframe
import Domain.Matrix as Matrix
import Domain.Node as Node exposing (NodeGeometry(..))
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene
import Expect
import Test exposing (..)


suite : Test
suite =
    describe "Domain.Evaluate"
        [ test "the bouncing ball is at its keyed positions on key frames and between them in the middle" <|
            \_ ->
                case Examples.build "bouncing-ball" "doc" "scene" "0" of
                    Just doc ->
                        let
                            at f =
                                Evaluate.evaluateScene doc "scene" f |> Maybe.andThen (\r -> Dict.get "ball" r.byId) |> Maybe.map (\n -> Matrix.apply n.worldMatrix { x = 0, y = 0 })
                        in
                        Expect.all
                            [ \_ -> Expect.equal (Just { x = 200, y = 90 }) (at 0)
                            , \_ -> Expect.equal (Just { x = 200, y = 280 }) (at 30)
                            , \_ -> Expect.equal (Just { x = 200, y = 90 }) (at 60)
                            , \_ ->
                                case at 15 of
                                    Just p ->
                                        Expect.all [ \_ -> Expect.greaterThan 90 p.y, \_ -> Expect.lessThan 280 p.y ] ()

                                    Nothing ->
                                        Expect.fail "no ball"
                            ]
                            ()

                    Nothing ->
                        Expect.fail "missing example"
        , test "evaluation does not depend on the order frames are visited" <|
            \_ ->
                case Examples.build "illustration" "doc" "scene" "0" of
                    Just doc ->
                        let
                            snapshot f =
                                Evaluate.evaluateScene doc "scene" f |> Maybe.map (\r -> List.map (\n -> ( n.id, n.worldMatrix, n.opacity )) r.nodes)

                            a =
                                [ snapshot 10, snapshot 40, snapshot 10 ]

                            b =
                                [ snapshot 10, snapshot 10, snapshot 10 ]
                        in
                        Expect.equal (List.head a) (List.head (List.reverse a))
                            |> always (Expect.equal a [ snapshot 10, snapshot 40, snapshot 10 ])
                            |> always (Expect.equal b [ snapshot 10, snapshot 10, snapshot 10 ])

                    Nothing ->
                        Expect.fail "missing example"
        , test "group transforms compose into child world matrices" <|
            \_ ->
                let
                    child =
                        Node.new "c" "c" (Rectangle { size = { x = 10, y = 10 }, cornerRadius = 0 })

                    group =
                        Node.new "g" "g" Group

                    scene =
                        Scene.new "s" "s" 100 100 (Fps.fps 30 1) 10 Scene.Transparent
                            |> Scene.insertNode Nothing 0 { group | transform = { translation = { x = 50, y = 0 }, scale = { x = 2, y = 2 }, rotation = 0, skew = { x = 0, y = 0 }, pivot = { x = 0, y = 0 } } }
                            |> Scene.insertNode (Just "g") 0 { child | transform = { translation = { x = 5, y = 5 }, scale = { x = 1, y = 1 }, rotation = 0, skew = { x = 0, y = 0 }, pivot = { x = 0, y = 0 } } }

                    doc =
                        Document.new "d" "d" "0" scene
                in
                case Evaluate.evaluateScene doc "s" 0 |> Maybe.andThen (\r -> Dict.get "c" r.byId) of
                    Just res ->
                        Expect.equal { x = 60, y = 10 } (Matrix.apply res.worldMatrix { x = 0, y = 0 })

                    Nothing ->
                        Expect.fail "child missing"
        , test "a motion path moves the node along its arc length with orientation" <|
            \_ ->
                case Examples.build "motion-path" "doc" "scene" "0" of
                    Just doc ->
                        let
                            pos f =
                                Evaluate.evaluateScene doc "scene" f |> Maybe.andThen (\r -> Dict.get "arrow" r.byId) |> Maybe.map (\n -> Matrix.apply n.worldMatrix { x = 0, y = 0 })
                        in
                        Expect.all
                            [ \_ ->
                                case pos 0 of
                                    Just p ->
                                        Expect.all [ \_ -> Expect.within (Expect.Absolute 1.0e-6) 40 p.x, \_ -> Expect.within (Expect.Absolute 1.0e-6) 260 p.y ] ()

                                    Nothing ->
                                        Expect.fail "no arrow"
                            , \_ ->
                                case pos 90 of
                                    Just p ->
                                        Expect.all [ \_ -> Expect.within (Expect.Absolute 1.0e-6) 440 p.x, \_ -> Expect.within (Expect.Absolute 1.0e-6) 200 p.y ] ()

                                    Nothing ->
                                        Expect.fail "no arrow"
                            ]
                            ()

                    Nothing ->
                        Expect.fail "missing example"
        , test "disabled tracks fall back to the base value" <|
            \_ ->
                let
                    node =
                        Node.new "n" "n" (Rectangle { size = { x = 10, y = 10 }, cornerRadius = 0 })

                    track =
                        Keyframe.newTrack "t" "n" Opacity
                            |> Keyframe.insert { id = "k", frame = 0, value = Scalar 0.2, easing = Domain.Easing.Linear }

                    scene =
                        Scene.new "s" "s" 100 100 (Fps.fps 30 1) 10 Scene.Transparent
                            |> Scene.insertNode Nothing 0 node
                            |> Scene.upsertTrack { track | enabled = False }

                    doc =
                        Document.new "d" "d" "0" scene
                in
                Expect.equal (Just 1) (Evaluate.evaluateScene doc "s" 0 |> Maybe.andThen (\r -> Dict.get "n" r.byId) |> Maybe.map .opacity)
        , test "compatible path morph interpolates and the midpoint is a true blend" <|
            \_ ->
                case Examples.build "morph" "doc" "scene" "0" of
                    Just doc ->
                        case Evaluate.evaluateScene doc "scene" 15 |> Maybe.andThen (\r -> Dict.get "blob" r.byId) of
                            Just res ->
                                case res.geometry of
                                    Path g ->
                                        case List.head g.subpaths of
                                            Just sp ->
                                                -- circle starts at (80,0), square at (80,-80): midpoint y is -40 at the half-way easing
                                                Expect.within (Expect.Absolute 1.0e-6) -40 sp.start.y

                                            Nothing ->
                                                Expect.fail "no subpath"

                                    _ ->
                                        Expect.fail "not a path"

                            Nothing ->
                                Expect.fail "no blob"

                    Nothing ->
                        Expect.fail "missing example"
        ]
