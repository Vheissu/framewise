module Domain.Loop exposing (mapFrame)

{-| Map an unbounded continuous frame into a scene's frame range according to
its playback mode. `n` is `durationFrames`.

  - Once: clamp to `[0, n]`.
  - Repeat: wrap into `[0, n)` with a mathematically correct modulo for
    negative time.
  - PingPong: mirror over `[0, n]` with period `2n`.

-}

import Domain.Scene exposing (PlaybackMode(..))


mapFrame : PlaybackMode -> Int -> Float -> Float
mapFrame mode n frame =
    let
        nf =
            toFloat (max 1 n)
    in
    case mode of
        PlayOnce ->
            clamp 0 nf frame

        Repeat ->
            fmod frame nf

        PingPong ->
            let
                period =
                    2 * nf

                m =
                    fmod frame period
            in
            if m <= nf then
                m

            else
                period - m


fmod : Float -> Float -> Float
fmod a b =
    a - b * toFloat (floor (a / b))
