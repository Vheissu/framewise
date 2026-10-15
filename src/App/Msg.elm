module App.Msg exposing
    ( KeyEvent
    , Msg(..)
    , PointerEvent
    , WheelEvent
    )

import App.Model exposing (ColorTarget, ContextTarget, Dialog, Handle, KeyRef, LeftTab, PrefTab, Tool)
import Browser
import Domain.Color exposing (Rgba)
import Domain.Easing exposing (Easing)
import Domain.Property exposing (PropertyPath)
import Domain.Scene exposing (PlaybackMode)
import Export.Format exposing (Format)
import Json.Encode as E
import Shared.Ids exposing (DocumentId, KeyframeId, NodeId, SceneId, TrackId)
import Time
import Url exposing (Url)


type alias PointerEvent =
    { clientX : Float
    , clientY : Float
    , button : Int
    , shift : Bool
    , alt : Bool
    , ctrl : Bool
    , meta : Bool
    , hitNode : Maybe String
    , handle : Maybe String
    , anchor : Maybe String
    , detail : Int
    }


type alias WheelEvent =
    { clientX : Float
    , clientY : Float
    , deltaX : Float
    , deltaY : Float
    , ctrl : Bool
    , meta : Bool
    , shift : Bool
    }


type alias KeyEvent =
    { key : String
    , code : String
    , ctrl : Bool
    , meta : Bool
    , shift : Bool
    , alt : Bool
    , inInput : Bool
    , repeat : Bool
    }


type Msg
    = NoOp
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | FromJs E.Value
    | Tick Time.Posix
    | ClockNow Time.Posix
      -- commands & navigation
    | RunCommand String
    | GoWelcome
    | OpenDocumentTab DocumentId
    | CloseDocument DocumentId
    | ConfirmCloseDocument DocumentId
    | OpenExample String
    | OpenRecent DocumentId
    | RemoveRecent DocumentId
    | OpenRecovery DocumentId
    | DiscardRecovery DocumentId
    | DownloadRecovery DocumentId
      -- dialogs & ui chrome
    | SetDialog Dialog
    | CloseDialog
    | DocFormChanged (App.Model.DocForm -> App.Model.DocForm)
    | SubmitNewDocument
    | SceneFormChanged (App.Model.SceneForm -> App.Model.SceneForm)
    | SubmitSceneSettings
    | DocSettingsChanged String String
    | SubmitDocumentSettings
    | ToggleMenu String
    | HoverMenu String
    | CloseMenus
    | OpenPalette
    | PaletteInput String
    | PaletteMove Int
    | PaletteRun
    | ClosePalette
    | OpenContextMenu Float Float ContextTarget
    | CloseContextMenu
    | DismissToast Int
    | ExpireToasts
    | SetLeftTab LeftTab
    | ToggleSection String
    | SetPrefTab PrefTab
    | PrefSearch String
    | PreferenceChanged (App.Model.Preferences -> App.Model.Preferences)
    | ResetPreferences
    | ResetWorkspace
    | ClearStorage String
    | RequestPersistentStorage
    | SetDocsPage String
    | DocsSearch String
    | ShortcutSearch String
    | ConfirmAccepted String
    | ToggleCollapse String
      -- tools & canvas
    | ChooseTool Tool
    | CanvasPointerDown PointerEvent
    | CanvasPointerMove PointerEvent
    | CanvasPointerUp PointerEvent
    | CanvasDoubleClick PointerEvent
    | CanvasWheel WheelEvent
    | CanvasRect { left : Float, top : Float, width : Float, height : Float }
    | TimelineRect { left : Float, top : Float, width : Float, height : Float }
    | WindowPointerMove Float Float Bool
    | WindowPointerUp Float Float
    | KeyDown KeyEvent
    | KeyUp KeyEvent
    | SetFocusContext App.Model.FocusContext
    | ZoomTo Float
    | ZoomBy Float
    | FitScene
    | FitSelection
    | ToggleEditorFlag String
    | SetHover (Maybe NodeId)
    | FinishPen
    | CancelPen
    | ExitIsolation
    | EnterIsolation NodeId
      -- selection / layers
    | SelectNodes (List NodeId) Bool
    | SelectAll
    | Deselect
    | InvertSelection
    | ToggleExpanded NodeId
    | SetHidden NodeId Bool
    | SetLocked NodeId Bool
    | StartRename NodeId
    | RenameInput String
    | CommitRename
    | CancelRename
    | LayerFilter String
    | LayerDragStart NodeId
    | LayerDragOver (Maybe NodeId) Int
    | LayerDrop
    | LayerDragEnd
    | MoveSelection Int
    | ReorderSelection String
    | GroupSelection Bool
    | UngroupSelection
    | DeleteSelection
    | DuplicateSelection
    | ConvertToPath
    | ToggleClosedPath
    | ReversePath
    | SetAlign String
    | Distribute String
    | FlipSelection Bool
    | ResetTransform
    | SelectParent
    | SelectChildren
    | SelectScene SceneId
    | AddScene
    | DuplicateScene SceneId
    | DeleteScene SceneId
    | ReorderScene SceneId Int
      -- inspector
    | FieldInput String String
    | FieldCommit String
    | FieldCancel String
    | FieldStep String Float
    | SetNodeProperty NodeId PropertyPath Domain.Property.PropertyValue
    | SetNodeFill NodeId Bool
    | SetNodeStroke NodeId Bool
    | SetStrokeOption NodeId String String
    | SetTextOption NodeId String String
    | SetEffect NodeId String
    | SetSceneBackground Bool
    | SetSceneOption String String
    | OpenPicker ColorTarget Rgba Float Float
    | PickerChange Rgba
    | PickerHex String
    | PickerConfirm
    | PickerCancel
    | SetMotionOrient NodeId Bool
    | DetachMotionPath NodeId
    | CreateMotionPathFromSelection
      -- timeline
    | SetPlayhead Float
    | StepFrame Int
    | JumpToKey Int
    | TogglePlay
    | StopPlayback
    | SetSpeed Float
    | ToggleReverse
    | SetLoopMode PlaybackMode
    | ToggleAutoKey
    | ToggleKeyAt NodeId PropertyPath
    | AddKeyAtPlayhead
    | RemoveSelectedKeys
    | RemoveTrack TrackId
    | RemoveAllAnimation NodeId
    | SetTrackEnabled TrackId Bool
    | SetTrackLocked TrackId Bool
    | SelectKey KeyRef Bool
    | SelectKeysInRange (List KeyRef)
    | SetKeyEasing Easing
    | SetKeyFrame KeyRef Int
    | SetKeyValue KeyRef Domain.Property.PropertyValue
    | ShiftKeys Int
    | ScaleKeys Float
    | DistributeKeys
    | ReverseKeys
    | CopyKeys
    | PasteKeys
    | TimelinePointerDown PointerEvent
    | TimelineRulerDown PointerEvent
    | KeyPointerDown KeyRef PointerEvent
    | TimelineZoom Float
    | TimelineScroll Float
    | ToggleAllProperties
    | SetWorkRange (Maybe ( Int, Int ))
    | StaggerFormChanged String String
    | ApplyStagger
    | SplitterDown String Float
    | ToggleOnionSkin
    | SetOnion Int Int
      -- history / clipboard
    | Undo
    | Redo
    | HistoryJump Int
    | Copy
    | Cut
    | Paste
    | PasteInPlace
    | CopyStyle
    | PasteStyle
    | CopyAsSvg
      -- documents & persistence
    | NewDocumentFromPreset String
    | SaveDocument
    | SaveDocumentAs
    | SaveCopy
    | SaveSnapshotJson
    | RevertToSaved
    | OpenFile
    | ImportSvg
    | ImportImage
    | ImportReviewAccept
    | ImportReviewCancel
    | AutosaveTick DocumentId Int
    | SetDirtyGuard
      -- export
    | OpenExport
    | ExportFormChanged (App.Model.ExportForm -> App.Model.ExportForm)
    | SelectExportFormat Format
    | RunExport
    | CancelExportJob String
    | RetryExportJob String
    | QuickExport
      -- preview
    | OpenPreview
    | ClosePreview
    | PreviewSeek Float
    | PreviewToggleFull
      -- announcements
    | Announce String
