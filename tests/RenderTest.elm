module RenderTest exposing (suite)

import App.Examples as Examples
import Dict
import Expect
import Export.Static as Static
import Test exposing (..)


suite : Test
suite =
    describe "scene rendering"
        [ test "clip paths hold the clip shape directly, with its transform on the clipPath" <|
            \_ ->
                case Examples.build "illustration" "d" "s" "0" |> Maybe.andThen (\doc -> Dict.get "s" doc.scenes |> Maybe.andThen (Static.export Static.defaultOptions doc)) of
                    Just svg ->
                        Expect.all
                            [ \s -> Expect.equal True (String.contains "<clipPath id=\"fw-s-clip-clip\" transform=\"matrix(1 0 0 1 0 0)\"><rect" s)
                            , \s -> Expect.equal False (String.contains "<clipPath id=\"fw-s-clip-clip\"><g" s)
                            ]
                            svg

                    Nothing ->
                        Expect.fail "illustration example did not render"
        ]
