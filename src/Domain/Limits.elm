module Domain.Limits exposing
    ( maxCanvasDimension
    , maxDurationFrames
    , maxKeyframesPerTrack
    , maxNestingDepth
    , maxNodesPerScene
    , maxOutputPixels
    , maxPathSegments
    , maxTracksPerScene
    )

{-| Conservative guard rails. Content beyond these limits fails validation
with an explanation instead of exhausting memory.
-}


maxCanvasDimension : Float
maxCanvasDimension =
    16384


maxOutputPixels : Int
maxOutputPixels =
    64000000


maxNodesPerScene : Int
maxNodesPerScene =
    5000


maxPathSegments : Int
maxPathSegments =
    20000


maxKeyframesPerTrack : Int
maxKeyframesPerTrack =
    5000


maxTracksPerScene : Int
maxTracksPerScene =
    5000


maxDurationFrames : Int
maxDurationFrames =
    100000


maxNestingDepth : Int
maxNestingDepth =
    64
