module Export.Spans exposing (bake)

{-| Layer spans (in and out points) as plain visibility animation. Exporters
and the portable player only understand keyframed visibility, so before
export every span is folded into the layer's visibility track: hold keys
that hide the layer before its in point and from its out point on, and keep
any visibility keys the user set inside the span.

The result evaluates to the same visibility as the span at every frame,
because visibility steps at keys rather than interpolating.

-}

import Dict
import Domain.Easing exposing (Easing(..))
import Domain.Interpolation as Interpolation
import Domain.Keyframe exposing (Track)
import Domain.Node exposing (Node)
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)


bake : Scene -> Scene
bake scene =
    Dict.foldl
        (\_ node acc ->
            case node.span of
                Just span ->
                    bakeNode span node acc

                Nothing ->
                    acc
        )
        scene
        scene.nodes


bakeNode : { inFrame : Int, outFrame : Int } -> Node -> Scene -> Scene
bakeNode span node scene =
    let
        existing =
            Scene.trackFor node.id Visible scene

        userTrack =
            existing |> Maybe.andThen (\t -> iif t.enabled (Just t) Nothing)

        userVisible frame =
            case userTrack |> Maybe.andThen (Interpolation.evaluateTrack (toFloat frame)) of
                Just (BoolValue v) ->
                    v

                _ ->
                    not node.hidden

        visibleAt frame =
            Domain.Node.inSpan scene.durationFrames (toFloat frame) node && userVisible frame

        userFrames =
            userTrack |> Maybe.map (.keyframes >> List.map .frame) |> Maybe.withDefault []

        frames =
            (0 :: span.inFrame :: span.outFrame :: userFrames)
                |> List.filter (\f -> f >= 0 && (f < scene.durationFrames || f == span.inFrame || List.member f userFrames))
                |> List.sort
                |> dedupe

        -- only keep a key where the visibility changes
        changes =
            List.foldl
                (\f ( acc, previous ) ->
                    let
                        v =
                            visibleAt f
                    in
                    if Just v == previous then
                        ( acc, previous )

                    else
                        ( ( f, v ) :: acc, Just v )
                )
                ( [], Nothing )
                frames
                |> Tuple.first
                |> List.reverse

        trackId =
            existing |> Maybe.map .id |> Maybe.withDefault ("span-" ++ node.id)

        track : Track
        track =
            { id = trackId
            , target = { nodeId = node.id, property = Visible }
            , enabled = True
            , locked = False
            , keyframes =
                List.map
                    (\( f, v ) -> { id = trackId ++ "-" ++ String.fromInt f, frame = f, value = BoolValue v, easing = Hold })
                    changes
            }
    in
    Scene.upsertTrack track (Scene.updateNode node.id (\n -> { n | span = Nothing }) scene)


dedupe : List Int -> List Int
dedupe list =
    List.foldr
        (\x acc ->
            case acc of
                y :: _ ->
                    if x == y then
                        acc

                    else
                        x :: acc

                [] ->
                    [ x ]
        )
        []
        list


iif : Bool -> a -> a -> a
iif c a b =
    if c then
        a

    else
        b
