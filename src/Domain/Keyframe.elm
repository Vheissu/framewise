module Domain.Keyframe exposing
    ( Keyframe
    , Track
    , TrackTarget
    , frames
    , insert
    , isSorted
    , keyAt
    , newTrack
    , remove
    , removeAt
    , scale
    , segmentAt
    , setEasing
    , setFrame
    , setValue
    , shift
    , trackKey
    )

{-| Keyframes and tracks. Keyframes are kept sorted by integer frame and a
track never holds two keys at the same frame; `insert` overwrites.
-}

import Domain.Easing exposing (Easing(..))
import Domain.Property exposing (PropertyPath, PropertyValue)
import Shared.Ids exposing (KeyframeId, NodeId, TrackId)


type alias Keyframe =
    { id : KeyframeId
    , frame : Int
    , value : PropertyValue
    , easing : Easing
    }


type alias TrackTarget =
    { nodeId : NodeId, property : PropertyPath }


type alias Track =
    { id : TrackId
    , target : TrackTarget
    , enabled : Bool
    , locked : Bool
    , keyframes : List Keyframe
    }


newTrack : TrackId -> NodeId -> PropertyPath -> Track
newTrack id nodeId property =
    { id = id
    , target = { nodeId = nodeId, property = property }
    , enabled = True
    , locked = False
    , keyframes = []
    }


{-| Stable composite key for looking up a track by node and property.
-}
trackKey : NodeId -> PropertyPath -> String
trackKey nodeId property =
    nodeId ++ "|" ++ Domain.Property.pathToCode property


frames : Track -> List Int
frames t =
    List.map .frame t.keyframes


isSorted : Track -> Bool
isSorted t =
    let
        fs =
            frames t
    in
    List.map2 (<) fs (List.drop 1 fs) |> List.all identity


keyAt : Int -> Track -> Maybe Keyframe
keyAt frame t =
    List.filter (\k -> k.frame == frame) t.keyframes |> List.head


{-| Insert or overwrite the key at the keyframe's frame.
-}
insert : Keyframe -> Track -> Track
insert key t =
    let
        others =
            List.filter (\k -> k.frame /= key.frame) t.keyframes
    in
    { t | keyframes = List.sortBy .frame (key :: others) }


remove : KeyframeId -> Track -> Track
remove keyId t =
    { t | keyframes = List.filter (\k -> k.id /= keyId) t.keyframes }


removeAt : Int -> Track -> Track
removeAt frame t =
    { t | keyframes = List.filter (\k -> k.frame /= frame) t.keyframes }


setValue : KeyframeId -> PropertyValue -> Track -> Track
setValue keyId value t =
    { t | keyframes = List.map (\k -> ifId keyId k { k | value = value }) t.keyframes }


setEasing : KeyframeId -> Easing -> Track -> Track
setEasing keyId easing t =
    { t | keyframes = List.map (\k -> ifId keyId k { k | easing = easing }) t.keyframes }


{-| Move a key to a new frame. If another key occupies the target frame it is
overwritten.
-}
setFrame : KeyframeId -> Int -> Track -> Track
setFrame keyId frame t =
    case List.filter (\k -> k.id == keyId) t.keyframes of
        key :: _ ->
            let
                moved =
                    { key | frame = max 0 frame }
            in
            insert moved { t | keyframes = List.filter (\k -> k.id /= keyId) t.keyframes }

        [] ->
            t


{-| Shift a set of keys by a frame delta. Keys are clamped at 0; collisions
with unselected keys overwrite them.
-}
shift : List KeyframeId -> Int -> Track -> Track
shift ids delta t =
    let
        ( moving, staying ) =
            List.partition (\k -> List.member k.id ids) t.keyframes

        movedKeys =
            List.map (\k -> { k | frame = max 0 (k.frame + delta) }) moving

        movedFrames =
            List.map .frame movedKeys
    in
    { t
        | keyframes =
            List.sortBy .frame
                (movedKeys ++ List.filter (\k -> not (List.member k.frame movedFrames)) staying)
    }


{-| Scale the timing of selected keys around an anchor frame.
-}
scale : List KeyframeId -> Int -> Float -> Track -> Track
scale ids anchor factor t =
    let
        ( moving, staying ) =
            List.partition (\k -> List.member k.id ids) t.keyframes

        movedKeys =
            List.map (\k -> { k | frame = max 0 (anchor + round (toFloat (k.frame - anchor) * factor)) }) moving

        -- resolve collisions inside the moved set deterministically: last wins
        dedup =
            List.foldl (\k acc -> k :: List.filter (\o -> o.frame /= k.frame) acc) [] movedKeys

        movedFrames =
            List.map .frame dedup
    in
    { t
        | keyframes =
            List.sortBy .frame (dedup ++ List.filter (\k -> not (List.member k.frame movedFrames)) staying)
    }


{-| The segment governing `frame`: the key at or before and the key after.
-}
segmentAt : Float -> Track -> { before : Maybe Keyframe, after : Maybe Keyframe }
segmentAt frame t =
    let
        step k acc =
            if toFloat k.frame <= frame then
                { acc | before = Just k }

            else
                case acc.after of
                    Nothing ->
                        { acc | after = Just k }

                    Just _ ->
                        acc
    in
    List.foldl step { before = Nothing, after = Nothing } t.keyframes


ifId : KeyframeId -> Keyframe -> Keyframe -> Keyframe
ifId id k replacement =
    if k.id == id then
        replacement

    else
        k
