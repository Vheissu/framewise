module GoldenTest exposing (suite)

{-| GENERATED FILE: do not edit. Run `node tests/golden/generate-elm.mjs`.

Shared golden fixtures: the same expectations are checked against the
JavaScript player in tests/unit/player.test.ts.

-}

import Dict
import DocumentIO.Decode as Decode
import Domain.Document as Document
import Domain.Evaluate as Evaluate
import Domain.Fps as Fps
import Domain.Matrix as Matrix
import Domain.Node exposing (NodeGeometry(..))
import Domain.Paint exposing (Paint(..))
import Domain.Scene as Scene
import Expect
import Json.Decode as D
import Test exposing (..)


type Expected
    = Single Float
    | Many (List Float)


type alias Expectation =
    { frame : Float, nodeId : String, property : String, value : Expected, tolerance : Float }


type alias Golden =
    { name : String, json : String, expectations : List Expectation }


goldens : List Golden
goldens =
    [ { name = "basic-transform-opacity"
      , json = "{\"version\":1,\"scene\":{\"id\":\"scene\",\"name\":\"basic\",\"width\":400,\"height\":400,\"fps\":{\"numerator\":30,\"denominator\":1},\"durationFrames\":60,\"playbackMode\":\"repeat\"},\"nodes\":[{\"id\":\"box\",\"name\":\"box\",\"kind\":\"rect\",\"parentId\":null,\"childIds\":[],\"hidden\":false,\"locked\":false,\"opacity\":1,\"transform\":{\"translation\":{\"x\":10,\"y\":20},\"scale\":{\"x\":1,\"y\":1},\"rotation\":0,\"skew\":{\"x\":0,\"y\":0},\"pivot\":{\"x\":0,\"y\":0}},\"geometry\":{\"size\":{\"x\":100,\"y\":50},\"cornerRadius\":0},\"fill\":{\"type\":\"solid\",\"color\":{\"r\":0.2,\"g\":0.5,\"b\":0.95,\"a\":1}},\"stroke\":{\"paint\":{\"type\":\"none\"},\"width\":2,\"cap\":\"butt\",\"join\":\"miter\",\"miterLimit\":4,\"dashArray\":[],\"dashOffset\":0},\"effects\":[],\"motion\":null,\"metadata\":{\"importedElementId\":null}}],\"tracks\":[{\"id\":\"t1\",\"target\":{\"nodeId\":\"box\",\"property\":\"transform.position\"},\"enabled\":true,\"locked\":false,\"keyframes\":[{\"id\":\"a\",\"frame\":0,\"value\":{\"type\":\"point\",\"value\":{\"x\":10,\"y\":20}},\"easing\":{\"type\":\"linear\"}},{\"id\":\"b\",\"frame\":30,\"value\":{\"type\":\"point\",\"value\":{\"x\":110,\"y\":20}},\"easing\":{\"type\":\"preset\",\"name\":\"ease-in-out\"}},{\"id\":\"c\",\"frame\":60,\"value\":{\"type\":\"point\",\"value\":{\"x\":110,\"y\":220}},\"easing\":{\"type\":\"linear\"}}]},{\"id\":\"t2\",\"target\":{\"nodeId\":\"box\",\"property\":\"compositing.opacity\"},\"enabled\":true,\"locked\":false,\"keyframes\":[{\"id\":\"d\",\"frame\":10,\"value\":{\"type\":\"scalar\",\"value\":1},\"easing\":{\"type\":\"linear\"}},{\"id\":\"e\",\"frame\":50,\"value\":{\"type\":\"scalar\",\"value\":0.2},\"easing\":{\"type\":\"linear\"}}]}],\"motionPaths\":[]}"
      , expectations =
            [ { frame = 0, nodeId = "box", property = "position", value = Many [ 10, 20 ], tolerance = 0.000001 }
            , { frame = 15, nodeId = "box", property = "position", value = Many [ 60, 20 ], tolerance = 0.000001 }
            , { frame = 30, nodeId = "box", property = "position", value = Many [ 110, 20 ], tolerance = 0.000001 }
            , { frame = 45, nodeId = "box", property = "position", value = Many [ 110, 120 ], tolerance = 0.000001 }
            , { frame = 60, nodeId = "box", property = "position", value = Many [ 110, 220 ], tolerance = 0.000001 }
            , { frame = 75, nodeId = "box", property = "position", value = Many [ 110, 220 ], tolerance = 0.000001 }
            , { frame = 0, nodeId = "box", property = "opacity", value = Single 1, tolerance = 0.000001 }
            , { frame = 10, nodeId = "box", property = "opacity", value = Single 1, tolerance = 0.000001 }
            , { frame = 30, nodeId = "box", property = "opacity", value = Single 0.6, tolerance = 0.000001 }
            , { frame = 50, nodeId = "box", property = "opacity", value = Single 0.2, tolerance = 0.000001 }
            , { frame = 60, nodeId = "box", property = "opacity", value = Single 0.2, tolerance = 0.000001 }
            ]
      }
    , { name = "easing-hold-bezier-rotation-pivot"
      , json = "{\"version\":1,\"scene\":{\"id\":\"scene\",\"name\":\"easing\",\"width\":400,\"height\":400,\"fps\":{\"numerator\":30,\"denominator\":1},\"durationFrames\":60,\"playbackMode\":\"repeat\"},\"nodes\":[{\"id\":\"n\",\"name\":\"n\",\"kind\":\"ellipse\",\"parentId\":null,\"childIds\":[],\"hidden\":false,\"locked\":false,\"opacity\":1,\"transform\":{\"translation\":{\"x\":100,\"y\":100},\"scale\":{\"x\":1,\"y\":1},\"rotation\":0,\"skew\":{\"x\":0,\"y\":0},\"pivot\":{\"x\":10,\"y\":0}},\"geometry\":{\"radii\":{\"x\":20,\"y\":20}},\"fill\":{\"type\":\"solid\",\"color\":{\"r\":0.2,\"g\":0.5,\"b\":0.95,\"a\":1}},\"stroke\":{\"paint\":{\"type\":\"none\"},\"width\":2,\"cap\":\"butt\",\"join\":\"miter\",\"miterLimit\":4,\"dashArray\":[],\"dashOffset\":0},\"effects\":[],\"motion\":null,\"metadata\":{\"importedElementId\":null}}],\"tracks\":[{\"id\":\"r\",\"target\":{\"nodeId\":\"n\",\"property\":\"transform.rotation\"},\"enabled\":true,\"locked\":false,\"keyframes\":[{\"id\":\"a\",\"frame\":0,\"value\":{\"type\":\"angle\",\"value\":0},\"easing\":{\"type\":\"hold\"}},{\"id\":\"b\",\"frame\":20,\"value\":{\"type\":\"angle\",\"value\":90},\"easing\":{\"type\":\"preset\",\"name\":\"ease-in\"}},{\"id\":\"c\",\"frame\":40,\"value\":{\"type\":\"angle\",\"value\":180},\"easing\":{\"type\":\"cubicBezier\",\"x1\":0.3,\"y1\":-0.4,\"x2\":0.6,\"y2\":1.5}},{\"id\":\"d\",\"frame\":60,\"value\":{\"type\":\"angle\",\"value\":360},\"easing\":{\"type\":\"linear\"}}]}],\"motionPaths\":[]}"
      , expectations =
            [ { frame = 0, nodeId = "n", property = "rotation", value = Single 0, tolerance = 0.00001 }
            , { frame = 0, nodeId = "n", property = "position", value = Many [ 100, 100 ], tolerance = 0.0001 }
            , { frame = 10, nodeId = "n", property = "rotation", value = Single 0, tolerance = 0.00001 }
            , { frame = 10, nodeId = "n", property = "position", value = Many [ 100, 100 ], tolerance = 0.0001 }
            , { frame = 19, nodeId = "n", property = "rotation", value = Single 0, tolerance = 0.00001 }
            , { frame = 19, nodeId = "n", property = "position", value = Many [ 100, 100 ], tolerance = 0.0001 }
            , { frame = 20, nodeId = "n", property = "rotation", value = Single 90, tolerance = 0.00001 }
            , { frame = 20, nodeId = "n", property = "position", value = Many [ 110, 90 ], tolerance = 0.0001 }
            , { frame = 30, nodeId = "n", property = "rotation", value = Single 118.38211313152854, tolerance = 0.00001 }
            , { frame = 30, nodeId = "n", property = "position", value = Many [ 114.75349573029948, 91.20202987377061 ], tolerance = 0.0001 }
            , { frame = 40, nodeId = "n", property = "rotation", value = Single 180, tolerance = 0.00001 }
            , { frame = 40, nodeId = "n", property = "position", value = Many [ 120, 100 ], tolerance = 0.0001 }
            , { frame = 50, nodeId = "n", property = "rotation", value = Single 291.6306783769554, tolerance = 0.00001 }
            , { frame = 50, nodeId = "n", property = "position", value = Many [ 106.31377661807923, 109.29579244489574 ], tolerance = 0.0001 }
            , { frame = 60, nodeId = "n", property = "rotation", value = Single 360, tolerance = 0.00001 }
            , { frame = 60, nodeId = "n", property = "position", value = Many [ 100, 100 ], tolerance = 0.0001 }
            ]
      }
    , { name = "motion-path-polyline"
      , json = "{\"version\":1,\"scene\":{\"id\":\"scene\",\"name\":\"motion\",\"width\":400,\"height\":400,\"fps\":{\"numerator\":30,\"denominator\":1},\"durationFrames\":40,\"playbackMode\":\"repeat\"},\"nodes\":[{\"id\":\"m\",\"name\":\"m\",\"kind\":\"polygon\",\"parentId\":null,\"childIds\":[],\"hidden\":false,\"locked\":false,\"opacity\":1,\"transform\":{\"translation\":{\"x\":50,\"y\":50},\"scale\":{\"x\":1,\"y\":1},\"rotation\":0,\"skew\":{\"x\":0,\"y\":0},\"pivot\":{\"x\":0,\"y\":0}},\"geometry\":{\"sides\":3,\"radius\":5,\"innerRadius\":null},\"fill\":{\"type\":\"solid\",\"color\":{\"r\":0.2,\"g\":0.5,\"b\":0.95,\"a\":1}},\"stroke\":{\"paint\":{\"type\":\"none\"},\"width\":2,\"cap\":\"butt\",\"join\":\"miter\",\"miterLimit\":4,\"dashArray\":[],\"dashOffset\":0},\"effects\":[],\"motion\":{\"pathId\":\"mp\",\"orient\":true},\"metadata\":{\"importedElementId\":null}}],\"tracks\":[{\"id\":\"p\",\"target\":{\"nodeId\":\"m\",\"property\":\"motion.progress\"},\"enabled\":true,\"locked\":false,\"keyframes\":[{\"id\":\"a\",\"frame\":0,\"value\":{\"type\":\"scalar\",\"value\":0},\"easing\":{\"type\":\"linear\"}},{\"id\":\"b\",\"frame\":40,\"value\":{\"type\":\"scalar\",\"value\":1},\"easing\":{\"type\":\"linear\"}}]}],\"motionPaths\":[{\"id\":\"mp\",\"geometry\":{\"subpaths\":[{\"start\":{\"x\":0,\"y\":0},\"closed\":false,\"segments\":[{\"type\":\"line\",\"to\":{\"x\":100,\"y\":0}},{\"type\":\"line\",\"to\":{\"x\":100,\"y\":100}}]}]}}]}"
      , expectations =
            [ { frame = 0, nodeId = "m", property = "position", value = Many [ 50, 50 ], tolerance = 0.000001 }
            , { frame = 10, nodeId = "m", property = "position", value = Many [ 100, 50 ], tolerance = 0.000001 }
            , { frame = 20, nodeId = "m", property = "position", value = Many [ 150, 50 ], tolerance = 0.000001 }
            , { frame = 30, nodeId = "m", property = "position", value = Many [ 150, 100 ], tolerance = 0.000001 }
            , { frame = 40, nodeId = "m", property = "position", value = Many [ 150, 150 ], tolerance = 0.000001 }
            ]
      }
    , { name = "spring-colour-size"
      , json = "{\"version\":1,\"scene\":{\"id\":\"scene\",\"name\":\"spring\",\"width\":400,\"height\":400,\"fps\":{\"numerator\":30,\"denominator\":1},\"durationFrames\":60,\"playbackMode\":\"repeat\"},\"nodes\":[{\"id\":\"s\",\"name\":\"s\",\"kind\":\"rect\",\"parentId\":null,\"childIds\":[],\"hidden\":false,\"locked\":false,\"opacity\":1,\"transform\":{\"translation\":{\"x\":0,\"y\":0},\"scale\":{\"x\":1,\"y\":1},\"rotation\":0,\"skew\":{\"x\":0,\"y\":0},\"pivot\":{\"x\":0,\"y\":0}},\"geometry\":{\"size\":{\"x\":10,\"y\":10},\"cornerRadius\":0},\"fill\":{\"type\":\"solid\",\"color\":{\"r\":1,\"g\":0,\"b\":0,\"a\":1}},\"stroke\":{\"paint\":{\"type\":\"none\"},\"width\":2,\"cap\":\"butt\",\"join\":\"miter\",\"miterLimit\":4,\"dashArray\":[],\"dashOffset\":0},\"effects\":[],\"motion\":null,\"metadata\":{\"importedElementId\":null}}],\"tracks\":[{\"id\":\"sc\",\"target\":{\"nodeId\":\"s\",\"property\":\"transform.scale\"},\"enabled\":true,\"locked\":false,\"keyframes\":[{\"id\":\"a\",\"frame\":0,\"value\":{\"type\":\"point\",\"value\":{\"x\":1,\"y\":1}},\"easing\":{\"type\":\"spring\",\"mass\":1,\"stiffness\":200,\"damping\":3,\"velocity\":0}},{\"id\":\"b\",\"frame\":50,\"value\":{\"type\":\"point\",\"value\":{\"x\":2,\"y\":0.5}},\"easing\":{\"type\":\"linear\"}}]},{\"id\":\"fc\",\"target\":{\"nodeId\":\"s\",\"property\":\"style.fill.color\"},\"enabled\":true,\"locked\":false,\"keyframes\":[{\"id\":\"c\",\"frame\":0,\"value\":{\"type\":\"color\",\"value\":{\"r\":1,\"g\":0,\"b\":0,\"a\":1}},\"easing\":{\"type\":\"linear\"}},{\"id\":\"d\",\"frame\":40,\"value\":{\"type\":\"color\",\"value\":{\"r\":0,\"g\":0,\"b\":1,\"a\":0.2}},\"easing\":{\"type\":\"linear\"}}]},{\"id\":\"rw\",\"target\":{\"nodeId\":\"s\",\"property\":\"shape.rect.size\"},\"enabled\":true,\"locked\":false,\"keyframes\":[{\"id\":\"e\",\"frame\":0,\"value\":{\"type\":\"size\",\"value\":{\"x\":10,\"y\":10}},\"easing\":{\"type\":\"preset\",\"name\":\"ease-in-out\"}},{\"id\":\"f\",\"frame\":20,\"value\":{\"type\":\"size\",\"value\":{\"x\":30,\"y\":10}},\"easing\":{\"type\":\"linear\"}}]}],\"motionPaths\":[]}"
      , expectations =
            [ { frame = 0, nodeId = "s", property = "scale", value = Many [ 1, 1 ], tolerance = 0.000001 }
            , { frame = 5, nodeId = "s", property = "scale", value = Many [ 1.7684306537797423, 0.6157846731101289 ], tolerance = 0.000001 }
            , { frame = 12, nodeId = "s", property = "scale", value = Many [ 2.695973842153796, 0.15201307892310212 ], tolerance = 0.000001 }
            , { frame = 25, nodeId = "s", property = "scale", value = Many [ 1.6194585978228448, 0.6902707010885776 ], tolerance = 0.000001 }
            , { frame = 40, nodeId = "s", property = "scale", value = Many [ 1.9553192667139627, 0.5223403666430186 ], tolerance = 0.000001 }
            , { frame = 50, nodeId = "s", property = "scale", value = Many [ 2, 0.5 ], tolerance = 0.000001 }
            , { frame = 0, nodeId = "s", property = "fill", value = Many [ 1, 1 ], tolerance = 0.000001 }
            , { frame = 10, nodeId = "s", property = "fill", value = Many [ 0.75, 0.8 ], tolerance = 0.000001 }
            , { frame = 40, nodeId = "s", property = "fill", value = Many [ 0, 0.19999999999999996 ], tolerance = 0.000001 }
            , { frame = 45, nodeId = "s", property = "fill", value = Many [ 0, 0.19999999999999996 ], tolerance = 0.000001 }
            , { frame = 0, nodeId = "s", property = "rectWidth", value = Single 10, tolerance = 0.000001 }
            , { frame = 10, nodeId = "s", property = "rectWidth", value = Single 20, tolerance = 0.000001 }
            , { frame = 20, nodeId = "s", property = "rectWidth", value = Single 30, tolerance = 0.000001 }
            ]
      }
    ]


animationDecoder : D.Decoder Scene.Scene
animationDecoder =
    D.map4
        (\meta nodes tracks motionPaths ->
            let
                base =
                    Scene.new meta.id meta.name meta.width meta.height meta.fps meta.duration Scene.Transparent
            in
            { base
                | rootNodeIds = List.map .id (List.filter (\n -> n.parentId == Nothing) nodes)
                , nodes = Dict.fromList (List.map (\n -> ( n.id, n )) nodes)
                , tracks = Dict.fromList (List.map (\t -> ( t.id, t )) tracks)
                , motionPaths = Dict.fromList (List.map (\m -> ( m.id, m )) motionPaths)
            }
        )
        (D.field "scene"
            (D.map6 (\id name w h f d -> { id = id, name = name, width = w, height = h, fps = f, duration = d })
                (D.field "id" D.string)
                (D.field "name" D.string)
                (D.field "width" D.float)
                (D.field "height" D.float)
                (D.field "fps" (D.map2 Fps.fps (D.field "numerator" D.int) (D.field "denominator" D.int)))
                (D.field "durationFrames" D.int)
            )
        )
        (D.field "nodes" (D.list Decode.node))
        (D.field "tracks" (D.list Decode.track))
        (D.field "motionPaths" (D.list (D.map2 (\id g -> { id = id, name = id, geometry = g, revision = 0 }) (D.field "id" D.string) (D.field "geometry" Decode.pathGeometryDecoder))))


readProperty : Evaluate.ResolvedNode -> String -> Maybe Expected
readProperty node property =
    let
        origin =
            Matrix.apply node.worldMatrix { x = 0, y = 0 }
    in
    case property of
        "position" ->
            Just (Many [ origin.x, origin.y ])

        "opacity" ->
            Just (Single node.opacity)

        "rotation" ->
            Just (Single (atan2 node.localMatrix.b node.localMatrix.a * 180 / pi))

        "scale" ->
            let
                sx =
                    sqrt (node.localMatrix.a * node.localMatrix.a + node.localMatrix.b * node.localMatrix.b)

                sy =
                    Matrix.determinant node.localMatrix / sx
            in
            Just (Many [ sx, sy ])

        "fill" ->
            case node.fill of
                Solid c ->
                    Just (Many [ c.r, c.a ])

                _ ->
                    Just (Many [ -1, -1 ])

        "rectWidth" ->
            case node.geometry of
                Rectangle r ->
                    Just (Single r.size.x)

                _ ->
                    Nothing

        _ ->
            Nothing


angleDistance : Float -> Float -> Float
angleDistance a b =
    let
        d =
            abs (a - b)

        m =
            d - 360 * toFloat (floor (d / 360))
    in
    min m (360 - m)


checkExpectation : Scene.Scene -> Expectation -> (() -> Expect.Expectation)
checkExpectation scene e =
    \_ ->
        let
            doc =
                Document.new "d" "d" "0" scene
        in
        case Evaluate.evaluateScene doc scene.id e.frame |> Maybe.andThen (\r -> Dict.get e.nodeId r.byId) of
            Nothing ->
                Expect.fail ("node " ++ e.nodeId ++ " missing")

            Just node ->
                case ( readProperty node e.property, e.value ) of
                    ( Just (Single actual), Single expected ) ->
                        if e.property == "rotation" then
                            Expect.atMost e.tolerance (angleDistance expected actual)

                        else
                            Expect.within (Expect.Absolute e.tolerance) expected actual

                    ( Just (Many actual), Many expected ) ->
                        Expect.all (List.map2 (\a x -> \_ -> Expect.within (Expect.Absolute e.tolerance) x a) actual expected) ()

                    _ ->
                        Expect.fail ("cannot read " ++ e.property ++ " at frame " ++ String.fromFloat e.frame)


suite : Test
suite =
    describe "golden fixtures (shared with the player)"
        (List.map
            (\g ->
                test g.name <|
                    \_ ->
                        case D.decodeString animationDecoder g.json of
                            Ok scene ->
                                Expect.all (List.map (checkExpectation scene) g.expectations) ()

                            Err err ->
                                Expect.fail (D.errorToString err)
            )
            goldens
        )
