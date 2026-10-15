module App.Update exposing (init, subscriptions, update)

import App.Canvas as Canvas
import App.Commands as Commands
import App.Edit as Edit exposing (Update, pure)
import App.Examples as Examples
import App.Fields as Fields
import App.Interop as Interop
import App.Model as Model exposing (Dialog(..), Gesture(..), Model, Tool(..))
import App.Msg exposing (KeyEvent, Msg(..))
import App.Ops as Ops
import App.Persist as Persist
import App.Ports as Ports
import App.Presets as Presets
import App.Route as Route
import App.Timeline as Timeline
import Browser
import Browser.Events
import Browser.Navigation as Nav
import Dict
import DocumentIO.Decode as Decode
import DocumentIO.Encode
import Domain.Color as Color
import Domain.Document as Document exposing (Document)
import Domain.Easing
import Domain.Fps as Fps
import Domain.History as History
import Domain.Keyframe as Keyframe
import Domain.Matrix
import Domain.Node as Node exposing (NodeGeometry(..))
import Domain.Paint as Paint
import Domain.Path
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Domain.Transform
import Domain.Validation
import Export.Format as Format
import Export.Static
import Json.Decode as D
import Json.Encode as E
import Process
import Set
import Shared.Ids exposing (DocumentId, NodeId)
import Task
import Time
import Url exposing (Url)



-- INIT


init : D.Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flagsValue url key =
    let
        flags =
            case D.decodeValue Interop.flagsDecoder flagsValue of
                Ok f ->
                    f

                Err _ ->
                    { basePath = "/", isMac = False, ids = [], capabilities = Model.defaultCapabilities, preferences = Nothing, recents = [], recoveries = [], now = 0, reducedMotion = False, version = "0.0.0", layout = Nothing }

        prefs =
            flags.preferences
                |> Maybe.andThen (D.decodeValue Interop.preferencesDecoder >> Result.toMaybe)
                |> Maybe.withDefault Model.defaultPreferences

        editor0 =
            Model.defaultEditor prefs

        editor =
            case flags.layout |> Maybe.andThen (D.decodeValue Interop.layoutDecoder >> Result.toMaybe) of
                Just l ->
                    { editor0 | leftWidth = l.leftWidth, rightWidth = l.rightWidth, timelineHeight = l.timelineHeight, leftCollapsed = l.leftCollapsed, rightCollapsed = l.rightCollapsed, timelineCollapsed = l.timelineCollapsed }

                Nothing ->
                    editor0

        route =
            Route.fromUrl flags.basePath url

        model =
            { key = key
            , route = route
            , basePath = flags.basePath
            , isMac = flags.isMac
            , version = flags.version
            , capabilities = flags.capabilities
            , reducedMotion = flags.reducedMotion
            , documents = Dict.empty
            , openOrder = []
            , activeDocument = Nothing
            , editor = editor
            , preferences = prefs
            , ids = flags.ids
            , idRequestPending = False
            , idCounter = 1
            , recents = flags.recents
            , recoveries = flags.recoveries
            , dialog = NoDialog
            , openMenu = Nothing
            , menuIndex = 0
            , palette = Nothing
            , contextMenu = Nothing
            , picker = Nothing
            , fieldDrafts = Dict.empty
            , toasts = []
            , toastSeq = 1
            , exportJobs = []
            , now = Time.millisToPosix flags.now
            , liveAnnouncement = ""
            , internalClipboard = Nothing
            , pendingRequests = Dict.empty
            , offlineReady = False
            , pendingExampleOpen = Nothing
            , dragOverlay = False
            , tabConflicts = []
            }
    in
    ( model, Cmd.batch [ routeEffect route model, Task.perform ClockNow Time.now ] )


routeEffect : Model.Route -> Model -> Cmd Msg
routeEffect route model =
    case route of
        Model.EditorRoute id ->
            if Dict.member id model.documents then
                Cmd.none

            else
                Ports.send (Persist.openStoredRequest id False)

        Model.PreviewRoute id _ ->
            if Dict.member id model.documents then
                Cmd.none

            else
                Ports.send (Persist.openStoredRequest id False)

        _ ->
            Cmd.none



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        gestureSubs =
            case model.editor.gesture of
                NoGesture ->
                    []

                _ ->
                    [ Browser.Events.onMouseMove (D.map3 WindowPointerMove (D.field "clientX" D.float) (D.field "clientY" D.float) (D.field "shiftKey" D.bool))
                    , Browser.Events.onMouseUp (D.map2 WindowPointerUp (D.field "clientX" D.float) (D.field "clientY" D.float))
                    ]

        playbackSub =
            if model.editor.playback.playing then
                [ Browser.Events.onAnimationFrame Tick ]

            else
                []

        toastSub =
            if List.isEmpty model.toasts then
                []

            else
                [ Time.every 4500 (\_ -> ExpireToasts) ]
    in
    Sub.batch
        ([ Ports.fromJs FromJs
         , Browser.Events.onKeyDown (D.map KeyDown keyDecoder)
         , Browser.Events.onKeyUp (D.map KeyUp keyDecoder)
         , Time.every 30000 ClockNow
         ]
            ++ gestureSubs
            ++ playbackSub
            ++ toastSub
        )


keyDecoder : D.Decoder KeyEvent
keyDecoder =
    D.map8 KeyEvent
        (D.field "key" D.string)
        (D.oneOf [ D.field "code" D.string, D.succeed "" ])
        (D.field "ctrlKey" D.bool)
        (D.field "metaKey" D.bool)
        (D.field "shiftKey" D.bool)
        (D.field "altKey" D.bool)
        (D.oneOf
            [ D.at [ "target", "tagName" ] D.string
                |> D.andThen
                    (\tag ->
                        if List.member (String.toUpper tag) [ "INPUT", "TEXTAREA", "SELECT" ] then
                            D.succeed True

                        else
                            D.oneOf [ D.at [ "target", "isContentEditable" ] D.bool, D.succeed False ]
                    )
            , D.succeed False
            ]
        )
        (D.oneOf [ D.field "repeat" D.bool, D.succeed False ])



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            pure model

        LinkClicked request ->
            case request of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            let
                route =
                    Route.fromUrl model.basePath url

                m2 =
                    { model | route = route }

                withActive =
                    case route of
                        Model.EditorRoute id ->
                            if Dict.member id m2.documents then
                                { m2 | activeDocument = Just id }

                            else
                                m2

                        Model.PreviewRoute id sceneId ->
                            if Dict.member id m2.documents then
                                { m2 | activeDocument = Just id }
                                    |> Edit.mapActiveDoc (\d -> { d | activeSceneId = sceneId })

                            else
                                m2

                        _ ->
                            Edit.endPlayback m2
            in
            ( withActive, routeEffect route withActive )

        FromJs value ->
            handleFromJs value model

        Tick now ->
            pure (Timeline.tick now { model | now = now })

        ClockNow now ->
            pure { model | now = now }

        RunCommand id ->
            runCommand id model

        GoWelcome ->
            ( Edit.endPlayback model, Nav.pushUrl model.key (Route.toPath model.basePath Model.Welcome) )

        OpenDocumentTab id ->
            ( { model | activeDocument = Just id }, Nav.pushUrl model.key (Route.toPath model.basePath (Model.EditorRoute id)) )

        CloseDocument id ->
            case Dict.get id model.documents of
                Just open ->
                    if Just open.revision /= open.savedRevision && open.revision /= 0 && open.autosavedRevision /= Just open.revision then
                        pure { model | dialog = ConfirmDialog { title = "Close " ++ open.document.metadata.name ++ "?", body = "This document has changes that are not saved to a file. Framewise keeps a local autosave you can recover from the welcome screen, but unsaved changes since the last autosave will be lost.", confirmLabel = "Close", onConfirm = "close:" ++ id } }

                    else
                        closeDocument id model

                Nothing ->
                    pure model

        ConfirmCloseDocument id ->
            closeDocument id model

        OpenExample id ->
            openExample id model

        OpenRecent id ->
            if Dict.member id model.documents then
                ( { model | activeDocument = Just id }, Nav.pushUrl model.key (Route.toPath model.basePath (Model.EditorRoute id)) )

            else
                ( model, Ports.send (Persist.openStoredRequest id False) )

        RemoveRecent id ->
            ( { model | recents = List.filter (\r -> r.documentId /= id) model.recents }, Ports.send (Persist.deleteRecoveryRequest id False) )

        OpenRecovery id ->
            ( model, Ports.send (Persist.openStoredRequest id True) )

        DiscardRecovery id ->
            pure { model | dialog = ConfirmDialog { title = "Discard recovery copy?", body = "The autosaved checkpoint will be deleted. Files you saved yourself are not affected.", confirmLabel = "Discard", onConfirm = "discardRecovery:" ++ id } }

        DownloadRecovery id ->
            ( model, Ports.send (Ports.request ("dl-" ++ id) "storage.downloadRecovery" (E.object [ ( "documentId", E.string id ) ])) )

        SetDialog dialog ->
            pure { model | dialog = dialog, openMenu = Nothing, contextMenu = Nothing, palette = Nothing }

        CloseDialog ->
            pure { model | dialog = NoDialog }

        DocFormChanged f ->
            case model.dialog of
                NewDocumentDialog form ->
                    pure { model | dialog = NewDocumentDialog (f form) }

                _ ->
                    pure model

        SubmitNewDocument ->
            case model.dialog of
                NewDocumentDialog form ->
                    createDocument form model

                _ ->
                    pure model

        NewDocumentFromPreset presetId ->
            let
                form =
                    applyPreset presetId (Model.defaultDocForm model.preferences)
            in
            pure { model | dialog = NewDocumentDialog form }

        SceneFormChanged f ->
            case model.dialog of
                SceneSettingsDialog form ->
                    pure { model | dialog = SceneSettingsDialog (f form) }

                FpsRetimeDialog form ->
                    pure { model | dialog = FpsRetimeDialog (f form) }

                _ ->
                    pure model

        SubmitSceneSettings ->
            case model.dialog of
                SceneSettingsDialog form ->
                    applySceneSettings form model

                FpsRetimeDialog form ->
                    applySceneSettings form model

                _ ->
                    pure model

        DocSettingsChanged field value ->
            case model.dialog of
                DocumentSettingsDialog form ->
                    pure
                        { model
                            | dialog =
                                DocumentSettingsDialog
                                    (if field == "name" then
                                        { form | name = value }

                                     else
                                        { form | description = value }
                                    )
                        }

                _ ->
                    pure model

        SubmitDocumentSettings ->
            case model.dialog of
                DocumentSettingsDialog form ->
                    Edit.commit "Document settings"
                        (\doc ->
                            let
                                meta =
                                    doc.metadata
                            in
                            { doc | metadata = { meta | name = String.trim form.name, description = form.description } }
                        )
                        { model | dialog = NoDialog }

                _ ->
                    pure model

        ToggleMenu name ->
            pure
                { model
                    | openMenu =
                        if model.openMenu == Just name then
                            Nothing

                        else
                            Just name
                    , menuIndex = 0
                    , contextMenu = Nothing
                }

        HoverMenu name ->
            case model.openMenu of
                Just _ ->
                    pure { model | openMenu = Just name, menuIndex = 0 }

                Nothing ->
                    pure model

        CloseMenus ->
            pure { model | openMenu = Nothing, contextMenu = Nothing }

        OpenPalette ->
            ( { model | palette = Just { query = "", index = 0 }, openMenu = Nothing, contextMenu = Nothing }, focusElement "palette-input" )

        PaletteInput q ->
            pure { model | palette = Maybe.map (\p -> { p | query = q, index = 0 }) model.palette }

        PaletteMove delta ->
            pure { model | palette = Maybe.map (\p -> { p | index = max 0 (p.index + delta) }) model.palette }

        PaletteRun ->
            case model.palette of
                Just p ->
                    case List.drop p.index (paletteResults p.query model) |> List.head of
                        Just cmd ->
                            runCommandMsg cmd { model | palette = Nothing }

                        Nothing ->
                            pure { model | palette = Nothing }

                Nothing ->
                    pure model

        ClosePalette ->
            pure { model | palette = Nothing }

        OpenContextMenu x y target ->
            pure { model | contextMenu = Just { x = x, y = y, target = target }, openMenu = Nothing }

        CloseContextMenu ->
            pure { model | contextMenu = Nothing }

        DismissToast id ->
            pure { model | toasts = List.filter (\t -> t.id /= id) model.toasts }

        ExpireToasts ->
            pure { model | toasts = List.drop 1 model.toasts }

        SetLeftTab tab ->
            updateEditor (\e -> { e | leftTab = tab, leftCollapsed = False }) model

        ToggleSection id ->
            updateEditor
                (\e ->
                    { e
                        | collapsedSections =
                            if Set.member id e.collapsedSections then
                                Set.remove id e.collapsedSections

                            else
                                Set.insert id e.collapsedSections
                    }
                )
                model

        SetPrefTab tab ->
            case model.dialog of
                PreferencesDialog _ q ->
                    pure { model | dialog = PreferencesDialog tab q }

                _ ->
                    pure { model | dialog = PreferencesDialog tab "" }

        PrefSearch q ->
            case model.dialog of
                PreferencesDialog tab _ ->
                    pure { model | dialog = PreferencesDialog tab q }

                _ ->
                    pure model

        PreferenceChanged f ->
            let
                prefs =
                    f model.preferences
            in
            ( { model | preferences = prefs }, Ports.send (Persist.savePreferencesRequest prefs) )

        ResetPreferences ->
            ( { model | preferences = Model.defaultPreferences }, Ports.send (Persist.savePreferencesRequest Model.defaultPreferences) )

        ResetWorkspace ->
            let
                d =
                    Model.defaultEditor model.preferences

                e =
                    model.editor

                reset =
                    { e | leftWidth = d.leftWidth, rightWidth = d.rightWidth, timelineHeight = d.timelineHeight, leftCollapsed = False, rightCollapsed = False, timelineCollapsed = False }
            in
            ( { model | editor = reset }, Ports.send (Persist.saveLayoutRequest reset) )

        ClearStorage category ->
            pure { model | dialog = ConfirmDialog { title = "Clear " ++ category ++ "?", body = "This removes " ++ category ++ " from this browser's storage. Files you downloaded or saved yourself are not affected.", confirmLabel = "Clear", onConfirm = "clearStorage:" ++ category } }

        RequestPersistentStorage ->
            ( model, Ports.send (Ports.request "persist" "storage.persist" E.null) )

        SetDocsPage page ->
            pure { model | dialog = DocsDialog page "" }

        DocsSearch q ->
            case model.dialog of
                DocsDialog page _ ->
                    pure { model | dialog = DocsDialog page q }

                _ ->
                    pure model

        ShortcutSearch q ->
            pure { model | dialog = ShortcutsDialog q }

        ConfirmAccepted action ->
            confirmAction action { model | dialog = NoDialog }

        ToggleCollapse which ->
            let
                e =
                    model.editor

                updated =
                    case which of
                        "left" ->
                            { e | leftCollapsed = not e.leftCollapsed }

                        "right" ->
                            { e | rightCollapsed = not e.rightCollapsed }

                        _ ->
                            { e | timelineCollapsed = not e.timelineCollapsed }
            in
            ( { model | editor = updated }, Ports.send (Persist.saveLayoutRequest updated) )

        -- TOOLS & CANVAS
        ChooseTool tool ->
            let
                e =
                    model.editor

                ( m2, cmd ) =
                    if e.penDraft /= Nothing && tool /= PenTool && tool /= MotionPathTool then
                        Canvas.finishPen False model

                    else
                        pure model

                e2 =
                    m2.editor
            in
            ( { m2 | editor = { e2 | tool = tool, focus = Model.CanvasFocus, editingText = Nothing } }, cmd )

        CanvasPointerDown ev ->
            Canvas.pointerDown ev { model | fieldDrafts = Dict.empty }

        CanvasPointerMove ev ->
            case model.editor.gesture of
                NoGesture ->
                    pure (setHoverFromEvent ev model)

                _ ->
                    Canvas.pointerMove ev.clientX ev.clientY ev.shift model

        CanvasPointerUp ev ->
            Canvas.pointerUp ev.clientX ev.clientY model

        CanvasDoubleClick ev ->
            Canvas.doubleClick ev model

        CanvasWheel ev ->
            Canvas.wheel ev model

        CanvasRect rect ->
            let
                e =
                    model.editor

                m2 =
                    { model | editor = { e | canvasRect = rect } }

                view =
                    Model.activeView m2
            in
            if not view.fitted && rect.width > 0 && Model.activeScene m2 /= Nothing then
                pure (Canvas.zoomToFit False m2)

            else
                pure m2

        TimelineRect rect ->
            let
                e =
                    model.editor

                m2 =
                    { model | editor = { e | timelineRect = rect } }

                view =
                    Model.activeView m2
            in
            case ( view.timelineFitted, Model.activeScene m2 ) of
                ( False, Just scene ) ->
                    if rect.width > 50 then
                        pure (Edit.mapActiveView (\v -> { v | timelineFitted = True, timelinePixelsPerFrame = clamp 1 120 ((rect.width - 2 * Timeline.timeOrigin - 8) / toFloat (max 1 scene.durationFrames)) }) m2)

                    else
                        pure m2

                _ ->
                    pure m2

        WindowPointerMove x y shift ->
            case model.editor.gesture of
                ScrubPlayhead ->
                    Timeline.pointerMove x model

                DragKeys _ ->
                    Timeline.pointerMove x model

                DragSplitter g ->
                    dragSplitter g x y model

                _ ->
                    Canvas.pointerMove x y shift model

        WindowPointerUp x y ->
            case model.editor.gesture of
                ScrubPlayhead ->
                    Timeline.pointerUp model

                DragKeys _ ->
                    Timeline.pointerUp model

                DragSplitter _ ->
                    let
                        e =
                            model.editor

                        m2 =
                            { model | editor = { e | gesture = NoGesture } }
                    in
                    ( m2, Ports.send (Persist.saveLayoutRequest m2.editor) )

                _ ->
                    Canvas.pointerUp x y model

        KeyDown ev ->
            handleKeyDown ev model

        KeyUp ev ->
            if ev.key == " " then
                updateEditor (\e -> { e | spaceHeld = False }) model

            else
                pure model

        SetFocusContext ctx ->
            updateEditor (\e -> { e | focus = ctx }) model

        ZoomTo z ->
            let
                rect =
                    model.editor.canvasRect
            in
            pure (Canvas.zoomAround { x = rect.width / 2, y = rect.height / 2 } z model)

        ZoomBy factor ->
            let
                rect =
                    model.editor.canvasRect
            in
            pure (Canvas.zoomAround { x = rect.width / 2, y = rect.height / 2 } ((Model.activeView model).zoom * factor) model)

        FitScene ->
            pure (Canvas.zoomToFit False model)

        FitSelection ->
            pure (Canvas.zoomToFit True model)

        ToggleEditorFlag flag ->
            updateEditor
                (\e ->
                    case flag of
                        "grid" ->
                            { e | showGrid = not e.showGrid }

                        "snapGrid" ->
                            { e | snapToGrid = not e.snapToGrid }

                        "snapObjects" ->
                            { e | snapToObjects = not e.snapToObjects }

                        "snapArtboard" ->
                            { e | snapToArtboard = not e.snapToArtboard }

                        "rulers" ->
                            { e | showRulers = not e.showRulers }

                        "guides" ->
                            { e | showGuides = not e.showGuides }

                        "outline" ->
                            { e | outlineMode = not e.outlineMode }

                        "motionPaths" ->
                            { e | showMotionPaths = not e.showMotionPaths }

                        "checker" ->
                            { e | checkerboard = not e.checkerboard }

                        "allProps" ->
                            { e | showAllProperties = not e.showAllProperties }

                        _ ->
                            e
                )
                model

        SetHover h ->
            updateEditor (\e -> { e | hover = h }) model

        FinishPen ->
            Canvas.finishPen False model

        CancelPen ->
            updateEditor (\e -> { e | penDraft = Nothing, gesture = NoGesture }) model

        ExitIsolation ->
            updateEditor (\e -> { e | isolation = Nothing }) model

        EnterIsolation id ->
            updateEditor (\e -> { e | isolation = Just id }) model

        -- SELECTION / LAYERS
        SelectNodes ids additive ->
            let
                current =
                    Edit.selection model

                newSel =
                    if additive then
                        List.foldl
                            (\id acc ->
                                if List.member id acc then
                                    List.filter ((/=) id) acc

                                else
                                    acc ++ [ id ]
                            )
                            current
                            ids

                    else
                        ids

                e =
                    model.editor
            in
            pure (Edit.setSelection newSel { model | editor = { e | focus = Model.LayersFocus } } |> Edit.focusAnnounce (announceSelection newSel model))

        SelectAll ->
            case Model.activeScene model of
                Just scene ->
                    pure (Edit.setSelection (Scene.childrenOf model.editor.isolation scene |> List.filter (\id -> Dict.get id scene.nodes |> Maybe.map (\n -> not n.locked && not n.hidden) |> Maybe.withDefault False)) model)

                Nothing ->
                    pure model

        Deselect ->
            pure (Edit.setSelection [] model)

        InvertSelection ->
            case Model.activeScene model of
                Just scene ->
                    let
                        all =
                            Scene.childrenOf model.editor.isolation scene

                        sel =
                            Edit.selection model
                    in
                    pure (Edit.setSelection (List.filter (\id -> not (List.member id sel)) all) model)

                Nothing ->
                    pure model

        ToggleExpanded id ->
            pure
                (Edit.mapActiveView
                    (\v ->
                        { v
                            | expanded =
                                if Set.member id v.expanded then
                                    Set.remove id v.expanded

                                else
                                    Set.insert id v.expanded
                        }
                    )
                    model
                )

        SetHidden id hidden ->
            commitScene
                (if hidden then
                    "Hide"

                 else
                    "Show"
                )
                (Scene.updateNode id (\n -> { n | hidden = hidden }))
                model

        SetLocked id locked ->
            commitScene
                (if locked then
                    "Lock"

                 else
                    "Unlock"
                )
                (Scene.updateNode id (\n -> { n | locked = locked }))
                model

        StartRename id ->
            let
                name =
                    Model.activeScene model |> Maybe.andThen (\s -> Dict.get id s.nodes) |> Maybe.map .name |> Maybe.withDefault ""
            in
            updateEditor (\e -> { e | renamingNode = Just id, renameDraft = name }) model
                |> Tuple.mapSecond (\c -> Cmd.batch [ c, focusElement "layer-rename-input" ])

        RenameInput s ->
            updateEditor (\e -> { e | renameDraft = s }) model

        CommitRename ->
            case model.editor.renamingNode of
                Just id ->
                    let
                        name =
                            String.trim model.editor.renameDraft

                        e =
                            model.editor

                        m2 =
                            { model | editor = { e | renamingNode = Nothing } }
                    in
                    if String.isEmpty name then
                        pure m2

                    else
                        commitScene "Rename" (Scene.updateNode id (\n -> { n | name = name })) m2

                Nothing ->
                    pure model

        CancelRename ->
            updateEditor (\e -> { e | renamingNode = Nothing }) model

        LayerFilter s ->
            updateEditor (\e -> { e | layerFilter = s }) model

        LayerDragStart id ->
            updateEditor (\e -> { e | gesture = DragLayer { nodeId = id } }) model

        LayerDragOver parent index ->
            updateEditor (\e -> { e | dropTarget = Just ( parent, index ) }) model

        LayerDrop ->
            case ( model.editor.gesture, model.editor.dropTarget, Model.activeScene model ) of
                ( DragLayer g, Just ( parent, index ), Just scene ) ->
                    let
                        targetLocked =
                            parent |> Maybe.andThen (\pid -> Dict.get pid scene.nodes) |> Maybe.map .locked |> Maybe.withDefault False

                        e =
                            model.editor

                        cleared =
                            { model | editor = { e | gesture = NoGesture, dropTarget = Nothing } }

                        moving =
                            if List.member g.nodeId (Edit.selection model) then
                                Edit.selection model

                            else
                                [ g.nodeId ]
                    in
                    if targetLocked then
                        pure (Edit.toast "warning" "Cannot drop into a locked group" cleared)

                    else
                        commitScene "Move layer"
                            (\s -> List.foldl (\( i, id ) acc -> Scene.moveNode id parent (index + i) acc) s (List.indexedMap Tuple.pair (orderBySiblings s moving)))
                            cleared

                _ ->
                    updateEditor (\e -> { e | gesture = NoGesture, dropTarget = Nothing }) model

        LayerDragEnd ->
            updateEditor (\e -> { e | gesture = NoGesture, dropTarget = Nothing }) model

        MoveSelection delta ->
            Ops.reorderSelection
                (if delta > 0 then
                    "up"

                 else
                    "down"
                )
                model

        ReorderSelection how ->
            Ops.reorderSelection how model

        GroupSelection clip ->
            Ops.groupSelection clip model

        UngroupSelection ->
            Ops.ungroupSelection model

        DeleteSelection ->
            if model.preferences.confirmDelete && not (List.isEmpty (Edit.selection model)) then
                pure { model | dialog = ConfirmDialog { title = "Delete selection?", body = "The selected layers and their animation will be removed. You can undo this.", confirmLabel = "Delete", onConfirm = "delete" } }

            else
                Ops.deleteSelection model

        DuplicateSelection ->
            Ops.duplicateSelection model

        ConvertToPath ->
            Ops.convertToPath model

        ToggleClosedPath ->
            Ops.toggleClosedPath model

        ReversePath ->
            Ops.reversePath model

        SetAlign how ->
            Ops.alignSelection how model

        Distribute axis ->
            Ops.distributeSelection axis model

        FlipSelection h ->
            Ops.flipSelection h model

        ResetTransform ->
            Ops.resetTransform model

        SelectParent ->
            case Model.activeScene model of
                Just scene ->
                    let
                        parents =
                            Edit.selection model |> List.filterMap (\id -> Dict.get id scene.nodes |> Maybe.andThen .parentId)
                    in
                    if List.isEmpty parents then
                        pure model

                    else
                        pure (Edit.setSelection (dedupe parents) model)

                Nothing ->
                    pure model

        SelectChildren ->
            case Model.activeScene model of
                Just scene ->
                    let
                        children =
                            Edit.selection model |> List.concatMap (\id -> Dict.get id scene.nodes |> Maybe.map .childIds |> Maybe.withDefault [])
                    in
                    if List.isEmpty children then
                        pure model

                    else
                        pure (Edit.setSelection children model)

                Nothing ->
                    pure model

        SelectScene sceneId ->
            let
                m2 =
                    Edit.endPlayback model |> Edit.mapActiveDoc (\d -> { d | activeSceneId = sceneId })

                e =
                    m2.editor

                m3 =
                    { m2 | editor = { e | selectedKeys = [], isolation = Nothing, gesture = NoGesture } }
            in
            if (Model.activeView m3).fitted then
                pure m3

            else
                pure (Canvas.zoomToFit False m3)

        AddScene ->
            case Model.activeDoc model of
                Just open ->
                    let
                        ( id, m2 ) =
                            Edit.nextId model

                        template =
                            Dict.get open.activeSceneId open.document.scenes

                        count =
                            Dict.size open.document.scenes + 1

                        scene =
                            case template of
                                Just t ->
                                    Scene.new id ("Scene " ++ String.fromInt count) t.width t.height t.fps t.durationFrames t.background

                                Nothing ->
                                    Scene.new id ("Scene " ++ String.fromInt count) model.preferences.defaultWidth model.preferences.defaultHeight model.preferences.defaultFps model.preferences.defaultDuration Scene.Transparent

                        ( m3, cmd ) =
                            Edit.commit "Add scene" (Document.addScene scene) m2
                    in
                    ( Edit.mapActiveDoc (\d -> { d | activeSceneId = id }) m3, cmd )

                Nothing ->
                    pure model

        DuplicateScene sceneId ->
            case Model.activeDoc model of
                Just open ->
                    let
                        ( ids, m2 ) =
                            Edit.nextIds 1 model

                        newId =
                            List.head ids |> Maybe.withDefault "scene"

                        suffix =
                            String.right 6 newId

                        idFor old =
                            old ++ "-" ++ suffix

                        ( m3, cmd ) =
                            Edit.commit "Duplicate scene" (Document.duplicateScene sceneId newId idFor) m2
                    in
                    ( Edit.mapActiveDoc (\d -> { d | activeSceneId = newId }) m3, cmd )

                Nothing ->
                    pure model

        DeleteScene sceneId ->
            case Model.activeDoc model of
                Just open ->
                    if List.length open.document.sceneOrder <= 1 then
                        pure (Edit.toast "warning" "A document needs at least one scene" model)

                    else
                        pure { model | dialog = ConfirmDialog { title = "Delete scene?", body = "The scene, its layers and animation will be removed. You can undo this.", confirmLabel = "Delete scene", onConfirm = "deleteScene:" ++ sceneId } }

                Nothing ->
                    pure model

        ReorderScene sceneId delta ->
            Edit.commit "Reorder scenes" (Document.reorderScene sceneId delta) model

        -- INSPECTOR
        FieldInput id text ->
            pure { model | fieldDrafts = Dict.insert id text model.fieldDrafts }

        FieldCommit id ->
            case Dict.get id model.fieldDrafts of
                Just text ->
                    Fields.commit id text model

                Nothing ->
                    pure model

        FieldCancel id ->
            pure { model | fieldDrafts = Dict.remove id model.fieldDrafts }

        FieldStep id delta ->
            Fields.step id delta { model | fieldDrafts = Dict.remove id model.fieldDrafts }

        SetNodeProperty id property value ->
            commitSceneWith "Edit" (\m s -> Tuple.first (Edit.setAnimatedProperty m id property value s)) model

        SetNodeFill id enabled ->
            commitScene "Fill"
                (Scene.updateNode id
                    (\n ->
                        { n
                            | fill =
                                if enabled then
                                    Paint.Solid (Color.rgba 0.36 0.56 0.92 1)

                                else
                                    Paint.NoPaint
                        }
                    )
                )
                model

        SetNodeStroke id enabled ->
            commitScene "Stroke"
                (Scene.updateNode id
                    (\n ->
                        let
                            s =
                                n.stroke
                        in
                        { n
                            | stroke =
                                if enabled then
                                    { s | paint = Paint.Solid (Color.rgba 0.12 0.12 0.14 1) }

                                else
                                    { s | paint = Paint.NoPaint }
                        }
                    )
                )
                model

        SetStrokeOption id option value ->
            commitScene "Stroke style"
                (Scene.updateNode id
                    (\n ->
                        let
                            s =
                                n.stroke
                        in
                        case option of
                            "cap" ->
                                { n | stroke = { s | cap = Paint.capFromCode value |> Maybe.withDefault s.cap } }

                            "join" ->
                                { n | stroke = { s | join = Paint.joinFromCode value |> Maybe.withDefault s.join } }

                            _ ->
                                n
                    )
                )
                model

        SetTextOption id option value ->
            commitScene "Text style"
                (Scene.updateNode id
                    (\n ->
                        case n.geometry of
                            Text t ->
                                case option of
                                    "align" ->
                                        { n | geometry = Text { t | align = Node.alignFromCode value |> Maybe.withDefault t.align } }

                                    "weight" ->
                                        { n | geometry = Text { t | fontWeight = String.toInt value |> Maybe.withDefault t.fontWeight } }

                                    "italic" ->
                                        { n | geometry = Text { t | italic = value == "true" } }

                                    "family" ->
                                        { n | geometry = Text { t | fontFamily = value } }

                                    _ ->
                                        n

                            _ ->
                                n
                    )
                )
                model

        SetEffect id action ->
            commitScene "Effects"
                (Scene.updateNode id
                    (\n ->
                        case action of
                            "addBlur" ->
                                if List.any isBlur n.effects then
                                    n

                                else
                                    { n | effects = n.effects ++ [ Node.Blur 4 ] }

                            "addShadow" ->
                                { n | effects = n.effects ++ [ Node.DropShadow { offset = { x = 2, y = 4 }, blur = 4, color = Color.rgba 0 0 0 0.4 } ] }

                            "removeBlur" ->
                                { n | effects = List.filter (not << isBlur) n.effects }

                            "removeShadow" ->
                                { n | effects = List.filter isBlur n.effects }

                            _ ->
                                n
                    )
                )
                model

        SetSceneBackground transparent ->
            commitScene "Background"
                (\s ->
                    { s
                        | background =
                            if transparent then
                                Scene.Transparent

                            else
                                Scene.SolidBackground Color.white
                    }
                )
                model

        SetSceneOption option value ->
            commitScene "Scene"
                (\s ->
                    case option of
                        "name" ->
                            { s | name = value }

                        "playbackMode" ->
                            { s | playbackMode = Scene.playbackModeFromCode value |> Maybe.withDefault s.playbackMode }

                        "description" ->
                            { s | description = value }

                        _ ->
                            s
                )
                model

        OpenPicker target initial x y ->
            pure { model | picker = Just { target = target, initial = initial, current = initial, hexDraft = Color.toHex initial, anchor = { x = x, y = y } } }

        PickerChange color ->
            case model.picker of
                Just p ->
                    applyPickerColor color { model | picker = Just { p | current = color, hexDraft = Color.toHex color } }

                Nothing ->
                    pure model

        PickerHex text ->
            case model.picker of
                Just p ->
                    case Color.fromHex text of
                        Just c ->
                            applyPickerColor c { model | picker = Just { p | current = c, hexDraft = text } }

                        Nothing ->
                            pure { model | picker = Just { p | hexDraft = text } }

                Nothing ->
                    pure model

        PickerConfirm ->
            pure { model | picker = Nothing }

        PickerCancel ->
            case model.picker of
                Just p ->
                    let
                        ( m2, cmd ) =
                            applyPickerColor p.initial model
                    in
                    ( { m2 | picker = Nothing }, cmd )

                Nothing ->
                    pure model

        SetMotionOrient id orient ->
            commitScene "Motion orientation" (Scene.updateNode id (\n -> { n | motion = Maybe.map (\m -> { m | orient = orient }) n.motion })) model

        DetachMotionPath id ->
            commitScene "Detach motion path"
                (\s ->
                    let
                        pathId =
                            Dict.get id s.nodes |> Maybe.andThen .motion |> Maybe.map .pathId
                    in
                    { s
                        | motionPaths =
                            case pathId of
                                Just pid ->
                                    Dict.remove pid s.motionPaths

                                Nothing ->
                                    s.motionPaths
                        , tracks = Dict.filter (\_ t -> not (t.target.nodeId == id && t.target.property == MotionProgress)) s.tracks
                    }
                        |> Scene.updateNode id (\n -> { n | motion = Nothing })
                )
                model

        CreateMotionPathFromSelection ->
            createMotionPathFromSelection model

        -- TIMELINE
        SetPlayhead f ->
            pure (Timeline.setPlayhead f (Edit.endPlayback model))

        StepFrame delta ->
            pure (Timeline.setPlayhead (toFloat (round (Edit.currentFrame model)) + toFloat delta) (Edit.endPlayback model))

        JumpToKey direction ->
            jumpToKey direction model

        TogglePlay ->
            pure (Timeline.togglePlay model)

        StopPlayback ->
            case Model.activeScene model of
                Just scene ->
                    pure (Timeline.setPlayhead (toFloat (Tuple.first (Timeline.playbackRange scene))) (Edit.endPlayback model))

                Nothing ->
                    pure model

        SetSpeed s ->
            updatePlayback (\pb -> { pb | speed = clamp 0.1 8 s, startTime = -1, startFrame = Edit.currentFrame model }) model

        ToggleReverse ->
            updatePlayback (\pb -> { pb | reverse = not pb.reverse, startTime = -1, startFrame = Edit.currentFrame model }) model

        SetLoopMode mode ->
            commitScene "Loop mode" (\s -> { s | playbackMode = mode }) model

        ToggleAutoKey ->
            updateEditor (\e -> { e | autoKey = not e.autoKey }) model

        ToggleKeyAt id property ->
            Timeline.toggleKeyAt id property model

        AddKeyAtPlayhead ->
            Timeline.addKeyAtPlayhead model

        RemoveSelectedKeys ->
            Timeline.removeSelectedKeys model

        RemoveTrack trackId ->
            commitScene "Remove track" (\s -> { s | tracks = Dict.remove trackId s.tracks }) model

        RemoveAllAnimation id ->
            commitScene "Remove animation" (Scene.removeTracksFor id) model

        SetTrackEnabled trackId enabled ->
            commitScene "Toggle track" (\s -> { s | tracks = Dict.update trackId (Maybe.map (\t -> { t | enabled = enabled })) s.tracks }) model

        SetTrackLocked trackId locked ->
            commitScene "Lock track" (\s -> { s | tracks = Dict.update trackId (Maybe.map (\t -> { t | locked = locked })) s.tracks }) model

        SelectKey ref additive ->
            updateEditor
                (\e ->
                    { e
                        | selectedKeys =
                            if additive then
                                if List.member ref e.selectedKeys then
                                    List.filter ((/=) ref) e.selectedKeys

                                else
                                    ref :: e.selectedKeys

                            else
                                [ ref ]
                        , focus = Model.TimelineFocus
                    }
                )
                model

        SelectKeysInRange refs ->
            updateEditor (\e -> { e | selectedKeys = refs }) model

        SetKeyEasing easing ->
            Timeline.setKeyEasing easing model

        SetKeyFrame ref frame ->
            commitScene "Move keyframe" (\s -> { s | tracks = Dict.update ref.trackId (Maybe.map (Keyframe.setFrame ref.keyId frame)) s.tracks }) model

        SetKeyValue ref value ->
            commitScene "Edit keyframe" (\s -> { s | tracks = Dict.update ref.trackId (Maybe.map (Keyframe.setValue ref.keyId value)) s.tracks }) model

        ShiftKeys delta ->
            Timeline.shiftKeys delta model

        ScaleKeys factor ->
            Timeline.scaleKeys factor model

        DistributeKeys ->
            Timeline.distributeKeys model

        ReverseKeys ->
            Timeline.reverseKeys model

        CopyKeys ->
            pure (Timeline.copyKeys model)

        PasteKeys ->
            Timeline.pasteKeys model

        TimelinePointerDown ev ->
            let
                e =
                    model.editor
            in
            if ev.button == 2 then
                pure { model | editor = { e | focus = Model.TimelineFocus } }

            else
                pure { model | editor = { e | focus = Model.TimelineFocus, selectedKeys = [] }, openMenu = Nothing, contextMenu = Nothing }

        TimelineRulerDown ev ->
            Timeline.rulerDown ev model

        KeyPointerDown ref ev ->
            Timeline.keyPointerDown ref ev model

        TimelineZoom factor ->
            pure (Edit.mapActiveView (\v -> { v | timelinePixelsPerFrame = clamp 1 120 (v.timelinePixelsPerFrame * factor) }) model)

        TimelineScroll delta ->
            pure (Edit.mapActiveView (\v -> { v | timelineScroll = max 0 (v.timelineScroll + delta) }) model)

        ToggleAllProperties ->
            updateEditor (\e -> { e | showAllProperties = not e.showAllProperties }) model

        SetWorkRange range ->
            commitScene "Work range" (\s -> { s | workRange = Maybe.map (\( a, b ) -> { start = a, end = b }) range }) model

        StaggerFormChanged field value ->
            case model.dialog of
                StaggerDialog f ->
                    pure
                        { model
                            | dialog =
                                StaggerDialog
                                    (case field of
                                        "start" ->
                                            { f | startFrame = value }

                                        "spacing" ->
                                            { f | spacing = value }

                                        _ ->
                                            { f | order = value }
                                    )
                        }

                _ ->
                    pure model

        ApplyStagger ->
            case model.dialog of
                StaggerDialog f ->
                    Timeline.applyStagger f model

                _ ->
                    pure model

        SplitterDown which start ->
            let
                e =
                    model.editor

                original =
                    case which of
                        "left" ->
                            e.leftWidth

                        "right" ->
                            e.rightWidth

                        _ ->
                            e.timelineHeight
            in
            updateEditor (\ed -> { ed | gesture = DragSplitter { which = which, start = start, original = original } }) model

        ToggleOnionSkin ->
            updateEditor (\e -> { e | onionSkin = not e.onionSkin }) model

        SetOnion before after ->
            updateEditor (\e -> { e | onionBefore = clamp 0 10 before, onionAfter = clamp 0 10 after }) model

        -- HISTORY / CLIPBOARD
        Undo ->
            case Model.activeDoc model of
                Just open ->
                    case History.undo open.document open.history of
                        Just ( doc, history ) ->
                            let
                                ( m2, cmd ) =
                                    Edit.updateDocument doc history model
                            in
                            ( pruneSelection (Edit.focusAnnounce "Undo" m2), cmd )

                        Nothing ->
                            pure model

                Nothing ->
                    pure model

        Redo ->
            case Model.activeDoc model of
                Just open ->
                    case History.redo open.document open.history of
                        Just ( doc, history ) ->
                            let
                                ( m2, cmd ) =
                                    Edit.updateDocument doc history model
                            in
                            ( pruneSelection (Edit.focusAnnounce "Redo" m2), cmd )

                        Nothing ->
                            pure model

                Nothing ->
                    pure model

        HistoryJump steps ->
            jumpHistory steps model

        Copy ->
            copySelection model

        Cut ->
            let
                ( m2, cmd ) =
                    copySelection model
            in
            case m2.internalClipboard of
                Just _ ->
                    let
                        ( m3, cmd2 ) =
                            Ops.deleteSelection m2
                    in
                    ( m3, Cmd.batch [ cmd, cmd2 ] )

                Nothing ->
                    ( m2, cmd )

        Paste ->
            case model.internalClipboard of
                Just value ->
                    Ops.pasteClipboard value False model

                Nothing ->
                    if model.capabilities.clipboardRead then
                        ( model, Ports.send (Ports.request "clip-read" "clipboard.read" E.null) )

                    else
                        pure model

        PasteInPlace ->
            case model.internalClipboard of
                Just value ->
                    Ops.pasteClipboard value True model

                Nothing ->
                    pure model

        CopyStyle ->
            case Edit.selectedNodes model of
                n :: _ ->
                    pure (Edit.toast "info" "Style copied" { model | internalClipboard = Just (E.object [ ( "format", E.string "framewise-style" ), ( "fill", encodePaint n.fill ), ( "stroke", encodeStroke n.stroke ), ( "opacity", E.float n.opacity ) ]) })

                [] ->
                    pure model

        PasteStyle ->
            case model.internalClipboard |> Maybe.andThen (D.decodeValue styleDecoder >> Result.toMaybe) of
                Just style ->
                    commitScene "Paste style"
                        (\s ->
                            List.foldl
                                (\id acc ->
                                    Scene.updateNode id
                                        (\n ->
                                            case n.geometry of
                                                Group ->
                                                    { n | opacity = style.opacity }

                                                ClippingGroup ->
                                                    { n | opacity = style.opacity }

                                                RasterImage _ ->
                                                    { n | opacity = style.opacity }

                                                _ ->
                                                    { n | fill = style.fill, stroke = style.stroke, opacity = style.opacity }
                                        )
                                        acc
                                )
                                s
                                (Edit.selection model)
                        )
                        model

                Nothing ->
                    pure (Edit.toast "info" "Copy a style first" model)

        CopyAsSvg ->
            case ( Model.activeDoc model, Model.activeScene model ) of
                ( Just open, Just scene ) ->
                    let
                        sel =
                            Edit.selection model

                        trimmed =
                            { scene | rootNodeIds = List.filter (\id -> List.member id sel) scene.rootNodeIds }

                        svg =
                            Export.Static.export { frame = Edit.currentFrame model, includeBackground = False, includeIds = True, title = Nothing, description = Nothing } open.document trimmed
                    in
                    case svg of
                        Just text ->
                            ( Edit.toast "info" "SVG copied to the clipboard" model, Ports.send (Ports.request "clip-write" "clipboard.write" (E.object [ ( "text", E.string text ) ])) )

                        Nothing ->
                            pure model

                _ ->
                    pure model

        -- DOCUMENTS & PERSISTENCE
        SaveDocument ->
            saveWith "save" model

        SaveDocumentAs ->
            saveWith "saveAs" model

        SaveCopy ->
            saveWith "copy" model

        SaveSnapshotJson ->
            case Model.activeDoc model of
                Just open ->
                    ( model, Ports.send (Ports.request "json" "file.downloadText" (E.object [ ( "name", E.string (open.document.metadata.name ++ ".framewise.json") ), ( "mime", E.string "application/json" ), ( "text", E.string (E.encode 2 (Edit.documentJson open.document)) ) ])) )

                Nothing ->
                    pure model

        RevertToSaved ->
            pure { model | dialog = ConfirmDialog { title = "Revert to saved?", body = "All changes since the last explicit save will be discarded. This reloads the saved file from the browser copy taken at save time.", confirmLabel = "Revert", onConfirm = "revert" } }

        OpenFile ->
            ( model, Ports.send (Persist.openFileRequest "document") )

        ImportSvg ->
            ( model, Ports.send (Persist.openFileRequest "svg") )

        ImportImage ->
            ( model, Ports.send (Persist.openFileRequest "image") )

        ImportReviewAccept ->
            case model.dialog of
                ImportReviewDialog review ->
                    acceptImport review { model | dialog = NoDialog }

                _ ->
                    pure model

        ImportReviewCancel ->
            pure { model | dialog = NoDialog }

        AutosaveTick docId revision ->
            case Dict.get docId model.documents of
                Just open ->
                    if open.revision == revision && open.autosavedRevision /= Just revision then
                        ( model, Ports.send (Persist.autosaveRequest open) )

                    else
                        pure model

                Nothing ->
                    pure model

        SetDirtyGuard ->
            pure model

        -- EXPORT
        OpenExport ->
            case Model.activeScene model of
                Just scene ->
                    pure { model | dialog = ExportDialog (Model.defaultExportForm scene (Edit.currentFrame model)), openMenu = Nothing }

                Nothing ->
                    pure model

        ExportFormChanged f ->
            case model.dialog of
                ExportDialog form ->
                    pure { model | dialog = ExportDialog (f form) }

                _ ->
                    pure model

        SelectExportFormat format ->
            case model.dialog of
                ExportDialog form ->
                    pure { model | dialog = ExportDialog { form | format = format } }

                _ ->
                    pure model

        RunExport ->
            case model.dialog of
                ExportDialog form ->
                    runExport form model

                _ ->
                    pure model

        QuickExport ->
            case Model.activeScene model of
                Just scene ->
                    runExport (Model.defaultExportForm scene (Edit.currentFrame model)) model

                Nothing ->
                    pure model

        CancelExportJob id ->
            ( { model | exportJobs = List.map (\j -> ifJob id j { j | status = "cancelled" }) model.exportJobs }
            , Ports.send (Ports.request ("cancel-" ++ id) "export.cancel" (E.object [ ( "jobId", E.string id ) ]))
            )

        RetryExportJob _ ->
            case model.dialog of
                ExportDialog form ->
                    runExport form model

                _ ->
                    pure model

        -- PREVIEW
        OpenPreview ->
            case Model.activeDoc model of
                Just open ->
                    let
                        e =
                            model.editor

                        pb =
                            e.playback

                        autoplay =
                            not model.reducedMotion

                        m2 =
                            { model | editor = { e | playback = { pb | playing = autoplay, startTime = -1, startFrame = Edit.currentFrame model } }, openMenu = Nothing, dialog = NoDialog }
                    in
                    ( m2, Nav.pushUrl model.key (Route.toPath model.basePath (Model.PreviewRoute open.document.id open.activeSceneId)) )

                Nothing ->
                    pure model

        ClosePreview ->
            case Model.activeDoc model of
                Just open ->
                    ( Edit.endPlayback model, Nav.pushUrl model.key (Route.toPath model.basePath (Model.EditorRoute open.document.id)) )

                Nothing ->
                    ( model, Nav.pushUrl model.key (Route.toPath model.basePath Model.Welcome) )

        PreviewSeek f ->
            pure (Timeline.setPlayhead f (Edit.endPlayback model))

        PreviewToggleFull ->
            ( model, Ports.send (Ports.request "fs" "platform.fullscreen" E.null) )

        Announce s ->
            pure { model | liveAnnouncement = s }



-- HELPERS


updateEditor : (Model.EditorState -> Model.EditorState) -> Model -> Update
updateEditor f model =
    pure { model | editor = f model.editor }


updatePlayback : (Model.Playback -> Model.Playback) -> Model -> Update
updatePlayback f model =
    updateEditor (\e -> { e | playback = f e.playback }) model


commitScene : String -> (Scene -> Scene) -> Model -> Update
commitScene description f model =
    case Model.activeDoc model of
        Just open ->
            Edit.commit description (Document.updateScene open.activeSceneId f) model

        Nothing ->
            pure model


commitSceneWith : String -> (Model -> Scene -> Scene) -> Model -> Update
commitSceneWith description f model =
    case Model.activeDoc model of
        Just open ->
            Edit.commitCoalesced description description (Document.updateScene open.activeSceneId (f model)) model

        Nothing ->
            pure model


dedupe : List comparable -> List comparable
dedupe =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []


isBlur : Node.Effect -> Bool
isBlur e =
    case e of
        Node.Blur _ ->
            True

        _ ->
            False


ifJob : String -> Model.ExportJob -> Model.ExportJob -> Model.ExportJob
ifJob id job replacement =
    if job.id == id then
        replacement

    else
        job


orderBySiblings : Scene -> List NodeId -> List NodeId
orderBySiblings scene ids =
    Scene.flattenOrder scene |> List.filter (\id -> List.member id ids)


{-| After undo/redo the selection may reference deleted nodes.
-}
pruneSelection : Model -> Model
pruneSelection model =
    case Model.activeScene model of
        Just scene ->
            let
                e =
                    model.editor
            in
            Edit.mapActiveView (\v -> { v | selection = List.filter (\id -> Dict.member id scene.nodes) v.selection })
                { model | editor = { e | selectedKeys = List.filter (\r -> Dict.member r.trackId scene.tracks) e.selectedKeys } }

        Nothing ->
            model


announceSelection : List NodeId -> Model -> String
announceSelection ids model =
    case ( ids, Model.activeScene model ) of
        ( [], _ ) ->
            "Nothing selected"

        ( [ id ], Just scene ) ->
            Dict.get id scene.nodes |> Maybe.map (\n -> n.name ++ " selected") |> Maybe.withDefault ""

        ( many, _ ) ->
            String.fromInt (List.length many) ++ " objects selected"


setHoverFromEvent : App.Msg.PointerEvent -> Model -> Model
setHoverFromEvent ev model =
    let
        e =
            model.editor
    in
    if e.hover == ev.hitNode then
        model

    else
        { model | editor = { e | hover = ev.hitNode } }


dragSplitter : { which : String, start : Float, original : Float } -> Float -> Float -> Model -> Update
dragSplitter g x y model =
    updateEditor
        (\e ->
            case g.which of
                "left" ->
                    { e | leftWidth = clamp 180 520 (g.original + (x - g.start)) }

                "right" ->
                    { e | rightWidth = clamp 220 560 (g.original - (x - g.start)) }

                _ ->
                    { e | timelineHeight = clamp 120 700 (g.original - (y - g.start)) }
        )
        model


styleDecoder : D.Decoder { fill : Paint.Paint, stroke : Paint.Stroke, opacity : Float }
styleDecoder =
    D.field "format" D.string
        |> D.andThen
            (\f ->
                if f == "framewise-style" then
                    D.map3 (\fill stroke opacity -> { fill = fill, stroke = stroke, opacity = opacity })
                        (D.field "fill" Decode.paintDecoder)
                        (D.field "stroke" Decode.strokeDecoder)
                        (D.field "opacity" D.float)

                else
                    D.fail "not a style"
            )


encodePaint : Paint.Paint -> E.Value
encodePaint =
    DocumentIO.Encode.paint


encodeStroke : Paint.Stroke -> E.Value
encodeStroke =
    DocumentIO.Encode.stroke


copySelection : Model -> Update
copySelection model =
    case Ops.clipboardPayload model of
        Just payload ->
            let
                m2 =
                    Edit.toast "info" "Copied" { model | internalClipboard = Just payload }
            in
            if model.capabilities.clipboardWrite then
                ( m2, Ports.send (Ports.request "clip-write" "clipboard.write" (E.object [ ( "text", E.string (E.encode 0 payload) ) ])) )

            else
                pure m2

        Nothing ->
            pure model


applyPickerColor : Color.Rgba -> Model -> Update
applyPickerColor color model =
    case model.picker of
        Nothing ->
            pure model

        Just p ->
            case p.target of
                Model.FillTarget ->
                    commitSceneWith "Fill colour" (\m s -> List.foldl (\id acc -> Tuple.first (Edit.setAnimatedProperty m id FillColor (ColorValue color) acc)) s (Edit.selection m)) model

                Model.StrokeTarget ->
                    commitSceneWith "Stroke colour" (\m s -> List.foldl (\id acc -> Tuple.first (Edit.setAnimatedProperty m id StrokeColor (ColorValue color) acc)) s (Edit.selection m)) model

                Model.BackgroundTarget ->
                    commitSceneWith "Background" (\_ s -> { s | background = Scene.SolidBackground color }) model

                Model.FormBackgroundTarget ->
                    case model.dialog of
                        NewDocumentDialog form ->
                            pure { model | dialog = NewDocumentDialog { form | background = color, transparent = False } }

                        SceneSettingsDialog form ->
                            pure { model | dialog = SceneSettingsDialog { form | background = color, transparent = False } }

                        _ ->
                            pure model


jumpToKey : Int -> Model -> Update
jumpToKey direction model =
    case Model.activeScene model of
        Just scene ->
            let
                frame =
                    Edit.currentFrame model

                sel =
                    Edit.selection model

                tracks =
                    if List.isEmpty sel then
                        Dict.values scene.tracks

                    else
                        List.concatMap (\id -> Scene.tracksFor id scene) sel

                frames =
                    tracks |> List.concatMap Keyframe.frames |> List.map toFloat

                target =
                    if direction > 0 then
                        frames |> List.filter (\f -> f > frame) |> List.minimum

                    else
                        frames |> List.filter (\f -> f < frame) |> List.maximum
            in
            case target of
                Just f ->
                    pure (Timeline.setPlayhead f (Edit.endPlayback model))

                Nothing ->
                    pure model

        Nothing ->
            pure model


jumpHistory : Int -> Model -> Update
jumpHistory steps model =
    if steps == 0 then
        pure model

    else
        let
            ( m2, cmd ) =
                update
                    (if steps < 0 then
                        Undo

                     else
                        Redo
                    )
                    model

            ( m3, cmd2 ) =
                jumpHistory
                    (if steps < 0 then
                        steps + 1

                     else
                        steps - 1
                    )
                    m2
        in
        ( m3, Cmd.batch [ cmd, cmd2 ] )


createMotionPathFromSelection : Model -> Update
createMotionPathFromSelection model =
    case Model.activeScene model of
        Just scene ->
            let
                nodes =
                    Edit.selectedNodes model

                pathNode =
                    nodes
                        |> List.filter
                            (\n ->
                                case n.geometry of
                                    Path _ ->
                                        True

                                    _ ->
                                        False
                            )
                        |> List.head

                target =
                    nodes |> List.filter (\n -> Just n.id /= Maybe.map .id pathNode) |> List.head
            in
            case ( pathNode, target ) of
                ( Just pn, Just tn ) ->
                    case ( pn.geometry, Canvas.resolvedNow model ) of
                        ( Path geometry, Just resolved ) ->
                            let
                                world =
                                    Dict.get pn.id resolved.byId |> Maybe.map .worldMatrix |> Maybe.withDefault Domain.Matrix.identity

                                parentInv =
                                    tn.parentId
                                        |> Maybe.andThen (\pid -> Dict.get pid resolved.byId)
                                        |> Maybe.map .worldMatrix
                                        |> Maybe.andThen Domain.Matrix.invert
                                        |> Maybe.withDefault Domain.Matrix.identity

                                geometryInParent =
                                    Domain.Path.transformGeometry (Domain.Matrix.multiply parentInv world) geometry

                                ( mpId, m2 ) =
                                    Edit.nextId model

                                ( tIds, m3 ) =
                                    Edit.nextIds 3 m2

                                idAt i =
                                    List.drop i tIds |> List.head |> Maybe.withDefault ("mp" ++ String.fromInt i)

                                update_ s =
                                    { s | motionPaths = Dict.insert mpId { id = mpId, name = tn.name ++ " path", geometry = geometryInParent, revision = 0 } s.motionPaths }
                                        |> Scene.updateNode tn.id
                                            (\n ->
                                                let
                                                    t =
                                                        n.transform
                                                in
                                                { n | motion = Just { pathId = mpId, orient = True }, transform = { t | translation = { x = 0, y = 0 } } }
                                            )
                                        |> (\sc ->
                                                case Scene.trackFor tn.id MotionProgress sc of
                                                    Just _ ->
                                                        sc

                                                    Nothing ->
                                                        Scene.upsertTrack
                                                            (Keyframe.newTrack (idAt 0) tn.id MotionProgress
                                                                |> Keyframe.insert { id = idAt 1, frame = 0, value = Scalar 0, easing = Domain.Easing.Preset Domain.Easing.EaseInOut }
                                                                |> Keyframe.insert { id = idAt 2, frame = sc.durationFrames, value = Scalar 1, easing = Domain.Easing.Linear }
                                                            )
                                                            sc
                                           )

                                ( m4, cmd ) =
                                    Edit.commit "Create motion path" (Document.updateScene scene.id update_) m3
                            in
                            ( Edit.setSelection [ tn.id ] m4, cmd )

                        _ ->
                            pure model

                _ ->
                    pure (Edit.toast "info" "Select a path and the object that should follow it" model)

        Nothing ->
            pure model



-- COMMANDS


runCommand : String -> Model -> Update
runCommand id model =
    case Commands.find id of
        Just cmd ->
            runCommandMsg cmd { model | openMenu = Nothing, contextMenu = Nothing, palette = Nothing }

        Nothing ->
            pure model


runCommandMsg : Commands.Command -> Model -> Update
runCommandMsg cmd model =
    case Commands.enabled model cmd of
        Err reason ->
            pure (Edit.toast "info" reason model)

        Ok () ->
            case cmd.msg of
                RunCommand id ->
                    runBuiltin id model

                other ->
                    update other model


runBuiltin : String -> Model -> Update
runBuiltin commandId model =
    case commandId of
        "file.new" ->
            pure { model | dialog = NewDocumentDialog (Model.defaultDocForm model.preferences) }

        "file.documentSettings" ->
            case Model.activeDoc model of
                Just open ->
                    pure { model | dialog = DocumentSettingsDialog { name = open.document.metadata.name, description = open.document.metadata.description } }

                Nothing ->
                    pure model

        "file.sceneSettings" ->
            case Model.activeScene model of
                Just scene ->
                    pure { model | dialog = SceneSettingsDialog (Model.sceneFormFor scene) }

                Nothing ->
                    pure model

        "file.close" ->
            case model.activeDocument of
                Just docId ->
                    update (CloseDocument docId) model

                Nothing ->
                    pure model

        "file.closeAll" ->
            let
                dirty =
                    Dict.values model.documents |> List.filter (\d -> Just d.revision /= d.savedRevision && d.revision /= 0)
            in
            if List.isEmpty dirty then
                ( { model | documents = Dict.empty, openOrder = [], activeDocument = Nothing }, Nav.pushUrl model.key (Route.toPath model.basePath Model.Welcome) )

            else
                pure { model | dialog = ConfirmDialog { title = "Close all documents?", body = String.fromInt (List.length dirty) ++ " document(s) have changes not saved to a file. Local autosaves remain recoverable.", confirmLabel = "Close all", onConfirm = "closeAll" } }

        "edit.findLayer" ->
            updateEditor (\e -> { e | leftTab = Model.LayersTab, leftCollapsed = False, layerFilter = "" }) model
                |> Tuple.mapSecond (\c -> Cmd.batch [ c, focusElement "layer-filter" ])

        "edit.rename" ->
            case Edit.selection model of
                id :: _ ->
                    update (StartRename id) model

                [] ->
                    pure model

        "layer.lock" ->
            case Edit.selectedNodes model of
                n :: _ ->
                    commitScene "Lock" (\s -> List.foldl (\id acc -> Scene.updateNode id (\x -> { x | locked = not n.locked }) acc) s (Edit.selection model)) model

                [] ->
                    pure model

        "layer.hide" ->
            case Edit.selectedNodes model of
                n :: _ ->
                    commitScene "Hide" (\s -> List.foldl (\id acc -> Scene.updateNode id (\x -> { x | hidden = not n.hidden }) acc) s (Edit.selection model)) model

                [] ->
                    pure model

        "layer.isolate" ->
            case Edit.selectedNodes model |> List.filter Node.isContainer |> List.head of
                Just g ->
                    updateEditor (\e -> { e | isolation = Just g.id }) model

                Nothing ->
                    pure model

        "layer.expandAll" ->
            case Model.activeScene model of
                Just scene ->
                    pure (Edit.mapActiveView (\v -> { v | expanded = Set.fromList (Dict.keys scene.nodes) }) model)

                Nothing ->
                    pure model

        "layer.collapseAll" ->
            pure (Edit.mapActiveView (\v -> { v | expanded = Set.empty }) model)

        "layer.removeAnimation" ->
            commitScene "Remove animation" (\s -> List.foldl Scene.removeTracksFor s (Edit.selection model)) model

        "animate.setWorkRange" ->
            case Model.activeScene model of
                Just scene ->
                    let
                        frames =
                            model.editor.selectedKeys
                                |> List.filterMap (\r -> Dict.get r.trackId scene.tracks |> Maybe.andThen (\t -> List.filter (\k -> k.id == r.keyId) t.keyframes |> List.head))
                                |> List.map .frame
                    in
                    case ( List.minimum frames, List.maximum frames ) of
                        ( Just a, Just b ) ->
                            update (SetWorkRange (Just ( a, max (a + 1) b ))) model

                        _ ->
                            pure model

                Nothing ->
                    pure model

        "window.layers" ->
            updateEditor (\e -> { e | leftTab = Model.LayersTab, leftCollapsed = False }) model

        "window.assets" ->
            updateEditor (\e -> { e | leftTab = Model.AssetsTab, leftCollapsed = False }) model

        "window.scenes" ->
            updateEditor (\e -> { e | leftTab = Model.ScenesTab, leftCollapsed = False }) model

        _ ->
            pure model


focusElement : String -> Cmd Msg
focusElement id =
    Ports.send (Ports.request "focus" "platform.focus" (E.object [ ( "id", E.string id ) ]))


paletteResults : String -> Model -> List Commands.Command
paletteResults query model =
    let
        q =
            String.toLower (String.trim query)

        score cmd =
            let
                label =
                    String.toLower cmd.label

                cat =
                    String.toLower cmd.category
            in
            if String.isEmpty q then
                Just 0

            else if String.startsWith q label then
                Just 0

            else if String.contains q label then
                Just 1

            else if String.contains q cat then
                Just 2

            else if fuzzy q label then
                Just 3

            else
                Nothing
    in
    Commands.all
        |> List.filterMap (\c -> score c |> Maybe.map (\s -> ( s, c )))
        |> List.sortBy Tuple.first
        |> List.map Tuple.second
        |> List.take 40
        |> (\list ->
                let
                    _ =
                        model
                in
                list
           )


fuzzy : String -> String -> Bool
fuzzy pattern text =
    let
        go ps ts =
            case ( ps, ts ) of
                ( [], _ ) ->
                    True

                ( _, [] ) ->
                    False

                ( p :: prest, t :: trest ) ->
                    if p == t then
                        go prest trest

                    else
                        go ps trest
    in
    go (String.toList pattern) (String.toList text)


confirmAction : String -> Model -> Update
confirmAction action model =
    case String.split ":" action of
        [ "close", id ] ->
            closeDocument id model

        [ "closeAll" ] ->
            ( { model | documents = Dict.empty, openOrder = [], activeDocument = Nothing }, Nav.pushUrl model.key (Route.toPath model.basePath Model.Welcome) )

        [ "delete" ] ->
            Ops.deleteSelection model

        [ "deleteScene", sceneId ] ->
            case Model.activeDoc model of
                Just open ->
                    let
                        remaining =
                            List.filter ((/=) sceneId) open.document.sceneOrder

                        nextActive =
                            List.head remaining |> Maybe.withDefault open.activeSceneId

                        ( m2, cmd ) =
                            Edit.commit "Delete scene" (Document.removeScene sceneId) model
                    in
                    ( Edit.mapActiveDoc (\d -> { d | activeSceneId = nextActive }) m2, cmd )

                Nothing ->
                    pure model

        [ "discardRecovery", id ] ->
            ( { model | recoveries = List.filter (\r -> r.documentId /= id) model.recoveries }, Ports.send (Persist.deleteRecoveryRequest id True) )

        [ "clearStorage", category ] ->
            ( model, Ports.send (Ports.request "clear" "storage.clear" (E.object [ ( "category", E.string category ) ])) )

        [ "revert" ] ->
            case Model.activeDoc model of
                Just open ->
                    ( model, Ports.send (Ports.request ("revert-" ++ open.document.id) "storage.loadSaved" (E.object [ ( "documentId", E.string open.document.id ) ])) )

                Nothing ->
                    pure model

        [ "import", _ ] ->
            pure model

        _ ->
            pure model


closeDocument : DocumentId -> Model -> Update
closeDocument id model =
    let
        remaining =
            List.filter ((/=) id) model.openOrder

        m2 =
            { model
                | documents = Dict.remove id model.documents
                , openOrder = remaining
                , activeDocument =
                    if model.activeDocument == Just id then
                        List.head remaining

                    else
                        model.activeDocument
                , dialog = NoDialog
            }
    in
    case m2.activeDocument of
        Just next ->
            ( m2, Cmd.batch [ Nav.pushUrl model.key (Route.toPath model.basePath (Model.EditorRoute next)), Ports.send Persist.recentsRequest ] )

        Nothing ->
            ( Edit.endPlayback m2, Cmd.batch [ Nav.pushUrl model.key (Route.toPath model.basePath Model.Welcome), Ports.send Persist.recentsRequest ] )



-- DOCUMENT CREATION


applyPreset : String -> Model.DocForm -> Model.DocForm
applyPreset presetId form =
    case Presets.find presetId of
        Just p ->
            { form
                | preset = presetId
                , width = String.fromFloat p.width
                , height = String.fromFloat p.height
                , fpsPreset = String.fromInt p.fps
                , fpsNumerator = String.fromInt p.fps
                , fpsDenominator = "1"
                , duration = String.fromInt p.duration
                , transparent = p.transparent
            }

        Nothing ->
            form


createDocument : Model.DocForm -> Model -> Update
createDocument form model =
    let
        width =
            String.toFloat form.width

        height =
            String.toFloat form.height

        fps =
            Maybe.map2 Fps.fps (String.toInt form.fpsNumerator) (String.toInt form.fpsDenominator)

        duration =
            String.toInt form.duration

        validation =
            case ( ( width, height ), ( fps, duration ) ) of
                ( ( Just w, Just h ), ( Just f, Just d ) ) ->
                    if w < 1 || h < 1 || w > 16384 || h > 16384 then
                        Err "Width and height must be between 1 and 16384"

                    else if not (Fps.isValid f) then
                        Err "Frame rate must be between 1 and 240"

                    else if d < 1 || d > 100000 then
                        Err "Duration must be between 1 and 100000 frames"

                    else
                        Ok ( w, h, ( f, d ) )

                _ ->
                    Err "Enter whole numbers for size, frame rate and duration"
    in
    case validation of
        Err e ->
            pure { model | dialog = NewDocumentDialog { form | error = Just e } }

        Ok ( w, h, ( f, d ) ) ->
            let
                ( ids, m2 ) =
                    Edit.nextIds 2 model

                docId =
                    List.head ids |> Maybe.withDefault "doc"

                sceneId =
                    List.drop 1 ids |> List.head |> Maybe.withDefault "scene"

                background =
                    if form.transparent then
                        Scene.Transparent

                    else
                        Scene.SolidBackground form.background

                scene =
                    Scene.new sceneId (nonEmpty form.sceneName "Scene 1") w h f d background

                doc =
                    Document.new docId (nonEmpty form.title "Untitled") (isoTime m2.now) scene

                m3 =
                    Persist.openDocument doc { fileName = Nothing, fileToken = Nothing, savedRevision = Nothing, revision = 0, isRecovery = False } { m2 | dialog = NoDialog }
            in
            ( m3
            , Cmd.batch
                [ Nav.pushUrl model.key (Route.toPath model.basePath (Model.EditorRoute docId))
                , Edit.scheduleAutosave docId 0 m3
                , refillIds m3
                ]
            )


nonEmpty : String -> String -> String
nonEmpty s default =
    if String.isEmpty (String.trim s) then
        default

    else
        String.trim s


isoTime : Time.Posix -> String
isoTime posix =
    let
        ms =
            Time.posixToMillis posix
    in
    -- stored as epoch milliseconds in a sortable string; display formatting happens in the view
    String.fromInt ms


refillIds : Model -> Cmd Msg
refillIds model =
    if List.length model.ids < 64 && not model.idRequestPending then
        Persist.requestIdsCmd

    else
        Cmd.none


openExample : String -> Model -> Update
openExample exampleId model =
    let
        ( ids, m2 ) =
            Edit.nextIds 2 model

        docId =
            List.head ids |> Maybe.withDefault "doc"

        sceneId =
            List.drop 1 ids |> List.head |> Maybe.withDefault "scene"
    in
    case Examples.build exampleId docId sceneId (isoTime model.now) of
        Just doc ->
            let
                m3 =
                    Persist.openDocument doc { fileName = Nothing, fileToken = Nothing, savedRevision = Nothing, revision = 0, isRecovery = False } m2
            in
            ( m3, Cmd.batch [ Nav.pushUrl model.key (Route.toPath model.basePath (Model.EditorRoute docId)), Edit.scheduleAutosave docId 0 m3, refillIds m3 ] )

        Nothing ->
            pure model


applySceneSettings : Model.SceneForm -> Model -> Update
applySceneSettings form model =
    case Model.activeDoc model |> Maybe.andThen (\d -> Dict.get form.sceneId d.document.scenes) of
        Nothing ->
            pure model

        Just scene ->
            let
                parsed =
                    Maybe.map4 (\w h n d -> { w = w, h = h, n = n, d = d })
                        (String.toFloat form.width)
                        (String.toFloat form.height)
                        (String.toInt form.fpsNumerator)
                        (String.toInt form.fpsDenominator)

                duration =
                    String.toInt form.duration
            in
            case ( parsed, duration ) of
                ( Just p, Just dur ) ->
                    let
                        newFps =
                            Fps.fps p.n p.d
                    in
                    if p.w < 1 || p.h < 1 || p.w > 16384 || p.h > 16384 then
                        pure { model | dialog = SceneSettingsDialog { form | error = Just "Width and height must be between 1 and 16384" } }

                    else if not (Fps.isValid newFps) then
                        pure { model | dialog = SceneSettingsDialog { form | error = Just "Frame rate must be between 1 and 240" } }

                    else if dur < 1 then
                        pure { model | dialog = SceneSettingsDialog { form | error = Just "Duration must be at least 1 frame" } }

                    else
                        let
                            retimed =
                                if Fps.equal newFps scene.fps then
                                    scene

                                else if form.fpsMode == "time" then
                                    retimeTracks scene.fps newFps scene

                                else
                                    scene

                            scaled =
                                if form.resizeMode == "scale" && (p.w /= scene.width || p.h /= scene.height) then
                                    scaleSceneContent (p.w / scene.width) (p.h / scene.height) retimed

                                else
                                    retimed

                            -- when timing is preserved and the user left the duration alone, keep the rescaled duration
                            effectiveDuration =
                                if form.fpsMode == "time" && dur == scene.durationFrames && not (Fps.equal newFps scene.fps) then
                                    retimed.durationFrames

                                else
                                    dur

                            trimmed =
                                if form.keepOutOfRange then
                                    scaled

                                else
                                    { scaled | tracks = Dict.map (\_ t -> { t | keyframes = List.filter (\k -> k.frame <= effectiveDuration) t.keyframes }) scaled.tracks |> Dict.filter (\_ t -> not (List.isEmpty t.keyframes)) }

                            workRange =
                                if form.useWorkRange then
                                    Maybe.map2 (\a b -> { start = clamp 0 dur a, end = clamp 0 dur b }) (String.toInt form.workStart) (String.toInt form.workEnd)

                                else
                                    Nothing

                            updated =
                                { trimmed
                                    | name = nonEmpty form.name scene.name
                                    , description = form.description
                                    , width = p.w
                                    , height = p.h
                                    , fps = newFps
                                    , durationFrames = effectiveDuration
                                    , playbackMode = form.playbackMode
                                    , workRange = workRange
                                    , background =
                                        if form.transparent then
                                            Scene.Transparent

                                        else
                                            Scene.SolidBackground form.background
                                }

                            ( m2, cmd ) =
                                Edit.commit "Scene settings" (Document.setScene updated) { model | dialog = NoDialog }
                        in
                        ( Timeline.setPlayhead (Edit.currentFrame m2) m2, cmd )

                _ ->
                    pure { model | dialog = SceneSettingsDialog { form | error = Just "Enter whole numbers for size, frame rate and duration" } }


{-| Preserve timing in seconds when the frame rate changes: every key frame
index is rescaled and rounded; collisions keep the later key.
-}
retimeTracks : Fps.Fps -> Fps.Fps -> Scene -> Scene
retimeTracks old new scene =
    let
        factor =
            Fps.toFloat new / Fps.toFloat old

        retime t =
            let
                moved =
                    List.map (\k -> { k | frame = round (toFloat k.frame * factor) }) t.keyframes

                dedup =
                    List.foldl (\k acc -> k :: List.filter (\o -> o.frame /= k.frame) acc) [] moved
            in
            { t | keyframes = List.sortBy .frame dedup }
    in
    { scene
        | tracks = Dict.map (\_ t -> retime t) scene.tracks
        , durationFrames = max 1 (round (toFloat scene.durationFrames * factor))
        , markers = List.map (\m -> { m | frame = round (toFloat m.frame * factor) }) scene.markers
        , workRange = Maybe.map (\r -> { start = round (toFloat r.start * factor), end = round (toFloat r.end * factor) }) scene.workRange
    }


scaleSceneContent : Float -> Float -> Scene -> Scene
scaleSceneContent sx sy scene =
    let
        scaleRoot id s =
            Scene.updateNode id
                (\n ->
                    let
                        t =
                            n.transform
                    in
                    { n | transform = { t | translation = { x = t.translation.x * sx, y = t.translation.y * sy }, scale = { x = t.scale.x * sx, y = t.scale.y * sy } } }
                )
                s

        scaled =
            List.foldl scaleRoot scene scene.rootNodeIds

        scaleTrack t =
            if List.member t.target.nodeId scene.rootNodeIds then
                case t.target.property of
                    Position ->
                        { t | keyframes = List.map (\k -> { k | value = mapPoint sx sy k.value }) t.keyframes }

                    Scale ->
                        { t | keyframes = List.map (\k -> { k | value = mapPoint sx sy k.value }) t.keyframes }

                    _ ->
                        t

            else
                t
    in
    { scaled | tracks = Dict.map (\_ t -> scaleTrack t) scaled.tracks }


mapPoint : Float -> Float -> PropertyValue -> PropertyValue
mapPoint sx sy v =
    case v of
        PointValue p ->
            PointValue { x = p.x * sx, y = p.y * sy }

        other ->
            other



-- SAVE / EXPORT


saveWith : String -> Model -> Update
saveWith mode model =
    case Model.activeDoc model of
        Just open ->
            let
                errors =
                    List.filter (\i -> i.severity == Domain.Validation.Error) open.validation
            in
            if not (List.isEmpty errors) then
                pure (Edit.toast "error" ("Cannot save: " ++ (List.head errors |> Maybe.map .message |> Maybe.withDefault "validation failed")) model)

            else
                ( Edit.mapActiveDoc (\d -> { d | saveStatus = Model.Saving }) model
                , Ports.send (Persist.saveRequest mode open)
                )

        Nothing ->
            pure model


runExport : Model.ExportForm -> Model -> Update
runExport form model =
    case Format.availability form.format of
        Format.Unavailable reason ->
            pure (Edit.toast "error" reason model)

        Format.Available ->
            case Persist.exportRequest form model of
                Err e ->
                    pure (Edit.toast "error" e model)

                Ok req ->
                    let
                        job =
                            { id = req.requestId
                            , label = Format.label form.format
                            , status = "queued"
                            , progress = Nothing
                            , message = Nothing
                            , fileName = Nothing
                            , revision = Maybe.withDefault 0 req.revision
                            }
                    in
                    ( { model | exportJobs = job :: List.filter (\j -> j.id /= job.id) model.exportJobs |> List.take 10 }
                    , Ports.send req
                    )



-- IMPORT


acceptImport : Model.ImportReview -> Model -> Update
acceptImport review model =
    case D.decodeValue (D.list Decode.node) review.nodes of
        Err err ->
            pure (Edit.toast "error" ("Import failed: " ++ D.errorToString err |> String.left 200) model)

        Ok nodes ->
            if review.asNewDocument || Model.activeDoc model == Nothing then
                importAsNewDocument review nodes model

            else
                importIntoScene review nodes model


importIntoScene : Model.ImportReview -> List Node.Node -> Model -> Update
importIntoScene review nodes model =
    case Model.activeScene model of
        Nothing ->
            pure model

        Just scene ->
            let
                ( ids, m2 ) =
                    Edit.nextIds (List.length nodes + 1) model

                groupId =
                    List.head ids |> Maybe.withDefault "import"

                mapping =
                    Dict.fromList (List.map2 (\n fresh -> ( n.id, fresh )) nodes (List.drop 1 ids))

                idFor old =
                    Dict.get old mapping |> Maybe.withDefault old

                roots =
                    List.filter (\n -> n.parentId == Nothing) nodes

                remapped =
                    List.map
                        (\n ->
                            { n
                                | id = idFor n.id
                                , childIds = List.map idFor n.childIds
                                , parentId =
                                    case n.parentId of
                                        Just p ->
                                            Just (idFor p)

                                        Nothing ->
                                            Just groupId
                                , importedElementId = Just n.id
                            }
                        )
                        nodes

                -- centre the import on the scene
                offset =
                    case ( review.width, review.height ) of
                        ( Just w, Just h ) ->
                            { x = (scene.width - w) / 2, y = (scene.height - h) / 2 }

                        _ ->
                            { x = 0, y = 0 }

                group =
                    let
                        g =
                            Node.new groupId (String.replace ".svg" "" review.fileName) Group
                    in
                    { g | childIds = List.map (.id >> idFor) roots, transform = Domain.Transform.translated offset }

                update_ s =
                    let
                        withNodes =
                            List.foldl (\n acc -> { acc | nodes = Dict.insert n.id n acc.nodes }) s remapped
                    in
                    Scene.insertNode model.editor.isolation 9999 group withNodes

                ( m3, cmd ) =
                    Edit.commit "Import SVG" (Document.updateScene scene.id update_) m2

                summary =
                    String.fromInt review.supportedCount
                        ++ " element(s) imported"
                        ++ (if List.isEmpty review.unsupported then
                                ""

                            else
                                ", " ++ String.fromInt (List.length review.unsupported) ++ " unsupported skipped"
                           )
            in
            ( Edit.setSelection [ groupId ] (Edit.toast "info" summary m3), Cmd.batch [ cmd, refillIds m3 ] )


importAsNewDocument : Model.ImportReview -> List Node.Node -> Model -> Update
importAsNewDocument review nodes model =
    let
        ( ids, m2 ) =
            Edit.nextIds 2 model

        docId =
            List.head ids |> Maybe.withDefault "doc"

        sceneId =
            List.drop 1 ids |> List.head |> Maybe.withDefault "scene"

        w =
            review.width |> Maybe.withDefault model.preferences.defaultWidth

        h =
            review.height |> Maybe.withDefault model.preferences.defaultHeight

        scene0 =
            Scene.new sceneId "Scene 1" (max 1 w) (max 1 h) model.preferences.defaultFps model.preferences.defaultDuration Scene.Transparent

        scene =
            { scene0
                | nodes = Dict.fromList (List.map (\n -> ( n.id, { n | importedElementId = Just n.id } )) nodes)
                , rootNodeIds = nodes |> List.filter (\n -> n.parentId == Nothing) |> List.map .id
            }

        doc =
            Document.new docId (String.replace ".svg" "" review.fileName) (isoTime model.now) scene

        m3 =
            Persist.openDocument doc { fileName = Nothing, fileToken = Nothing, savedRevision = Nothing, revision = 0, isRecovery = False } m2
    in
    ( m3, Cmd.batch [ Nav.pushUrl model.key (Route.toPath model.basePath (Model.EditorRoute docId)), Edit.scheduleAutosave docId 0 m3, refillIds m3 ] )



-- BRIDGE RESPONSES


handleFromJs : D.Value -> Model -> Update
handleFromJs value model =
    case D.decodeValue Interop.responseDecoder value of
        Err _ ->
            pure model

        Ok response ->
            let
                failed =
                    response.status == "error"

                message =
                    Maybe.withDefault "Unknown error" response.message
            in
            case response.operation of
                "platform.ids" ->
                    case D.decodeValue (D.field "ids" (D.list D.string)) response.payload of
                        Ok ids ->
                            pure { model | ids = model.ids ++ ids, idRequestPending = False }

                        Err _ ->
                            pure { model | idRequestPending = False }

                "storage.recents" ->
                    let
                        recents =
                            D.decodeValue (D.field "recents" (D.list Interop.recentDecoder)) response.payload |> Result.withDefault model.recents

                        recoveries =
                            D.decodeValue (D.field "recoveries" (D.list Interop.recoveryDecoder)) response.payload |> Result.withDefault model.recoveries
                    in
                    pure { model | recents = recents, recoveries = recoveries }

                "storage.load" ->
                    if failed then
                        ( { model | dialog = ErrorDialog "Could not open document" message }, Nav.pushUrl model.key (Route.toPath model.basePath Model.Welcome) )

                    else
                        openLoaded response.payload False model

                "storage.loadSaved" ->
                    if failed then
                        pure (Edit.toast "error" message model)

                    else
                        case D.decodeValue (D.field "document" Decode.document) response.payload of
                            Ok doc ->
                                case Model.activeDoc model of
                                    Just open ->
                                        Edit.updateDocument doc (History.commit "Revert to saved" open.document open.history) model
                                            |> Tuple.mapFirst (Edit.mapActiveDoc (\d -> { d | savedRevision = Just d.revision }))

                                    Nothing ->
                                        pure model

                            Err _ ->
                                pure (Edit.toast "error" "The saved copy could not be decoded" model)

                "file.open" ->
                    if failed then
                        if response.code == Just "cancelled" then
                            pure model

                        else
                            pure { model | dialog = ErrorDialog "Could not open file" message }

                    else
                        case D.decodeValue (D.field "kind" D.string) response.payload of
                            Ok "svg" ->
                                case D.decodeValue (D.field "review" Interop.importReviewDecoder) response.payload of
                                    Ok review ->
                                        pure { model | dialog = ImportReviewDialog { review | asNewDocument = Model.activeDoc model == Nothing } }

                                    Err e ->
                                        pure { model | dialog = ErrorDialog "SVG import failed" (D.errorToString e |> String.left 300) }

                            Ok "image" ->
                                addImageAsset response.payload model

                            _ ->
                                openLoaded response.payload False model

                "storage.autosave" ->
                    let
                        docId =
                            D.decodeValue (D.field "documentId" D.string) response.payload |> Result.withDefault ""

                        revision =
                            D.decodeValue (D.field "revision" D.int) response.payload |> Result.withDefault -1
                    in
                    if failed then
                        pure
                            ({ model | documents = Dict.update docId (Maybe.map (\d -> { d | autosaveFailed = Just message })) model.documents }
                                |> Edit.toast "error" ("Autosave failed: " ++ message ++ ". Save a copy to a file now.")
                            )

                    else
                        ( { model | documents = Dict.update docId (Maybe.map (\d -> { d | autosavedRevision = Just revision, autosaveFailed = Nothing })) model.documents }
                        , Ports.send Persist.recentsRequest
                        )

                "file.save" ->
                    let
                        docId =
                            response.payload |> D.decodeValue (D.field "documentId" D.string) |> Result.withDefault (model.activeDocument |> Maybe.withDefault "")
                    in
                    if failed then
                        if response.code == Just "cancelled" then
                            pure { model | documents = Dict.update docId (Maybe.map (\d -> { d | saveStatus = Model.SaveIdle })) model.documents }

                        else
                            pure
                                ({ model | documents = Dict.update docId (Maybe.map (\d -> { d | saveStatus = Model.SaveFailed message })) model.documents }
                                    |> Edit.toast "error" ("Save failed: " ++ message)
                                )

                    else
                        let
                            info =
                                D.decodeValue
                                    (D.map5 (\m f t r c -> { mode = m, fileName = f, fileToken = t, revision = r, copy = c })
                                        (D.field "mode" D.string)
                                        (D.maybe (D.field "fileName" D.string))
                                        (D.maybe (D.field "fileToken" D.string))
                                        (D.field "revision" D.int)
                                        (D.oneOf [ D.field "copy" D.bool, D.succeed False ])
                                    )
                                    response.payload
                        in
                        case info of
                            Ok i ->
                                if i.copy then
                                    pure (Edit.toast "info" ("Copy saved as " ++ Maybe.withDefault "download" i.fileName) { model | documents = Dict.update docId (Maybe.map (\d -> { d | saveStatus = Model.SaveIdle })) model.documents })

                                else
                                    ( { model
                                        | documents =
                                            Dict.update docId
                                                (Maybe.map
                                                    (\d ->
                                                        { d
                                                            | saveStatus = Model.SaveIdle
                                                            , savedRevision = Just i.revision
                                                            , fileName = i.fileName
                                                            , fileToken = i.fileToken
                                                            , lastSaveWasDownload = i.mode == "downloaded"
                                                            , isRecoveryCopy = False
                                                        }
                                                    )
                                                )
                                                model.documents
                                      }
                                        |> Edit.toast "info"
                                            (if i.mode == "downloaded" then
                                                "Downloaded " ++ Maybe.withDefault "file" i.fileName ++ ". The browser cannot overwrite files, so each save is a new download."

                                             else
                                                "Saved to " ++ Maybe.withDefault "file" i.fileName
                                            )
                                    , Ports.send Persist.recentsRequest
                                    )

                            Err _ ->
                                pure model

                "export.run" ->
                    let
                        jobId =
                            response.requestId
                    in
                    if failed then
                        pure
                            ({ model | exportJobs = List.map (\j -> ifJob jobId j { j | status = "failed", message = Just message }) model.exportJobs }
                                |> Edit.toast "error" ("Export failed: " ++ message)
                            )

                    else
                        let
                            fileName =
                                D.decodeValue (D.field "fileName" D.string) response.payload |> Result.toMaybe

                            bytes =
                                D.decodeValue (D.field "bytes" D.int) response.payload |> Result.withDefault 0
                        in
                        pure
                            ({ model | exportJobs = List.map (\j -> ifJob jobId j { j | status = "completed", fileName = fileName, message = Just (formatBytes bytes) }) model.exportJobs }
                                |> Edit.toast "info" ("Exported " ++ Maybe.withDefault "file" fileName)
                            )

                "export.progress" ->
                    let
                        jobId =
                            D.decodeValue (D.field "jobId" D.string) response.payload |> Result.withDefault ""

                        status =
                            D.decodeValue (D.field "status" D.string) response.payload |> Result.withDefault "rendering"

                        progress =
                            D.decodeValue (D.map2 Tuple.pair (D.field "done" D.int) (D.field "total" D.int)) response.payload |> Result.toMaybe
                    in
                    pure { model | exportJobs = List.map (\j -> ifJob jobId j { j | status = status, progress = progress }) model.exportJobs }

                "clipboard.read" ->
                    case D.decodeValue (D.field "text" D.string) response.payload |> Result.toMaybe |> Maybe.andThen (D.decodeString D.value >> Result.toMaybe) of
                        Just v ->
                            Ops.pasteClipboard v False model

                        Nothing ->
                            if failed then
                                pure (Edit.toast "info" "Clipboard access was denied; copy and paste still works inside this tab" model)

                            else
                                pure model

                "event.visibility" ->
                    case D.decodeValue (D.field "hidden" D.bool) response.payload of
                        Ok True ->
                            pure (Edit.endPlayback model)

                        _ ->
                            pure model

                "event.capabilities" ->
                    case D.decodeValue Interop.capabilitiesDecoder response.payload of
                        Ok caps ->
                            pure { model | capabilities = caps }

                        Err _ ->
                            pure model

                "event.offlineReady" ->
                    pure { model | offlineReady = True }

                "event.dragOverlay" ->
                    case D.decodeValue (D.field "active" D.bool) response.payload of
                        Ok active ->
                            pure { model | dragOverlay = active }

                        Err _ ->
                            pure model

                "event.tabConflict" ->
                    case D.decodeValue (D.field "documentId" D.string) response.payload of
                        Ok docId ->
                            pure (Edit.toast "warning" "This document is open in another tab. Changes here are kept separately; save to a file to keep them." { model | tabConflicts = docId :: model.tabConflicts })

                        Err _ ->
                            pure model

                "event.storage" ->
                    pure (Edit.toast "warning" message model)

                "storage.persist" ->
                    if failed then
                        pure (Edit.toast "warning" "The browser declined persistent storage" model)

                    else
                        pure (Edit.toast "info" "Persistent storage granted" model)

                "storage.clear" ->
                    ( Edit.toast "info" "Storage cleared" model, Ports.send Persist.recentsRequest )

                "storage.delete" ->
                    ( model, Ports.send Persist.recentsRequest )

                "storage.downloadRecovery" ->
                    if failed then
                        pure (Edit.toast "error" message model)

                    else
                        pure (Edit.toast "info" "Recovery copy downloaded" model)

                _ ->
                    if failed then
                        pure (Edit.toast "error" message model)

                    else
                        pure model


formatBytes : Int -> String
formatBytes n =
    if n > 1000000 then
        String.fromFloat (toFloat (round (toFloat n / 100000)) / 10) ++ " MB"

    else if n > 1000 then
        String.fromInt (n // 1000) ++ " kB"

    else
        String.fromInt n ++ " B"


openLoaded : D.Value -> Bool -> Model -> Update
openLoaded payload _ model =
    let
        decoded =
            D.decodeValue
                (D.map6 (\doc fileName fileToken revision savedRevision recovery -> { doc = doc, fileName = fileName, fileToken = fileToken, revision = revision, savedRevision = savedRevision, recovery = recovery })
                    (D.field "document" Decode.document)
                    (D.maybe (D.field "fileName" D.string))
                    (D.maybe (D.field "fileToken" D.string))
                    (D.oneOf [ D.field "revision" D.int, D.succeed 0 ])
                    (D.maybe (D.field "savedRevision" D.int))
                    (D.oneOf [ D.field "recovery" D.bool, D.succeed False ])
                )
                payload

        assetUrls =
            D.decodeValue (D.field "assetUrls" (D.dict D.string)) payload |> Result.withDefault Dict.empty
    in
    case decoded of
        Err err ->
            ( { model | dialog = ErrorDialog "Document could not be decoded" ("The file was not changed. " ++ String.left 400 (D.errorToString err)) }
            , Nav.pushUrl model.key (Route.toPath model.basePath Model.Welcome)
            )

        Ok info ->
            let
                doc =
                    info.doc

                issues =
                    Domain.Validation.validateDocument doc

                errors =
                    List.filter (\i -> i.severity == Domain.Validation.Error) issues
            in
            if not (List.isEmpty errors) then
                ( { model | dialog = ErrorDialog "Document failed validation" (String.join "\n" (List.map (\i -> i.objectId ++ ": " ++ i.message) (List.take 10 errors))) }
                , Nav.pushUrl model.key (Route.toPath model.basePath Model.Welcome)
                )

            else
                let
                    m2 =
                        Persist.openDocument doc
                            { fileName = info.fileName
                            , fileToken = info.fileToken
                            , savedRevision =
                                if info.fileName /= Nothing && info.savedRevision == Nothing then
                                    Just info.revision

                                else
                                    info.savedRevision
                            , revision = info.revision
                            , isRecovery = info.recovery
                            }
                            model
                            |> Edit.mapActiveDoc (\d -> { d | assetUrls = assetUrls, autosavedRevision = Just info.revision })

                    target =
                        case model.route of
                            Model.PreviewRoute id sceneId ->
                                if id == doc.id then
                                    Model.PreviewRoute id sceneId

                                else
                                    Model.EditorRoute doc.id

                            _ ->
                                Model.EditorRoute doc.id
                in
                ( m2, Cmd.batch [ Nav.pushUrl model.key (Route.toPath model.basePath target), refillIds m2 ] )


addImageAsset : D.Value -> Model -> Update
addImageAsset payload model =
    case ( Model.activeScene model, D.decodeValue imageDecoder payload ) of
        ( Just scene, Ok img ) ->
            let
                ( node, m2 ) =
                    Edit.newNodeAt (String.replace "." " " img.name)
                        (RasterImage { assetId = img.asset.id, size = { x = toFloat img.asset.width, y = toFloat img.asset.height }, naturalSize = { x = toFloat img.asset.width, y = toFloat img.asset.height } })
                        { x = (scene.width - toFloat img.asset.width) / 2, y = (scene.height - toFloat img.asset.height) / 2 }
                        scene
                        model

                ( m3, cmd ) =
                    Edit.commit "Import image"
                        (\doc ->
                            { doc | assets = Dict.insert img.asset.id img.asset doc.assets }
                                |> Document.updateScene scene.id (Scene.insertNode model.editor.isolation 9999 node)
                        )
                        m2
            in
            ( Edit.setSelection [ node.id ] (Edit.mapActiveDoc (\d -> { d | assetUrls = Dict.insert img.asset.id img.url d.assetUrls }) m3), cmd )

        ( _, Err e ) ->
            pure (Edit.toast "error" ("Image import failed: " ++ String.left 200 (D.errorToString e)) model)

        _ ->
            pure model


imageDecoder : D.Decoder { asset : Document.AssetMeta, url : String, name : String }
imageDecoder =
    D.map3 (\a u n -> { asset = a, url = u, name = n })
        (D.field "asset"
            (D.map7 Document.AssetMeta
                (D.field "id" D.string)
                (D.field "name" D.string)
                (D.field "mimeType" D.string)
                (D.field "byteLength" D.int)
                (D.field "sha256" D.string)
                (D.field "width" D.int)
                (D.field "height" D.int)
            )
        )
        (D.field "url" D.string)
        (D.oneOf [ D.field "name" D.string, D.succeed "Image" ])



-- KEYBOARD


handleKeyDown : KeyEvent -> Model -> Update
handleKeyDown ev model =
    let
        e =
            model.editor

        primary =
            if model.isMac then
                ev.meta

            else
                ev.ctrl
    in
    if ev.key == "Escape" then
        escape model

    else if ev.inInput then
        -- let text fields handle their own keys, except the palette/dialog shortcuts
        pure model

    else if model.palette /= Nothing then
        pure model

    else if ev.key == " " && not ev.repeat then
        if e.focus /= Model.CanvasFocus || model.route /= Model.EditorRoute (model.activeDocument |> Maybe.withDefault "") then
            pure (Timeline.togglePlay model)

        else
            pure { model | editor = { e | spaceHeld = True } }

    else if ev.key == " " then
        pure model

    else if ev.key == "Enter" && e.penDraft /= Nothing then
        Canvas.finishPen False model

    else if ev.key == "Enter" && not primary && not ev.shift then
        case ( e.focus, Edit.selection model ) of
            ( Model.LayersFocus, id :: _ ) ->
                update (StartRename id) model

            _ ->
                pure model

    else
        let
            -- tool letters apply anywhere except the timeline, where frame keys win
            contextName =
                case e.focus of
                    Model.TimelineFocus ->
                        "timeline"

                    _ ->
                        "canvas"

            matching =
                Commands.all
                    |> List.filter
                        (\c ->
                            case c.shortcut of
                                Just s ->
                                    Commands.shortcutMatches model.isMac contextName ev s

                                Nothing ->
                                    False
                        )
                    |> List.head
        in
        case matching of
            Just cmd ->
                -- Delete is context sensitive: keys win when the timeline has focus
                if (ev.key == "Delete" || ev.key == "Backspace") && e.focus == Model.TimelineFocus && not (List.isEmpty e.selectedKeys) then
                    Timeline.removeSelectedKeys model

                else if (ev.key == "Delete" || ev.key == "Backspace") && not (List.isEmpty (Edit.selection model)) then
                    update DeleteSelection model

                else
                    runCommandMsg cmd model

            Nothing ->
                keyFallback ev primary model


escape : Model -> Update
escape model =
    let
        e =
            model.editor
    in
    if model.contextMenu /= Nothing || model.openMenu /= Nothing then
        pure { model | contextMenu = Nothing, openMenu = Nothing }

    else if model.picker /= Nothing then
        update PickerCancel model

    else if model.palette /= Nothing then
        pure { model | palette = Nothing }

    else if model.dialog /= NoDialog then
        pure { model | dialog = NoDialog }

    else if not (Dict.isEmpty model.fieldDrafts) then
        pure { model | fieldDrafts = Dict.empty }

    else if e.renamingNode /= Nothing then
        pure { model | editor = { e | renamingNode = Nothing } }

    else if e.penDraft /= Nothing then
        pure { model | editor = { e | penDraft = Nothing, gesture = NoGesture } }

    else if e.gesture /= NoGesture then
        pure (Edit.cancelGesture model)

    else if e.editingText /= Nothing then
        pure { model | editor = { e | editingText = Nothing } }

    else if e.tool /= SelectTool then
        pure { model | editor = { e | tool = SelectTool } }

    else if e.isolation /= Nothing then
        pure { model | editor = { e | isolation = Nothing } }

    else
        case model.route of
            Model.PreviewRoute _ _ ->
                update ClosePreview model

            _ ->
                if not (List.isEmpty e.selectedKeys) then
                    pure { model | editor = { e | selectedKeys = [] } }

                else
                    pure (Edit.setSelection [] model)


keyFallback : KeyEvent -> Bool -> Model -> Update
keyFallback ev primary model =
    let
        e =
            model.editor

        timeline =
            e.focus == Model.TimelineFocus

        stepSize =
            if ev.shift then
                10

            else
                1
    in
    case ev.key of
        "ArrowLeft" ->
            if timeline then
                if List.isEmpty e.selectedKeys then
                    update (StepFrame -stepSize) model

                else
                    Timeline.shiftKeys -stepSize model

            else if e.focus == Model.CanvasFocus then
                Canvas.nudge { x = -(nudgeAmount ev model), y = 0 } model

            else
                pure model

        "ArrowRight" ->
            if timeline then
                if List.isEmpty e.selectedKeys then
                    update (StepFrame stepSize) model

                else
                    Timeline.shiftKeys stepSize model

            else if e.focus == Model.CanvasFocus then
                Canvas.nudge { x = nudgeAmount ev model, y = 0 } model

            else
                pure model

        "ArrowUp" ->
            if e.focus == Model.CanvasFocus then
                Canvas.nudge { x = 0, y = -(nudgeAmount ev model) } model

            else if e.focus == Model.LayersFocus then
                moveLayerSelection -1 model

            else
                pure model

        "ArrowDown" ->
            if e.focus == Model.CanvasFocus then
                Canvas.nudge { x = 0, y = nudgeAmount ev model } model

            else if e.focus == Model.LayersFocus then
                moveLayerSelection 1 model

            else
                pure model

        "Home" ->
            if timeline then
                update (SetPlayhead 0) model

            else
                pure model

        "End" ->
            case ( timeline, Model.activeScene model ) of
                ( True, Just scene ) ->
                    update (SetPlayhead (toFloat scene.durationFrames)) model

                _ ->
                    pure model

        "," ->
            if not primary then
                update (JumpToKey -1) model

            else
                pure model

        "." ->
            if not primary then
                update (JumpToKey 1) model

            else
                pure model

        "v" ->
            toolKey SelectTool ev model

        "a" ->
            if primary then
                pure model

            else
                toolKey DirectSelectTool ev model

        "h" ->
            toolKey HandTool ev model

        "z" ->
            if primary then
                pure model

            else
                toolKey ZoomTool ev model

        _ ->
            pure model


toolKey : Tool -> KeyEvent -> Model -> Update
toolKey tool ev model =
    if ev.ctrl || ev.meta || ev.alt then
        pure model

    else if Model.activeDoc model == Nothing then
        pure model

    else
        update (ChooseTool tool) model


nudgeAmount : KeyEvent -> Model -> Float
nudgeAmount ev model =
    if ev.shift then
        model.preferences.largeNudge

    else
        model.preferences.nudge


moveLayerSelection : Int -> Model -> Update
moveLayerSelection delta model =
    case Model.activeScene model of
        Just scene ->
            let
                visible =
                    visibleLayerOrder scene (Model.activeView model).expanded

                current =
                    Edit.selection model |> List.head

                idx =
                    current |> Maybe.andThen (\id -> indexOf id visible) |> Maybe.withDefault -1

                target =
                    List.drop (clamp 0 (List.length visible - 1) (idx + delta)) visible |> List.head
            in
            case target of
                Just id ->
                    pure (Edit.setSelection [ id ] model)

                Nothing ->
                    pure model

        Nothing ->
            pure model


indexOf : a -> List a -> Maybe Int
indexOf x list =
    List.indexedMap Tuple.pair list |> List.filter (\( _, v ) -> v == x) |> List.head |> Maybe.map Tuple.first


{-| Layer panel order: front-most first, respecting collapsed groups.
-}
visibleLayerOrder : Scene -> Set.Set NodeId -> List NodeId
visibleLayerOrder scene expanded =
    let
        walk ids =
            List.reverse ids
                |> List.concatMap
                    (\id ->
                        id
                            :: (if Set.member id expanded then
                                    Dict.get id scene.nodes |> Maybe.map (.childIds >> walk) |> Maybe.withDefault []

                                else
                                    []
                               )
                    )
    in
    walk scene.rootNodeIds
