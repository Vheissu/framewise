module Domain.History exposing
    ( Entry
    , History
    , canRedo
    , canUndo
    , commit
    , commitCoalesced
    , entries
    , init
    , redo
    , undo
    )

{-| Undo history as a bounded stack of document snapshots with descriptions.
Elm's persistent data structures share unchanged structure between
snapshots, so this is cheap for ordinary edits. Consecutive commits with the
same coalesce key (e.g. typing in a field, nudging) collapse into one entry.
-}


type alias Entry a =
    { description : String
    , coalesceKey : Maybe String
    , before : a
    }


type alias History a =
    { past : List (Entry a)
    , future : List ( String, a )
    , limit : Int
    }


init : Int -> History a
init limit =
    { past = [], future = [], limit = max 1 limit }


entries : History a -> List String
entries h =
    List.map .description h.past


canUndo : History a -> Bool
canUndo h =
    not (List.isEmpty h.past)


canRedo : History a -> Bool
canRedo h =
    not (List.isEmpty h.future)


{-| Record that `before` is being replaced by a new state described by
`description`. Clears the redo stack.
-}
commit : String -> a -> History a -> History a
commit description before h =
    { h
        | past = List.take h.limit ({ description = description, coalesceKey = Nothing, before = before } :: h.past)
        , future = []
    }


{-| Like `commit`, but if the previous entry has the same key the new change
merges into it (keeping the older `before`).
-}
commitCoalesced : String -> String -> a -> History a -> History a
commitCoalesced key description before h =
    case h.past of
        top :: _ ->
            if top.coalesceKey == Just key then
                { h | future = [] }

            else
                { h
                    | past = List.take h.limit ({ description = description, coalesceKey = Just key, before = before } :: h.past)
                    , future = []
                }

        [] ->
            { h
                | past = [ { description = description, coalesceKey = Just key, before = before } ]
                , future = []
            }


{-| Undo: returns the restored state and the new history.
-}
undo : a -> History a -> Maybe ( a, History a )
undo current h =
    case h.past of
        [] ->
            Nothing

        top :: rest ->
            Just
                ( top.before
                , { h | past = rest, future = ( top.description, current ) :: h.future }
                )


redo : a -> History a -> Maybe ( a, History a )
redo current h =
    case h.future of
        [] ->
            Nothing

        ( description, state ) :: rest ->
            Just
                ( state
                , { h
                    | future = rest
                    , past = { description = description, coalesceKey = Nothing, before = current } :: h.past
                  }
                )
