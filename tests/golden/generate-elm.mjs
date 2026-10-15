// Generates tests/GoldenTest.elm from the JSON fixtures so the Elm evaluator and the
// JavaScript player are checked against the same expected values.
// Run: node tests/golden/generate-elm.mjs   (CI fails if the output is stale)
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const dir = dirname(fileURLToPath(import.meta.url));
const files = readdirSync(dir)
  .filter((f) => f.endsWith(".json"))
  .sort();
const elmString = (s) => JSON.stringify(s).replace(/\\u([0-9a-f]{4})/g, (_, h) => `\\u{${h}}`);
const num = (v) => {
  const s = String(v);
  if (s.includes("e")) {
    // Elm needs a decimal point in exponent literals: 1e-6 -> 1.0e-6
    const [mant, exp] = s.split("e");
    return `${mant.includes(".") ? mant : mant + ".0"}e${exp}`;
  }
  return s;
};

const cases = [];
for (const file of files) {
  const g = JSON.parse(readFileSync(resolve(dir, file), "utf8"));
  const exps = g.expectations
    .map((e) => {
      const value = Array.isArray(e.value)
        ? `Many [ ${e.value.map(num).join(", ")} ]`
        : `Single ${num(e.value)}`;
      return `{ frame = ${num(e.frame)}, nodeId = ${elmString(e.nodeId)}, property = ${elmString(e.property)}, value = ${value}, tolerance = ${num(e.tolerance ?? 1e-6)} }`;
    })
    .join("\n            , ");
  cases.push(
    `{ name = ${elmString(g.name)}\n      , json = ${elmString(JSON.stringify(g.animation))}\n      , expectations =\n            [ ${exps}\n            ]\n      }`,
  );
}

const out = `module GoldenTest exposing (suite)

{-| GENERATED FILE: do not edit. Run \`node tests/golden/generate-elm.mjs\`.

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
    [ ${cases.join("\n    , ")}
    ]


animationDecoder : D.Decoder Scene.Scene
animationDecoder =
    D.map4
        (\\meta nodes tracks motionPaths ->
            let
                base =
                    Scene.new meta.id meta.name meta.width meta.height meta.fps meta.duration Scene.Transparent
            in
            { base
                | rootNodeIds = List.map .id (List.filter (\\n -> n.parentId == Nothing) nodes)
                , nodes = Dict.fromList (List.map (\\n -> ( n.id, n )) nodes)
                , tracks = Dict.fromList (List.map (\\t -> ( t.id, t )) tracks)
                , motionPaths = Dict.fromList (List.map (\\m -> ( m.id, m )) motionPaths)
            }
        )
        (D.field "scene"
            (D.map6 (\\id name w h f d -> { id = id, name = name, width = w, height = h, fps = f, duration = d })
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
        (D.field "motionPaths" (D.list (D.map2 (\\id g -> { id = id, name = id, geometry = g, revision = 0 }) (D.field "id" D.string) (D.field "geometry" Decode.pathGeometryDecoder))))


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
    \\_ ->
        let
            doc =
                Document.new "d" "d" "0" scene
        in
        case Evaluate.evaluateScene doc scene.id e.frame |> Maybe.andThen (\\r -> Dict.get e.nodeId r.byId) of
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
                        Expect.all (List.map2 (\\a x -> \\_ -> Expect.within (Expect.Absolute e.tolerance) x a) actual expected) ()

                    _ ->
                        Expect.fail ("cannot read " ++ e.property ++ " at frame " ++ String.fromFloat e.frame)


suite : Test
suite =
    describe "golden fixtures (shared with the player)"
        (List.map
            (\\g ->
                test g.name <|
                    \\_ ->
                        case D.decodeString animationDecoder g.json of
                            Ok scene ->
                                Expect.all (List.map (checkExpectation scene) g.expectations) ()

                            Err err ->
                                Expect.fail (D.errorToString err)
            )
            goldens
        )
`;
writeFileSync(resolve(dir, "../GoldenTest.elm"), out);
console.log(`wrote tests/GoldenTest.elm from ${files.length} fixtures`);
