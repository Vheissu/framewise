module SpanTest exposing (suite)

import App.Examples as Examples
import Dict
import DocumentIO.Decode as Decode
import DocumentIO.Encode as Encode
import Domain.Easing as Easing exposing (Easing(..))
import Domain.Evaluate as Evaluate
import Domain.Interpolation as Interpolation
import Domain.Keyframe as Keyframe
import Domain.LayerTime as LayerTime
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Expect
import Export.Capability as Capability
import Export.Smil as Smil
import Export.Spans as Spans
import Json.Decode
import Test exposing (..)


{-| The illustration example with layer spans: the sun only exists from frame
10 to 40, the near hill from 25 on but also has its own visibility keys, and
the scene clip (a group) is cut at frame 70.
-}
spanned : Maybe Scene
spanned =
    Examples.build "illustration" "doc" "scene" "0"
        |> Maybe.andThen (\doc -> Dict.get "scene" doc.scenes)
        |> Maybe.map
            (\scene ->
                scene
                    |> Scene.updateNode "sun" (\n -> { n | span = Just { inFrame = 10, outFrame = 40 } })
                    |> Scene.updateNode "hill2" (\n -> { n | span = Just { inFrame = 25, outFrame = 90 } })
                    |> Scene.updateNode "clip" (\n -> { n | span = Just { inFrame = 0, outFrame = 70 } })
                    |> Scene.upsertTrack
                        (let
                            t =
                                Keyframe.newTrack "vis" "hill2" Visible
                         in
                         { t
                            | keyframes =
                                [ { id = "v1", frame = 0, value = BoolValue True, easing = Hold }
                                , { id = "v2", frame = 30, value = BoolValue False, easing = Hold }
                                , { id = "v3", frame = 50, value = BoolValue True, easing = Hold }
                                ]
                         }
                        )
            )


hiddenFlags : Scene -> Float -> List ( String, Bool )
hiddenFlags scene frame =
    (Evaluate.evaluate scene frame).nodes |> List.map (\n -> ( n.id, n.inheritedHidden ))


suite : Test
suite =
    describe "layer spans"
        [ test "a layer is hidden outside its in and out points" <|
            \_ ->
                case spanned of
                    Just scene ->
                        let
                            sunHidden f =
                                Dict.get "sun" (Evaluate.evaluate scene f).byId |> Maybe.map .hidden
                        in
                        Expect.equal [ Just True, Just False, Just False, Just True ] [ sunHidden 9.5, sunHidden 10, sunHidden 39.9, sunHidden 40 ]

                    Nothing ->
                        Expect.fail "missing example"
        , test "baking spans into visibility keys gives the same visibility at every frame" <|
            \_ ->
                case spanned of
                    Just scene ->
                        let
                            baked =
                                Spans.bake scene

                            frames =
                                List.range 0 200 |> List.map (\i -> toFloat i * 0.5)
                        in
                        Expect.all
                            [ \_ -> Expect.equal (List.map (hiddenFlags scene) frames) (List.map (hiddenFlags baked) frames)
                            , \_ -> Expect.equal [] (Dict.values baked.nodes |> List.filterMap .span)
                            ]
                            ()

                    Nothing ->
                        Expect.fail "missing example"
        , test "spans survive a save and load" <|
            \_ ->
                case Examples.build "illustration" "doc" "scene" "0" of
                    Just doc ->
                        let
                            withSpan =
                                { doc | scenes = Dict.map (\_ s -> Scene.updateNode "sun" (\n -> { n | span = Just { inFrame = 5, outFrame = 60 } }) s) doc.scenes }

                            reloaded =
                                Json.Decode.decodeValue Decode.document (Encode.document withSpan)
                                    |> Result.toMaybe
                                    |> Maybe.andThen (\d -> Dict.get "scene" d.scenes)
                                    |> Maybe.andThen (\s -> Dict.get "sun" s.nodes)
                                    |> Maybe.andThen .span
                        in
                        Expect.equal (Just { inFrame = 5, outFrame = 60 }) reloaded

                    Nothing ->
                        Expect.fail "missing example"
        , test "a span with its out point before its in point is rejected" <|
            \_ ->
                Json.Decode.decodeString Decode.span """{"in": 30, "out": 10}"""
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , describe "cutting a track at a frame keeps every later value" <|
            List.map
                (\( name, easing ) ->
                    test name <|
                        \_ ->
                            let
                                track =
                                    Keyframe.newTrack "t" "n" Opacity
                                        |> (\t ->
                                                { t
                                                    | keyframes =
                                                        [ { id = "a", frame = 10, value = Scalar 0.1, easing = easing }
                                                        , { id = "b", frame = 40, value = Scalar 0.9, easing = easing }
                                                        , { id = "c", frame = 80, value = Scalar 0.3, easing = Linear }
                                                        ]
                                                }
                                           )

                                valueAt t f =
                                    case Interpolation.evaluateTrack f t of
                                        Just (Scalar v) ->
                                            v

                                        _ ->
                                            -1

                                frames =
                                    List.range 25 100 |> List.map toFloat
                            in
                            case LayerTime.cutAt 25 track of
                                Just cut ->
                                    Expect.all
                                        [ \_ -> Expect.equal (List.map .frame cut.keyframes) [ 25, 40, 80 ]
                                        , \_ ->
                                            List.map2 (\a b -> abs (a - b)) (List.map (valueAt track) frames) (List.map (valueAt cut) frames)
                                                |> List.maximum
                                                |> Maybe.withDefault 0
                                                |> Expect.atMost 1.0e-5
                                        ]
                                        ()

                                Nothing ->
                                    Expect.fail "cut refused"
                )
                [ ( "linear", Linear )
                , ( "hold", Hold )
                , ( "ease in out", Easing.Preset Easing.EaseInOut )
                , ( "overshooting bezier", CubicBezier 0.3 -0.4 0.6 1.5 )
                ]
        , test "a spring segment cannot be cut" <|
            \_ ->
                let
                    track =
                        Keyframe.newTrack "t" "n" Opacity
                            |> (\t ->
                                    { t
                                        | keyframes =
                                            [ { id = "a", frame = 10, value = Scalar 0.1, easing = Spring Easing.defaultSpring }
                                            , { id = "b", frame = 40, value = Scalar 0.9, easing = Linear }
                                            ]
                                    }
                               )
                in
                Expect.equal Nothing (LayerTime.cutAt 25 track)
        , test "moving a layer earlier plays its animation earlier, cutting keys at frame 0" <|
            \_ ->
                case Examples.build "illustration" "doc" "scene" "0" |> Maybe.andThen (\doc -> Dict.get "scene" doc.scenes) of
                    Just scene ->
                        let
                            withSpan =
                                LayerTime.setSpan "hill2" { inFrame = 30, outFrame = 90 } scene

                            moved =
                                LayerTime.shift [ "hill2" ] -20 withSpan

                            matrixAt s f =
                                Dict.get "hill2" (Evaluate.evaluate s f).byId |> Maybe.map (\n -> ( round (n.worldMatrix.e * 1000), round (n.worldMatrix.f * 1000), n.hidden ))
                        in
                        Expect.all
                            [ \_ -> Expect.equal (Just { inFrame = 10, outFrame = 70 }) (Dict.get "hill2" moved.nodes |> Maybe.andThen .span)
                            , \_ -> Expect.equal True (Dict.values moved.tracks |> List.all (.keyframes >> List.all (\k -> k.frame >= 0)))
                            , \_ -> Expect.equal (List.map (\f -> matrixAt withSpan (f + 20)) [ 10, 20, 35, 69 ]) (List.map (matrixAt moved) [ 10, 20, 35, 69 ])
                            ]
                            ()

                    Nothing ->
                        Expect.fail "missing example"
        , test "a layer span exports to SMIL as exact visibility steps" <|
            \_ ->
                case Examples.build "illustration" "doc" "scene" "0" of
                    Just doc ->
                        let
                            withSpan =
                                { doc | scenes = Dict.map (\_ s -> LayerTime.setSpan "sun" { inFrame = 15, outFrame = 45 } s) doc.scenes }

                            scene =
                                Dict.get "scene" withSpan.scenes
                        in
                        case scene |> Maybe.map (Smil.export { includeBackground = True, title = Nothing, description = Nothing, skipUnsupported = False } withSpan) of
                            Just (Ok out) ->
                                Expect.all
                                    [ \_ -> Expect.equal True (String.contains "attributeName=\"visibility\" values=\"hidden;visible;hidden\"" out.svg)
                                    , \_ ->
                                        out.report.items
                                            |> List.filter (\i -> i.nodeId == "sun")
                                            |> List.map .status
                                            |> Expect.equal [ Capability.Exact, Capability.Exact ]
                                    ]
                                    ()

                            _ ->
                                Expect.fail "export failed"

                    Nothing ->
                        Expect.fail "missing example"
        ]
