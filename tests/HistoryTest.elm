module HistoryTest exposing (suite)

import Domain.History as History
import Expect
import Test exposing (..)


suite : Test
suite =
    describe "Domain.History"
        [ test "undo restores the previous state and redo reapplies" <|
            \_ ->
                let
                    h0 =
                        History.init 10

                    h1 =
                        History.commit "Move" 1 h0

                    -- state is now 2
                    undone =
                        History.undo 2 h1
                in
                case undone of
                    Just ( state, h2 ) ->
                        Expect.all
                            [ \_ -> Expect.equal 1 state
                            , \_ -> Expect.equal (Just 2) (History.redo state h2 |> Maybe.map Tuple.first)
                            ]
                            ()

                    Nothing ->
                        Expect.fail "expected undo"
        , test "a new commit after undo clears the redo stack" <|
            \_ ->
                let
                    h =
                        History.commit "A" 1 (History.init 10)
                in
                case History.undo 2 h of
                    Just ( _, h2 ) ->
                        Expect.equal False (History.canRedo (History.commit "B" 1 h2))

                    Nothing ->
                        Expect.fail "expected undo"
        , test "coalesced commits merge into one entry" <|
            \_ ->
                let
                    h =
                        History.init 10
                            |> History.commitCoalesced "nudge" "Nudge" 0
                            |> History.commitCoalesced "nudge" "Nudge" 1
                            |> History.commitCoalesced "nudge" "Nudge" 2
                in
                Expect.all
                    [ \_ -> Expect.equal 1 (List.length (History.entries h))
                    , \_ -> Expect.equal (Just 0) (History.undo 3 h |> Maybe.map Tuple.first)
                    ]
                    ()
        , test "history is bounded" <|
            \_ ->
                let
                    h =
                        List.foldl (\i acc -> History.commit "c" i acc) (History.init 3) (List.range 1 10)
                in
                Expect.equal 3 (List.length (History.entries h))
        , test "undo on empty history is Nothing" <|
            \_ -> Expect.equal Nothing (History.undo 0 (History.init 5))
        ]
