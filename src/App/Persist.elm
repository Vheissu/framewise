module App.Persist exposing
    ( autosaveRequest
    , deleteRecoveryRequest
    , exportRequest
    , openDocument
    , openFileRequest
    , openStoredRequest
    , recentsRequest
    , requestIdsCmd
    , saveLayoutRequest
    , savePreferencesRequest
    , saveRequest
    , thumbnailSvg
    )

{-| Builds bridge requests for storage, files and exports, and opens
documents into the editor model.
-}

import App.Edit as Edit
import App.Interop as Interop
import App.Model as Model exposing (Model, OpenDocument)
import App.Msg exposing (Msg)
import App.Ports as Ports
import Dict
import DocumentIO.Encode as Encode
import Domain.Document as Document exposing (Document)
import Domain.Evaluate as Evaluate
import Domain.History as History
import Domain.Property
import Domain.Scene
import Domain.Validation as Validation
import Export.Capability as Capability
import Export.Css as Css
import Export.Format as Format exposing (Format(..))
import Export.Portable as Portable
import Export.Smil as Smil
import Export.Static as Static
import Json.Encode as E
import Render.Scene as Render
import Render.SvgDoc as Svg
import Shared.Ids exposing (DocumentId)


requestIdsCmd : Cmd Msg
requestIdsCmd =
    Ports.send (Ports.request "ids" "platform.ids" (E.object [ ( "count", E.int 256 ) ]))


{-| Place a document into the model as an open tab and make it active.
-}
openDocument : Document -> { fileName : Maybe String, fileToken : Maybe String, savedRevision : Maybe Int, revision : Int, isRecovery : Bool } -> Model -> Model
openDocument doc info model =
    let
        firstScene =
            List.head doc.sceneOrder |> Maybe.withDefault ""

        open : OpenDocument
        open =
            { document = doc
            , revision = info.revision
            , savedRevision = info.savedRevision
            , autosavedRevision = Nothing
            , autosaveFailed = Nothing
            , saveStatus = Model.SaveIdle
            , lastSaveWasDownload = False
            , history = History.init model.preferences.historyLimit
            , fileName = info.fileName
            , fileToken = info.fileToken
            , activeSceneId = firstScene
            , sceneViews = Dict.empty
            , assetUrls = Dict.empty
            , validation = Validation.validateDocument doc
            , isRecoveryCopy = info.isRecovery
            }
    in
    { model
        | documents = Dict.insert doc.id open model.documents
        , openOrder =
            if List.member doc.id model.openOrder then
                model.openOrder

            else
                model.openOrder ++ [ doc.id ]
        , activeDocument = Just doc.id
        , editor = Model.defaultEditor model.preferences |> keepLayout model.editor
    }


keepLayout : Model.EditorState -> Model.EditorState -> Model.EditorState
keepLayout old new =
    { new
        | leftWidth = old.leftWidth
        , rightWidth = old.rightWidth
        , timelineHeight = old.timelineHeight
        , leftCollapsed = old.leftCollapsed
        , rightCollapsed = old.rightCollapsed
        , timelineCollapsed = old.timelineCollapsed
        , canvasRect = old.canvasRect
        , timelineRect = old.timelineRect
        , autoKey = old.autoKey
        , showGrid = old.showGrid
        , snapToGrid = old.snapToGrid
        , showRulers = old.showRulers
        , checkerboard = old.checkerboard
    }


{-| A small static SVG of the first scene at frame 0, used for recents and
recovery cards.
-}
thumbnailSvg : Document -> Maybe String
thumbnailSvg doc =
    List.head doc.sceneOrder
        |> Maybe.andThen (\sid -> Evaluate.evaluateScene doc sid 0)
        |> Maybe.map
            (\resolved ->
                let
                    base =
                        Render.defaultOptions
                in
                Svg.toString
                    (Render.renderScene
                        { base | idPrefix = "thumb", includeIds = False, standalone = True }
                        resolved
                    )
            )


autosaveRequest : OpenDocument -> Ports.Request
autosaveRequest open =
    let
        doc =
            open.document

        firstScene =
            List.head (Document.orderedScenes doc)
    in
    { requestId = "autosave-" ++ doc.id ++ "-" ++ String.fromInt open.revision
    , operation = "storage.autosave"
    , documentId = Just doc.id
    , revision = Just open.revision
    , payload =
        E.object
            [ ( "document", Encode.document doc )
            , ( "name", E.string doc.metadata.name )
            , ( "width", E.float (Maybe.map .width firstScene |> Maybe.withDefault 0) )
            , ( "height", E.float (Maybe.map .height firstScene |> Maybe.withDefault 0) )
            , ( "sceneCount", E.int (List.length doc.sceneOrder) )
            , ( "savedRevision", Maybe.map E.int open.savedRevision |> Maybe.withDefault E.null )
            , ( "fileName", Maybe.map E.string open.fileName |> Maybe.withDefault E.null )
            , ( "thumbnail", thumbnailSvg doc |> Maybe.map E.string |> Maybe.withDefault E.null )
            ]
    }


saveRequest : String -> OpenDocument -> Ports.Request
saveRequest mode open =
    let
        doc =
            open.document
    in
    { requestId = "save-" ++ doc.id ++ "-" ++ String.fromInt open.revision ++ "-" ++ mode
    , operation = "file.save"
    , documentId = Just doc.id
    , revision = Just open.revision
    , payload =
        E.object
            [ ( "mode", E.string mode )
            , ( "document", Encode.document doc )
            , ( "fileToken", Maybe.map E.string open.fileToken |> Maybe.withDefault E.null )
            , ( "suggestedName", E.string (sanitizeFileName doc.metadata.name ++ ".framewise") )
            , ( "thumbnail", thumbnailSvg doc |> Maybe.map E.string |> Maybe.withDefault E.null )
            ]
    }


sanitizeFileName : String -> String
sanitizeFileName name =
    let
        cleaned =
            name
                |> String.toList
                |> List.map
                    (\c ->
                        if Char.isAlphaNum c || c == '-' || c == '_' || c == ' ' || c == '.' then
                            c

                        else
                            '-'
                    )
                |> String.fromList
                |> String.trim
    in
    if String.isEmpty cleaned then
        "framewise-document"

    else
        cleaned


openFileRequest : String -> Ports.Request
openFileRequest kind =
    Ports.request ("open-" ++ kind) "file.open" (E.object [ ( "kind", E.string kind ) ])


openStoredRequest : DocumentId -> Bool -> Ports.Request
openStoredRequest docId recovery =
    Ports.request ("load-" ++ docId) "storage.load" (E.object [ ( "documentId", E.string docId ), ( "recovery", E.bool recovery ) ])


recentsRequest : Ports.Request
recentsRequest =
    Ports.request "recents" "storage.recents" E.null


deleteRecoveryRequest : DocumentId -> Bool -> Ports.Request
deleteRecoveryRequest docId recoveryOnly =
    Ports.request ("delete-" ++ docId) "storage.delete" (E.object [ ( "documentId", E.string docId ), ( "recoveryOnly", E.bool recoveryOnly ) ])


savePreferencesRequest : Model.Preferences -> Ports.Request
savePreferencesRequest prefs =
    Ports.request "prefs" "storage.preferences" (Interop.preferencesEncoder prefs)


saveLayoutRequest : Model.EditorState -> Ports.Request
saveLayoutRequest editor =
    Ports.request "layout" "storage.layout" (Interop.layoutEncoder editor)


{-| Build an export request for the active scene (or every scene). The Elm
side produces every text artefact; the adapter rasterises, packages and
downloads.
-}
exportRequest : Model.ExportForm -> Model -> Result String Ports.Request
exportRequest form model =
    case Model.activeDoc model of
        Nothing ->
            Err "No document is open"

        Just open ->
            let
                doc =
                    open.document

                scenes =
                    if form.allScenes then
                        Document.orderedScenes doc

                    else
                        Dict.get open.activeSceneId doc.scenes |> Maybe.map List.singleton |> Maybe.withDefault []

                frame =
                    String.toFloat form.frame |> Maybe.withDefault (Edit.currentFrame model)

                title =
                    if String.isEmpty form.title then
                        Nothing

                    else
                        Just form.title

                description =
                    if String.isEmpty form.description then
                        Nothing

                    else
                        Just form.description

                perScene scene =
                    case form.format of
                        StaticSvg ->
                            Static.export { frame = frame, includeBackground = form.includeBackground, includeIds = True, title = title, description = description } doc scene
                                |> Maybe.map (\svg -> Ok (E.object [ ( "sceneId", E.string scene.id ), ( "name", E.string (sanitizeFileName scene.name) ), ( "svg", E.string svg ) ]))
                                |> Maybe.withDefault (Err "Scene could not be evaluated")

                        AnimatedSvg ->
                            Smil.export { includeBackground = form.includeBackground, title = title, description = description, skipUnsupported = form.skipUnsupported } doc scene
                                |> Result.map (\r -> E.object [ ( "sceneId", E.string scene.id ), ( "name", E.string (sanitizeFileName scene.name) ), ( "svg", E.string r.svg ), ( "report", reportJson r.report ) ])

                        SvgCss ->
                            Css.export { includeBackground = form.includeBackground, title = title, description = description, skipUnsupported = form.skipUnsupported, reducedMotionPause = form.reducedMotionPause } doc scene
                                |> Result.map (\r -> E.object [ ( "sceneId", E.string scene.id ), ( "name", E.string (sanitizeFileName scene.name) ), ( "svg", E.string r.svg ), ( "css", E.string r.css ), ( "report", reportJson r.report ) ])

                        HtmlPlayer ->
                            let
                                report =
                                    Capability.report HtmlPlayer scene
                            in
                            if report.unsupportedCount > 0 && not form.skipUnsupported then
                                Err "Some tracks cannot be represented by the player. Choose Skip Affected Tracks to continue."

                            else
                                Static.export { frame = 0, includeBackground = form.includeBackground, includeIds = True, title = title, description = description } (Document.setScene (Portable.markupScene scene) doc) (Portable.markupScene scene)
                                    |> Maybe.map
                                        (\svg ->
                                            Ok
                                                (E.object
                                                    [ ( "sceneId", E.string scene.id )
                                                    , ( "name", E.string (sanitizeFileName scene.name) )
                                                    , ( "svg", E.string svg )
                                                    , ( "animation", Portable.encode scene )
                                                    , ( "title", E.string (Maybe.withDefault scene.name title) )
                                                    , ( "report", reportJson report )
                                                    ]
                                                )
                                        )
                                    |> Maybe.withDefault (Err "Scene could not be evaluated")

                        PngStill ->
                            Static.export { frame = frame, includeBackground = form.includeBackground, includeIds = False, title = Nothing, description = Nothing } doc scene
                                |> Maybe.map
                                    (\svg ->
                                        Ok
                                            (E.object
                                                [ ( "sceneId", E.string scene.id )
                                                , ( "name", E.string (sanitizeFileName scene.name) )
                                                , ( "svg", E.string svg )
                                                , ( "width", E.float scene.width )
                                                , ( "height", E.float scene.height )
                                                , ( "scale", E.float form.scale )
                                                ]
                                            )
                                    )
                                |> Maybe.withDefault (Err "Scene could not be evaluated")

                        PngSequence ->
                            let
                                start =
                                    String.toInt form.rangeStart |> Maybe.withDefault 0 |> clamp 0 (scene.durationFrames - 1)

                                end =
                                    String.toInt form.rangeEnd |> Maybe.withDefault (scene.durationFrames - 1) |> clamp start (scene.durationFrames - 1)

                                frames =
                                    List.range start end
                                        |> List.filterMap
                                            (\f ->
                                                Static.export { frame = toFloat f, includeBackground = form.includeBackground, includeIds = False, title = Nothing, description = Nothing } doc scene
                                                    |> Maybe.map (\svg -> E.object [ ( "frame", E.int f ), ( "svg", E.string svg ) ])
                                            )
                            in
                            if end - start + 1 > 2000 then
                                Err "PNG sequences are limited to 2000 frames per export"

                            else
                                Ok
                                    (E.object
                                        [ ( "sceneId", E.string scene.id )
                                        , ( "name", E.string (sanitizeFileName scene.name) )
                                        , ( "frames", E.list identity frames )
                                        , ( "width", E.float scene.width )
                                        , ( "height", E.float scene.height )
                                        , ( "scale", E.float form.scale )
                                        , ( "fps", E.object [ ( "numerator", E.int scene.fps.numerator ), ( "denominator", E.int scene.fps.denominator ) ] )
                                        , ( "indexOrigin", E.int (String.toInt form.indexOrigin |> Maybe.withDefault 0) )
                                        , ( "transparent", E.bool (scene.background == Domain.Scene.Transparent || not form.includeBackground) )
                                        ]
                                    )

                        other ->
                            Err (Format.label other ++ " is not available in this build")

                results =
                    List.map perScene scenes
            in
            case List.filterMap errOf results of
                e :: _ ->
                    Err e

                [] ->
                    Ok
                        { requestId = "export-" ++ doc.id ++ "-" ++ String.fromInt open.revision ++ "-" ++ Format.code form.format
                        , operation = "export.run"
                        , documentId = Just doc.id
                        , revision = Just open.revision
                        , payload =
                            E.object
                                [ ( "format", E.string (Format.code form.format) )
                                , ( "documentName", E.string (sanitizeFileName doc.metadata.name) )
                                , ( "items", E.list identity (List.filterMap okOf results) )
                                , ( "appVersion", E.string model.version )
                                ]
                        }


errOf : Result String a -> Maybe String
errOf r =
    case r of
        Err e ->
            Just e

        Ok _ ->
            Nothing


okOf : Result String a -> Maybe a
okOf r =
    case r of
        Ok v ->
            Just v

        Err _ ->
            Nothing


reportJson : Capability.Report -> E.Value
reportJson report =
    E.object
        [ ( "exact", E.int report.exactCount )
        , ( "baked", E.int report.bakedCount )
        , ( "unsupported", E.int report.unsupportedCount )
        , ( "items"
          , E.list
                (\i ->
                    E.object
                        [ ( "nodeId", E.string i.nodeId )
                        , ( "nodeName", E.string i.nodeName )
                        , ( "property", Maybe.map (Domain.Property.pathToCode >> E.string) i.property |> Maybe.withDefault E.null )
                        , ( "status", E.string (Capability.statusLabel i.status) )
                        , ( "message"
                          , E.string
                                (case i.status of
                                    Capability.Exact ->
                                        ""

                                    Capability.Baked m ->
                                        m

                                    Capability.Unsupported m ->
                                        m
                                )
                          )
                        ]
                )
                report.items
          )
        ]
