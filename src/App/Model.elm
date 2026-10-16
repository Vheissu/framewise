module App.Model exposing
    ( BarEdge(..)
    , Capabilities
    , ColorTarget(..)
    , ContextMenu
    , ContextTarget(..)
    , Dialog(..)
    , DocForm
    , EditorState
    , ExportForm
    , ExportJob
    , FieldId
    , Flags
    , FocusContext(..)
    , Gesture(..)
    , Handle(..)
    , ImportReview
    , KeyRef
    , LeftTab(..)
    , Model
    , OpenDocument
    , PaletteState
    , PenDraft
    , PickerState
    , Playback
    , PrefTab(..)
    , Preferences
    , RangeEdit(..)
    , RecentEntry
    , RecoveryEntry
    , Route(..)
    , SaveStatus(..)
    , SceneForm
    , SceneView
    , Theme(..)
    , Toast
    , Tool(..)
    , activeDoc
    , activeScene
    , activeView
    , defaultCapabilities
    , defaultDocForm
    , defaultEditor
    , defaultExportForm
    , defaultPreferences
    , defaultSceneView
    , sceneFormFor
    , themeFromCode
    , themeToCode
    , toolFromCode
    , toolLabel
    , toolShortcut
    )

import Browser.Navigation as Nav
import Dict exposing (Dict)
import Domain.Color exposing (Rgba)
import Domain.Document exposing (Document)
import Domain.Fps as Fps exposing (Fps)
import Domain.History exposing (History)
import Domain.Path exposing (PathGeometry)
import Domain.Property exposing (PropertyPath)
import Domain.Scene as Scene exposing (Scene)
import Domain.Transform exposing (Transform)
import Domain.Validation
import Domain.Vec2 exposing (Vec2)
import Export.Format exposing (Format)
import Json.Encode as E
import Set exposing (Set)
import Shared.Ids exposing (AssetId, DocumentId, KeyframeId, NodeId, SceneId, TrackId)
import Time


type Route
    = Welcome
    | EditorRoute DocumentId
    | PreviewRoute DocumentId SceneId
    | NotFound


type alias Flags =
    { basePath : String
    , isMac : Bool
    , ids : List String
    , capabilities : Capabilities
    , preferences : Maybe E.Value
    , recents : List RecentEntry
    , recoveries : List RecoveryEntry
    , now : Int
    , reducedMotion : Bool
    , version : String
    , layout : Maybe E.Value
    }


type alias Capabilities =
    { nativeFilePickers : Bool
    , indexedDb : Bool
    , clipboardWrite : Bool
    , clipboardRead : Bool
    , offscreenCanvas : Bool
    , webCodecs : Bool
    , serviceWorker : Bool
    , persistentStorage : Bool
    , broadcastChannel : Bool
    , storageEstimate : Maybe { usage : Int, quota : Int }
    }


defaultCapabilities : Capabilities
defaultCapabilities =
    { nativeFilePickers = False
    , indexedDb = False
    , clipboardWrite = False
    , clipboardRead = False
    , offscreenCanvas = False
    , webCodecs = False
    , serviceWorker = False
    , persistentStorage = False
    , broadcastChannel = False
    , storageEstimate = Nothing
    }


type alias RecentEntry =
    { documentId : DocumentId
    , name : String
    , width : Float
    , height : Float
    , sceneCount : Int
    , modifiedAt : Int
    , revision : Int
    , hasAutosave : Bool
    , fileName : Maybe String
    }


type alias RecoveryEntry =
    { documentId : DocumentId
    , name : String
    , revision : Int
    , savedRevision : Maybe Int
    , checkpointAt : Int
    , byteLength : Int
    , decodable : Bool
    }


type Theme
    = SystemTheme
    | LightTheme
    | DarkTheme


themeToCode : Theme -> String
themeToCode t =
    case t of
        SystemTheme ->
            "system"

        LightTheme ->
            "light"

        DarkTheme ->
            "dark"


themeFromCode : String -> Theme
themeFromCode s =
    case s of
        "light" ->
            LightTheme

        "dark" ->
            DarkTheme

        _ ->
            SystemTheme


type alias Preferences =
    { theme : Theme
    , compact : Bool
    , reducedMotionOverride : Maybe Bool
    , autosaveIdleMs : Int
    , recentLimit : Int
    , gridSpacing : Float
    , gridSubdivisions : Int
    , defaultFps : Fps
    , defaultDuration : Int
    , defaultWidth : Float
    , defaultHeight : Float
    , autoKeyDefault : Bool
    , nudge : Float
    , largeNudge : Float
    , snapTolerance : Float
    , historyLimit : Int
    , confirmDelete : Bool
    , showDiagnostics : Bool
    , offKeyPolicy : String
    , timelineSnap : Bool
    }


defaultPreferences : Preferences
defaultPreferences =
    { theme = SystemTheme
    , compact = False
    , reducedMotionOverride = Nothing
    , autosaveIdleMs = 1500
    , recentLimit = 12
    , gridSpacing = 10
    , gridSubdivisions = 1
    , defaultFps = Fps.fps 30 1
    , defaultDuration = 60
    , defaultWidth = 400
    , defaultHeight = 400
    , autoKeyDefault = True
    , nudge = 1
    , largeNudge = 10
    , snapTolerance = 6
    , historyLimit = 200
    , confirmDelete = False
    , showDiagnostics = False
    , offKeyPolicy = "nearest"
    , timelineSnap = True
    }


type SaveStatus
    = SaveIdle
    | Saving
    | SaveFailed String


type alias SceneView =
    { pan : Vec2
    , zoom : Float
    , playhead : Float
    , selection : List NodeId
    , expanded : Set NodeId
    , timelinePixelsPerFrame : Float
    , timelineScroll : Float
    , fitted : Bool
    , timelineFitted : Bool
    }


defaultSceneView : SceneView
defaultSceneView =
    { pan = { x = 0, y = 0 }
    , zoom = 1
    , playhead = 0
    , selection = []
    , expanded = Set.empty
    , timelinePixelsPerFrame = 10
    , timelineScroll = 0
    , fitted = False
    , timelineFitted = False
    }


type alias OpenDocument =
    { document : Document
    , revision : Int
    , savedRevision : Maybe Int
    , autosavedRevision : Maybe Int
    , autosaveFailed : Maybe String
    , saveStatus : SaveStatus
    , lastSaveWasDownload : Bool
    , history : History Document
    , fileName : Maybe String
    , fileToken : Maybe String
    , activeSceneId : SceneId
    , sceneViews : Dict SceneId SceneView
    , assetUrls : Dict AssetId String
    , validation : List Domain.Validation.Issue
    , isRecoveryCopy : Bool
    }


type Tool
    = SelectTool
    | DirectSelectTool
    | HandTool
    | ZoomTool
    | PenTool
    | RectTool
    | EllipseTool
    | LineTool
    | PolygonTool
    | StarTool
    | TextTool
    | PivotTool
    | MotionPathTool


toolLabel : Tool -> String
toolLabel t =
    case t of
        SelectTool ->
            "Select"

        DirectSelectTool ->
            "Direct Select"

        HandTool ->
            "Hand"

        ZoomTool ->
            "Zoom"

        PenTool ->
            "Pen"

        RectTool ->
            "Rectangle"

        EllipseTool ->
            "Ellipse"

        LineTool ->
            "Line"

        PolygonTool ->
            "Polygon"

        StarTool ->
            "Star"

        TextTool ->
            "Text"

        PivotTool ->
            "Pivot"

        MotionPathTool ->
            "Motion Path"


toolShortcut : Tool -> Maybe String
toolShortcut t =
    case t of
        SelectTool ->
            Just "V"

        DirectSelectTool ->
            Just "A"

        HandTool ->
            Just "H"

        ZoomTool ->
            Just "Z"

        PenTool ->
            Just "P"

        RectTool ->
            Just "R"

        EllipseTool ->
            Just "O"

        LineTool ->
            Just "L"

        PolygonTool ->
            Just "Y"

        StarTool ->
            Nothing

        TextTool ->
            Just "T"

        PivotTool ->
            Nothing

        MotionPathTool ->
            Just "M"


toolFromCode : String -> Maybe Tool
toolFromCode s =
    case s of
        "select" ->
            Just SelectTool

        "direct" ->
            Just DirectSelectTool

        "hand" ->
            Just HandTool

        "zoom" ->
            Just ZoomTool

        "pen" ->
            Just PenTool

        "rect" ->
            Just RectTool

        "ellipse" ->
            Just EllipseTool

        "line" ->
            Just LineTool

        "polygon" ->
            Just PolygonTool

        "star" ->
            Just StarTool

        "text" ->
            Just TextTool

        "pivot" ->
            Just PivotTool

        "motion" ->
            Just MotionPathTool

        _ ->
            Nothing


type Handle
    = HandleNW
    | HandleN
    | HandleNE
    | HandleE
    | HandleSE
    | HandleS
    | HandleSW
    | HandleW
    | HandleRotate


type alias KeyRef =
    { trackId : TrackId, keyId : KeyframeId }


type Gesture
    = NoGesture
    | PendingPress { start : Vec2, screenStart : Vec2, hit : Maybe NodeId, shift : Bool, alt : Bool }
    | DragMove { start : Vec2, current : Vec2, originals : List ( NodeId, Transform ), snapLines : List ( Bool, Float ), duplicated : Bool }
    | DragResize { handle : Handle, start : Vec2, current : Vec2, originals : List ( NodeId, Transform ), originalScene : Scene, shift : Bool }
    | DragRotate { center : Vec2, startAngle : Float, originals : List ( NodeId, Transform ), originalScene : Scene }
    | DragPivot { nodeId : NodeId, original : Transform }
    | Marquee { start : Vec2, current : Vec2, additive : Bool }
    | DrawShape { start : Vec2, current : Vec2, shift : Bool, alt : Bool }
    | Panning { screenStart : Vec2, startPan : Vec2 }
    | ZoomMarquee { start : Vec2, current : Vec2 }
    | DragAnchor { nodeId : NodeId, subpath : Int, index : Int, original : PathGeometry, start : Vec2, isHandle : Bool, mirror : Bool }
    | PenDragHandle { start : Vec2, current : Vec2 }
    | ScrubPlayhead
    | DragWorkRange { edit : RangeEdit, pressFrame : Float, originalScene : Scene }
    | MarqueeKeys { startFrame : Float, startY : Float, currentFrame : Float, currentY : Float, base : List KeyRef }
    | DragLayerBar { nodeIds : List NodeId, edge : BarEdge, startFrame : Float, delta : Int, originalScene : Scene }
    | DragKeys { keys : List ( TrackId, KeyframeId, Int ), startFrame : Float, delta : Int, originalScene : Scene }
    | DragSplitter { which : String, start : Float, original : Float }
    | DragLayer { nodeId : NodeId }


{-| What a drag on the work area strip changes: one end follows the pointer
while the other stays at the given frame, or the whole range slides with the
pointer from the frame where it was grabbed.
-}
type BarEdge
    = BarBody
    | BarIn
    | BarOut


type RangeEdit
    = RangeFrom Int
    | RangeSlide { start : Int, end : Int, grab : Int }


type alias PenDraft =
    { nodeId : Maybe NodeId
    , subpathStart : Vec2
    , segments : List Domain.Path.Segment
    , lastHandle : Maybe Vec2
    , closed : Bool
    , parent : Maybe NodeId
    }


type alias Playback =
    { playing : Bool
    , startTime : Float
    , startFrame : Float
    , speed : Float
    , reverse : Bool
    , loopOverride : Maybe Scene.PlaybackMode
    }


type FocusContext
    = CanvasFocus
    | TimelineFocus
    | LayersFocus
    | OtherFocus


type LeftTab
    = LayersTab
    | AssetsTab
    | ScenesTab


type alias EditorState =
    { tool : Tool
    , previousTool : Maybe Tool
    , gesture : Gesture
    , hover : Maybe NodeId
    , canvasRect : { left : Float, top : Float, width : Float, height : Float }
    , timelineRect : { left : Float, top : Float, width : Float, height : Float }
    , timelinePointer : { x : Float, y : Float, shift : Bool }
    , showFilmstrip : Bool
    , spaceHeld : Bool
    , penDraft : Maybe PenDraft
    , playback : Playback
    , autoKey : Bool
    , showGrid : Bool
    , snapToGrid : Bool
    , snapToObjects : Bool
    , snapToArtboard : Bool
    , showRulers : Bool
    , showGuides : Bool
    , outlineMode : Bool
    , showMotionPaths : Bool
    , onionSkin : Bool
    , onionBefore : Int
    , onionAfter : Int
    , checkerboard : Bool
    , selectedKeys : List KeyRef
    , timelineHeight : Float
    , leftWidth : Float
    , rightWidth : Float
    , leftCollapsed : Bool
    , rightCollapsed : Bool
    , timelineCollapsed : Bool
    , leftTab : LeftTab
    , isolation : Maybe NodeId
    , focus : FocusContext
    , editingText : Maybe NodeId
    , layerFilter : String
    , showAllProperties : Bool
    , renamingNode : Maybe NodeId
    , collapsedSections : Set String
    , dropTarget : Maybe ( Maybe NodeId, Int )
    , nextKeyCollision : Maybe String
    , gestureOrigin : Maybe Document
    , renameDraft : String
    , keyClipboard : Maybe (List ( PropertyPath, Int, E.Value ))
    }


defaultEditor : Preferences -> EditorState
defaultEditor prefs =
    { tool = SelectTool
    , previousTool = Nothing
    , gesture = NoGesture
    , hover = Nothing
    , canvasRect = { left = 0, top = 0, width = 800, height = 600 }
    , timelineRect = { left = 0, top = 0, width = 800, height = 200 }
    , timelinePointer = { x = 0, y = 0, shift = False }
    , showFilmstrip = True
    , spaceHeld = False
    , penDraft = Nothing
    , playback = { playing = False, startTime = 0, startFrame = 0, speed = 1, reverse = False, loopOverride = Nothing }
    , autoKey = prefs.autoKeyDefault
    , showGrid = False
    , snapToGrid = False
    , snapToObjects = True
    , snapToArtboard = True
    , showRulers = True
    , showGuides = True
    , outlineMode = False
    , showMotionPaths = True
    , onionSkin = False
    , onionBefore = 2
    , onionAfter = 2
    , checkerboard = True
    , selectedKeys = []
    , timelineHeight = 250
    , leftWidth = 260
    , rightWidth = 310
    , leftCollapsed = False
    , rightCollapsed = False
    , timelineCollapsed = False
    , leftTab = LayersTab
    , isolation = Nothing
    , focus = CanvasFocus
    , editingText = Nothing
    , layerFilter = ""
    , showAllProperties = False
    , renamingNode = Nothing
    , collapsedSections = Set.empty
    , dropTarget = Nothing
    , nextKeyCollision = Nothing
    , gestureOrigin = Nothing
    , renameDraft = ""
    , keyClipboard = Nothing
    }


type alias DocForm =
    { title : String
    , sceneName : String
    , width : String
    , height : String
    , fpsPreset : String
    , fpsNumerator : String
    , fpsDenominator : String
    , duration : String
    , transparent : Bool
    , background : Rgba
    , preset : String
    , search : String
    , error : Maybe String
    }


defaultDocForm : Preferences -> DocForm
defaultDocForm prefs =
    { title = "Untitled"
    , sceneName = "Scene 1"
    , width = String.fromFloat prefs.defaultWidth
    , height = String.fromFloat prefs.defaultHeight
    , fpsPreset = Fps.toLabel prefs.defaultFps
    , fpsNumerator = String.fromInt prefs.defaultFps.numerator
    , fpsDenominator = String.fromInt prefs.defaultFps.denominator
    , duration = String.fromInt prefs.defaultDuration
    , transparent = True
    , background = Domain.Color.white
    , preset = "custom"
    , search = ""
    , error = Nothing
    }


type alias SceneForm =
    { sceneId : SceneId
    , name : String
    , description : String
    , width : String
    , height : String
    , resizeMode : String
    , fpsNumerator : String
    , fpsDenominator : String
    , fpsMode : String
    , duration : String
    , keepOutOfRange : Bool
    , transparent : Bool
    , background : Rgba
    , playbackMode : Scene.PlaybackMode
    , workStart : String
    , workEnd : String
    , useWorkRange : Bool
    , error : Maybe String
    }


sceneFormFor : Scene -> SceneForm
sceneFormFor scene =
    { sceneId = scene.id
    , name = scene.name
    , description = scene.description
    , width = String.fromFloat scene.width
    , height = String.fromFloat scene.height
    , resizeMode = "keep"
    , fpsNumerator = String.fromInt scene.fps.numerator
    , fpsDenominator = String.fromInt scene.fps.denominator
    , fpsMode = "time"
    , duration = String.fromInt scene.durationFrames
    , keepOutOfRange = True
    , transparent = scene.background == Scene.Transparent
    , background =
        case scene.background of
            Scene.SolidBackground c ->
                c

            Scene.Transparent ->
                Domain.Color.white
    , playbackMode = scene.playbackMode
    , workStart = scene.workRange |> Maybe.map (.start >> String.fromInt) |> Maybe.withDefault "0"
    , workEnd = scene.workRange |> Maybe.map (.end >> String.fromInt) |> Maybe.withDefault (String.fromInt scene.durationFrames)
    , useWorkRange = scene.workRange /= Nothing
    , error = Nothing
    }


type alias ExportForm =
    { format : Format
    , allScenes : Bool
    , frame : String
    , scale : Float
    , includeBackground : Bool
    , title : String
    , description : String
    , skipUnsupported : Bool
    , rangeStart : String
    , rangeEnd : String
    , indexOrigin : String
    , reducedMotionPause : Bool
    , showReport : Bool
    }


defaultExportForm : Scene -> Float -> ExportForm
defaultExportForm scene playhead =
    { format = Export.Format.AnimatedSvg
    , allScenes = False
    , frame = String.fromInt (round playhead)
    , scale = 1
    , includeBackground = True
    , title = scene.name
    , description = scene.description
    , skipUnsupported = False
    , rangeStart = "0"
    , rangeEnd = String.fromInt (scene.durationFrames - 1)
    , indexOrigin = "0"
    , reducedMotionPause = True
    , showReport = True
    }


type alias ExportJob =
    { id : String
    , label : String
    , status : String
    , progress : Maybe ( Int, Int )
    , message : Maybe String
    , fileName : Maybe String
    , revision : Int
    }


type alias ImportReview =
    { fileName : String
    , nodes : E.Value
    , supportedCount : Int
    , approximated : List String
    , unsupported : List String
    , warnings : List String
    , width : Maybe Float
    , height : Maybe Float
    , asNewDocument : Bool
    }


type PrefTab
    = GeneralTab
    | CanvasTab
    | AnimationTab
    | PerformanceTab
    | ShortcutsTab
    | StorageTab
    | AboutTab


type Dialog
    = NoDialog
    | NewDocumentDialog DocForm
    | SceneSettingsDialog SceneForm
    | ImportReviewDialog ImportReview
    | ExportDialog ExportForm
    | PreferencesDialog PrefTab String
    | ShortcutsDialog String
    | AboutDialog
    | DocsDialog String String
    | RecoveryDialog
    | HistoryDialog
    | StaggerDialog { startFrame : String, spacing : String, order : String }
    | ConfirmDialog { title : String, body : String, confirmLabel : String, onConfirm : String }
    | DocumentSettingsDialog { name : String, description : String }
    | ErrorDialog String String
    | FpsRetimeDialog SceneForm


type ColorTarget
    = FillTarget
    | StrokeTarget
    | BackgroundTarget
    | FormBackgroundTarget


type alias PickerState =
    { target : ColorTarget
    , initial : Rgba
    , current : Rgba
    , hexDraft : String
    , anchor : { x : Float, y : Float }
    }


type alias PaletteState =
    { query : String
    , index : Int
    }


type ContextTarget
    = CanvasContext (Maybe NodeId)
    | LayerContext NodeId
    | KeyframeContext KeyRef
    | TrackContext TrackId
    | SceneTabContext SceneId


type alias ContextMenu =
    { x : Float, y : Float, target : ContextTarget }


type alias Toast =
    { id : Int, message : String, kind : String }


type alias FieldId =
    String


type alias Model =
    { key : Nav.Key
    , route : Route
    , basePath : String
    , isMac : Bool
    , version : String
    , capabilities : Capabilities
    , reducedMotion : Bool
    , documents : Dict DocumentId OpenDocument
    , openOrder : List DocumentId
    , activeDocument : Maybe DocumentId
    , editor : EditorState
    , preferences : Preferences
    , ids : List String
    , idRequestPending : Bool
    , idCounter : Int
    , recents : List RecentEntry
    , recoveries : List RecoveryEntry
    , dialog : Dialog
    , openMenu : Maybe String
    , menuIndex : Int
    , palette : Maybe PaletteState
    , contextMenu : Maybe ContextMenu
    , picker : Maybe PickerState
    , fieldDrafts : Dict FieldId String
    , toasts : List Toast
    , toastSeq : Int
    , exportJobs : List ExportJob
    , now : Time.Posix
    , liveAnnouncement : String
    , internalClipboard : Maybe E.Value
    , pendingRequests : Dict String String
    , offlineReady : Bool
    , pendingExampleOpen : Maybe String
    , dragOverlay : Bool
    , tabConflicts : List DocumentId
    }


activeDoc : Model -> Maybe OpenDocument
activeDoc model =
    model.activeDocument |> Maybe.andThen (\id -> Dict.get id model.documents)


activeScene : Model -> Maybe Scene
activeScene model =
    activeDoc model |> Maybe.andThen (\d -> Dict.get d.activeSceneId d.document.scenes)


activeView : Model -> SceneView
activeView model =
    activeDoc model
        |> Maybe.andThen (\d -> Dict.get d.activeSceneId d.sceneViews)
        |> Maybe.withDefault defaultSceneView
