port module App.Ports exposing
    ( Request
    , fromJs
    , request
    , send
    , toJs
    )

{-| The single typed bridge to TypeScript. Every outgoing message is a
versioned envelope with an operation name and payload; every incoming message
is decoded strictly in `App.Update`.
-}

import Json.Encode as E


port toJs : E.Value -> Cmd msg


port fromJs : (E.Value -> msg) -> Sub msg


protocolVersion : Int
protocolVersion =
    1


type alias Request =
    { requestId : String
    , operation : String
    , documentId : Maybe String
    , revision : Maybe Int
    , payload : E.Value
    }


request : String -> String -> E.Value -> Request
request requestId operation payload =
    { requestId = requestId, operation = operation, documentId = Nothing, revision = Nothing, payload = payload }


send : Request -> Cmd msg
send r =
    toJs
        (E.object
            [ ( "protocolVersion", E.int protocolVersion )
            , ( "requestId", E.string r.requestId )
            , ( "operation", E.string r.operation )
            , ( "documentId", Maybe.map E.string r.documentId |> Maybe.withDefault E.null )
            , ( "revision", Maybe.map E.int r.revision |> Maybe.withDefault E.null )
            , ( "payload", r.payload )
            ]
        )
