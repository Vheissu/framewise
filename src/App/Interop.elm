module App.Interop exposing
    ( capabilitiesDecoder
    , flagsDecoder
    , importReviewDecoder
    , layoutDecoder
    , layoutEncoder
    , preferencesDecoder
    , preferencesEncoder
    , recentDecoder
    , recoveryDecoder
    , responseDecoder
    )

import App.Model as Model exposing (Capabilities, Flags, Preferences, RecentEntry, RecoveryEntry)
import Domain.Fps as Fps
import Json.Decode as D exposing (Decoder)
import Json.Encode as E


flagsDecoder : Decoder Flags
flagsDecoder =
    D.succeed Flags
        |> andMap (D.field "basePath" D.string)
        |> andMap (D.field "isMac" D.bool)
        |> andMap (D.field "ids" (D.list D.string))
        |> andMap (D.field "capabilities" capabilitiesDecoder)
        |> andMap (D.maybe (D.field "preferences" D.value))
        |> andMap (D.oneOf [ D.field "recents" (D.list recentDecoder), D.succeed [] ])
        |> andMap (D.oneOf [ D.field "recoveries" (D.list recoveryDecoder), D.succeed [] ])
        |> andMap (D.field "now" D.int)
        |> andMap (D.oneOf [ D.field "reducedMotion" D.bool, D.succeed False ])
        |> andMap (D.oneOf [ D.field "version" D.string, D.succeed "0.0.0" ])
        |> andMap (D.maybe (D.field "layout" D.value))


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    D.map2 (|>)


capabilitiesDecoder : Decoder Capabilities
capabilitiesDecoder =
    D.succeed Capabilities
        |> andMap (boolField "nativeFilePickers")
        |> andMap (boolField "indexedDb")
        |> andMap (boolField "clipboardWrite")
        |> andMap (boolField "clipboardRead")
        |> andMap (boolField "offscreenCanvas")
        |> andMap (boolField "webCodecs")
        |> andMap (boolField "serviceWorker")
        |> andMap (boolField "persistentStorage")
        |> andMap (boolField "broadcastChannel")
        |> andMap
            (D.maybe
                (D.field "storageEstimate"
                    (D.map2 (\u q -> { usage = u, quota = q }) (D.field "usage" D.int) (D.field "quota" D.int))
                )
            )


boolField : String -> Decoder Bool
boolField name =
    D.oneOf [ D.field name D.bool, D.succeed False ]


recentDecoder : Decoder RecentEntry
recentDecoder =
    D.succeed RecentEntry
        |> andMap (D.field "documentId" D.string)
        |> andMap (D.field "name" D.string)
        |> andMap (D.oneOf [ D.field "width" D.float, D.succeed 0 ])
        |> andMap (D.oneOf [ D.field "height" D.float, D.succeed 0 ])
        |> andMap (D.oneOf [ D.field "sceneCount" D.int, D.succeed 1 ])
        |> andMap (D.field "modifiedAt" D.int)
        |> andMap (D.oneOf [ D.field "revision" D.int, D.succeed 0 ])
        |> andMap (D.oneOf [ D.field "hasAutosave" D.bool, D.succeed False ])
        |> andMap (D.maybe (D.field "fileName" D.string))


recoveryDecoder : Decoder RecoveryEntry
recoveryDecoder =
    D.succeed RecoveryEntry
        |> andMap (D.field "documentId" D.string)
        |> andMap (D.field "name" D.string)
        |> andMap (D.field "revision" D.int)
        |> andMap (D.maybe (D.field "savedRevision" D.int))
        |> andMap (D.field "checkpointAt" D.int)
        |> andMap (D.oneOf [ D.field "byteLength" D.int, D.succeed 0 ])
        |> andMap (D.oneOf [ D.field "decodable" D.bool, D.succeed True ])


importReviewDecoder : Decoder Model.ImportReview
importReviewDecoder =
    D.succeed Model.ImportReview
        |> andMap (D.oneOf [ D.field "fileName" D.string, D.succeed "import.svg" ])
        |> andMap (D.field "nodes" D.value)
        |> andMap (D.field "supportedCount" D.int)
        |> andMap (D.oneOf [ D.field "approximated" (D.list D.string), D.succeed [] ])
        |> andMap (D.oneOf [ D.field "unsupported" (D.list D.string), D.succeed [] ])
        |> andMap (D.oneOf [ D.field "warnings" (D.list D.string), D.succeed [] ])
        |> andMap (D.maybe (D.field "width" D.float))
        |> andMap (D.maybe (D.field "height" D.float))
        |> andMap (D.oneOf [ D.field "asNewDocument" D.bool, D.succeed False ])


type alias Response =
    { requestId : String
    , operation : String
    , status : String
    , payload : D.Value
    , code : Maybe String
    , message : Maybe String
    }


responseDecoder : Decoder Response
responseDecoder =
    D.succeed Response
        |> andMap (D.oneOf [ D.field "requestId" D.string, D.succeed "" ])
        |> andMap (D.field "operation" D.string)
        |> andMap (D.oneOf [ D.field "status" D.string, D.succeed "event" ])
        |> andMap (D.oneOf [ D.field "payload" D.value, D.succeed E.null ])
        |> andMap (D.maybe (D.field "code" D.string))
        |> andMap (D.maybe (D.field "message" D.string))


preferencesDecoder : Decoder Preferences
preferencesDecoder =
    let
        d =
            Model.defaultPreferences

        field name dec default =
            D.oneOf [ D.field name dec, D.succeed default ]
    in
    D.succeed Preferences
        |> andMap (field "theme" (D.map Model.themeFromCode D.string) d.theme)
        |> andMap (field "compact" D.bool d.compact)
        |> andMap (field "reducedMotionOverride" (D.nullable D.bool) d.reducedMotionOverride)
        |> andMap (field "autosaveIdleMs" D.int d.autosaveIdleMs)
        |> andMap (field "recentLimit" D.int d.recentLimit)
        |> andMap (field "gridSpacing" D.float d.gridSpacing)
        |> andMap (field "gridSubdivisions" D.int d.gridSubdivisions)
        |> andMap (field "defaultFps" (D.map2 Fps.fps (D.field "numerator" D.int) (D.field "denominator" D.int)) d.defaultFps)
        |> andMap (field "defaultDuration" D.int d.defaultDuration)
        |> andMap (field "defaultWidth" D.float d.defaultWidth)
        |> andMap (field "defaultHeight" D.float d.defaultHeight)
        |> andMap (field "autoKeyDefault" D.bool d.autoKeyDefault)
        |> andMap (field "nudge" D.float d.nudge)
        |> andMap (field "largeNudge" D.float d.largeNudge)
        |> andMap (field "snapTolerance" D.float d.snapTolerance)
        |> andMap (field "historyLimit" D.int d.historyLimit)
        |> andMap (field "confirmDelete" D.bool d.confirmDelete)
        |> andMap (field "showDiagnostics" D.bool d.showDiagnostics)
        |> andMap (field "offKeyPolicy" D.string d.offKeyPolicy)
        |> andMap (field "timelineSnap" D.bool d.timelineSnap)


preferencesEncoder : Preferences -> E.Value
preferencesEncoder p =
    E.object
        [ ( "theme", E.string (Model.themeToCode p.theme) )
        , ( "compact", E.bool p.compact )
        , ( "reducedMotionOverride", Maybe.map E.bool p.reducedMotionOverride |> Maybe.withDefault E.null )
        , ( "autosaveIdleMs", E.int p.autosaveIdleMs )
        , ( "recentLimit", E.int p.recentLimit )
        , ( "gridSpacing", E.float p.gridSpacing )
        , ( "gridSubdivisions", E.int p.gridSubdivisions )
        , ( "defaultFps", E.object [ ( "numerator", E.int p.defaultFps.numerator ), ( "denominator", E.int p.defaultFps.denominator ) ] )
        , ( "defaultDuration", E.int p.defaultDuration )
        , ( "defaultWidth", E.float p.defaultWidth )
        , ( "defaultHeight", E.float p.defaultHeight )
        , ( "autoKeyDefault", E.bool p.autoKeyDefault )
        , ( "nudge", E.float p.nudge )
        , ( "largeNudge", E.float p.largeNudge )
        , ( "snapTolerance", E.float p.snapTolerance )
        , ( "historyLimit", E.int p.historyLimit )
        , ( "confirmDelete", E.bool p.confirmDelete )
        , ( "showDiagnostics", E.bool p.showDiagnostics )
        , ( "offKeyPolicy", E.string p.offKeyPolicy )
        , ( "timelineSnap", E.bool p.timelineSnap )
        ]


type alias Layout =
    { leftWidth : Float, rightWidth : Float, timelineHeight : Float, leftCollapsed : Bool, rightCollapsed : Bool, timelineCollapsed : Bool }


layoutDecoder : Decoder Layout
layoutDecoder =
    D.map6 Layout
        (D.field "leftWidth" D.float)
        (D.field "rightWidth" D.float)
        (D.field "timelineHeight" D.float)
        (D.oneOf [ D.field "leftCollapsed" D.bool, D.succeed False ])
        (D.oneOf [ D.field "rightCollapsed" D.bool, D.succeed False ])
        (D.oneOf [ D.field "timelineCollapsed" D.bool, D.succeed False ])


layoutEncoder : Model.EditorState -> E.Value
layoutEncoder e =
    E.object
        [ ( "leftWidth", E.float e.leftWidth )
        , ( "rightWidth", E.float e.rightWidth )
        , ( "timelineHeight", E.float e.timelineHeight )
        , ( "leftCollapsed", E.bool e.leftCollapsed )
        , ( "rightCollapsed", E.bool e.rightCollapsed )
        , ( "timelineCollapsed", E.bool e.timelineCollapsed )
        ]
