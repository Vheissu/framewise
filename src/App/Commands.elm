module App.Commands exposing
    ( Command
    , Shortcut
    , all
    , bindings
    , byId
    , enabled
    , find
    , menuGroups
    , shortcutLabel
    , shortcutMatches
    )

{-| The central command registry. Menus, the command palette, context menus
and keyboard shortcuts all resolve commands through this module, so an action
is defined exactly once with its enablement rule.
-}

import App.Model as Model exposing (Model, Tool(..))
import App.Msg exposing (KeyEvent, Msg(..))
import Dict
import Domain.Easing
import Domain.History as History
import Domain.Node as Node exposing (NodeGeometry(..))
import Domain.Scene
import Export.Format


type alias Shortcut =
    { key : String
    , primary : Bool
    , shift : Bool
    , alt : Bool
    , context : String
    }


type alias Command =
    { id : String
    , label : String
    , category : String
    , shortcut : Maybe Shortcut
    , msg : Msg
    , enable : Model -> Result String ()
    }


sc : String -> Shortcut
sc key =
    { key = key, primary = True, shift = False, alt = False, context = "global" }


scShift : String -> Shortcut
scShift key =
    { key = key, primary = True, shift = True, alt = False, context = "global" }


plain : String -> String -> Shortcut
plain key context =
    { key = key, primary = False, shift = False, alt = False, context = context }


always : Model -> Result String ()
always _ =
    Ok ()


needsDoc : Model -> Result String ()
needsDoc model =
    case Model.activeDoc model of
        Just _ ->
            Ok ()

        Nothing ->
            Err "Open a document first"


needsSelection : Model -> Result String ()
needsSelection model =
    needsDoc model
        |> Result.andThen
            (\_ ->
                if List.isEmpty (Model.activeView model).selection then
                    Err "Select an object first"

                else
                    Ok ()
            )


needsMulti : Model -> Result String ()
needsMulti model =
    needsDoc model
        |> Result.andThen
            (\_ ->
                if List.length (Model.activeView model).selection < 2 then
                    Err "Select two or more objects"

                else
                    Ok ()
            )


needsKeys : Model -> Result String ()
needsKeys model =
    needsDoc model
        |> Result.andThen
            (\_ ->
                if List.isEmpty model.editor.selectedKeys then
                    Err "Select one or more keyframes"

                else
                    Ok ()
            )


needsPathSelection : Model -> Result String ()
needsPathSelection model =
    needsSelection model
        |> Result.andThen
            (\_ ->
                case Model.activeScene model of
                    Just scene ->
                        if
                            (Model.activeView model).selection
                                |> List.filterMap (\id -> Dict.get id scene.nodes)
                                |> List.any
                                    (\n ->
                                        case n.geometry of
                                            Path _ ->
                                                True

                                            _ ->
                                                False
                                    )
                        then
                            Ok ()

                        else
                            Err "Select a path"

                    Nothing ->
                        Err "Open a document first"
            )


canConvert : Model -> Result String ()
canConvert model =
    needsSelection model
        |> Result.andThen
            (\_ ->
                case Model.activeScene model of
                    Just scene ->
                        if
                            (Model.activeView model).selection
                                |> List.filterMap (\id -> Dict.get id scene.nodes)
                                |> List.any (\n -> Node.toPathGeometry n.geometry /= Nothing && not (isPath n))
                        then
                            Ok ()

                        else
                            Err "Select a rectangle, ellipse, line or polygon"

                    Nothing ->
                        Err "Open a document first"
            )


isPath : Node.Node -> Bool
isPath n =
    case n.geometry of
        Path _ ->
            True

        _ ->
            False


canUndo : Model -> Result String ()
canUndo model =
    case Model.activeDoc model of
        Just d ->
            if History.canUndo d.history then
                Ok ()

            else
                Err "Nothing to undo"

        Nothing ->
            Err "Open a document first"


canRedo : Model -> Result String ()
canRedo model =
    case Model.activeDoc model of
        Just d ->
            if History.canRedo d.history then
                Ok ()

            else
                Err "Nothing to redo"

        Nothing ->
            Err "Open a document first"


canRevert : Model -> Result String ()
canRevert model =
    case Model.activeDoc model of
        Just d ->
            case d.savedRevision of
                Just r ->
                    if r /= d.revision then
                        Ok ()

                    else
                        Err "No changes since the last explicit save"

                Nothing ->
                    Err "The document has not been saved to a file yet"

        Nothing ->
            Err "Open a document first"


canPaste : Model -> Result String ()
canPaste model =
    needsDoc model
        |> Result.andThen
            (\_ ->
                case model.internalClipboard of
                    Just _ ->
                        Ok ()

                    Nothing ->
                        Err "Nothing copied yet"
            )


hasGroupSelected : Model -> Result String ()
hasGroupSelected model =
    needsSelection model
        |> Result.andThen
            (\_ ->
                case Model.activeScene model of
                    Just scene ->
                        if
                            (Model.activeView model).selection
                                |> List.filterMap (\id -> Dict.get id scene.nodes)
                                |> List.any Node.isContainer
                        then
                            Ok ()

                        else
                            Err "Select a group"

                    Nothing ->
                        Err "Open a document first"
            )


all : List Command
all =
    [ -- File
      Command "file.new" "New Document" "File" (Just (sc "n")) (RunCommand "file.new") always
    , Command "file.newScene" "New Scene" "File" Nothing AddScene needsDoc
    , Command "file.open" "Open…" "File" (Just (sc "o")) OpenFile always
    , Command "file.importSvg" "Import SVG…" "File" (Just (scShift "i")) ImportSvg needsDoc
    , Command "file.importImage" "Import Image…" "File" Nothing ImportImage needsDoc
    , Command "file.save" "Save" "File" (Just (sc "s")) SaveDocument needsDoc
    , Command "file.saveAs" "Save As…" "File" (Just (scShift "s")) SaveDocumentAs needsDoc
    , Command "file.saveCopy" "Save Copy…" "File" Nothing SaveCopy needsDoc
    , Command "file.saveJson" "Save Snapshot as JSON" "File" Nothing SaveSnapshotJson needsDoc
    , Command "file.revert" "Revert to Saved" "File" Nothing RevertToSaved canRevert
    , Command "file.recover" "Recover Unsaved Work…" "File" Nothing (SetDialog Model.RecoveryDialog) always
    , Command "file.documentSettings" "Document Settings…" "File" Nothing (RunCommand "file.documentSettings") needsDoc
    , Command "file.sceneSettings" "Scene Settings…" "File" Nothing (RunCommand "file.sceneSettings") needsDoc
    , Command "file.export" "Export…" "File" (Just (sc "e")) OpenExport needsDoc
    , Command "file.quickExport" "Quick Export" "File" (Just (scShift "e")) QuickExport needsDoc
    , Command "file.close" "Close Document" "File" (Just (sc "w")) (RunCommand "file.close") needsDoc
    , Command "file.closeAll" "Close All" "File" Nothing (RunCommand "file.closeAll") needsDoc

    -- Edit
    , Command "edit.undo" "Undo" "Edit" (Just (sc "z")) Undo canUndo
    , Command "edit.redo" "Redo" "Edit" (Just (scShift "z")) Redo canRedo
    , Command "edit.cut" "Cut" "Edit" (Just (sc "x")) Cut needsSelection
    , Command "edit.copy" "Copy" "Edit" (Just (sc "c")) Copy needsSelection
    , Command "edit.paste" "Paste" "Edit" (Just (sc "v")) Paste canPaste
    , Command "edit.pasteInPlace" "Paste in Place" "Edit" (Just (scShift "v")) PasteInPlace canPaste
    , Command "edit.copyStyle" "Copy Style" "Edit" Nothing CopyStyle needsSelection
    , Command "edit.pasteStyle" "Paste Style" "Edit" Nothing PasteStyle needsSelection
    , Command "edit.copySvg" "Copy as SVG" "Edit" Nothing CopyAsSvg needsSelection
    , Command "edit.duplicate" "Duplicate" "Edit" (Just (sc "d")) DuplicateSelection needsSelection
    , Command "edit.delete" "Delete" "Edit" (Just (plain "Delete" "canvas")) DeleteSelection needsSelection
    , Command "edit.selectAll" "Select All" "Edit" (Just (sc "a")) SelectAll needsDoc
    , Command "edit.deselect" "Deselect" "Edit" (Just (scShift "a")) Deselect needsSelection
    , Command "edit.invert" "Invert Selection" "Edit" (Just (scShift "i" |> withAlt)) InvertSelection needsDoc
    , Command "edit.findLayer" "Find Layer" "Edit" (Just (sc "f")) (RunCommand "edit.findLayer") needsDoc
    , Command "edit.rename" "Rename" "Edit" (Just (plain "F2" "global")) (RunCommand "edit.rename") needsSelection
    , Command "edit.preferences" "Preferences…" "Edit" (Just (sc ",")) (SetDialog (Model.PreferencesDialog Model.GeneralTab "")) always
    , Command "edit.shortcuts" "Keyboard Shortcuts…" "Edit" (Just (sc "/")) (SetDialog (Model.ShortcutsDialog "")) always

    -- View
    , Command "view.zoomIn" "Zoom In" "View" (Just (sc "=")) (ZoomBy 1.25) needsDoc
    , Command "view.zoomOut" "Zoom Out" "View" (Just (sc "-")) (ZoomBy 0.8) needsDoc
    , Command "view.actualSize" "Actual Size" "View" (Just (sc "1")) (ZoomTo 1) needsDoc
    , Command "view.fitScene" "Fit Scene" "View" (Just (sc "0")) FitScene needsDoc
    , Command "view.fitSelection" "Fit Selection" "View" (Just (sc "2")) FitSelection needsSelection
    , Command "view.rulers" "Toggle Rulers" "View" (Just (scShift "r")) (ToggleEditorFlag "rulers") needsDoc
    , Command "view.grid" "Toggle Grid" "View" (Just (sc "'")) (ToggleEditorFlag "grid") needsDoc
    , Command "view.guides" "Toggle Guides" "View" (Just (sc ";")) (ToggleEditorFlag "guides") needsDoc
    , Command "view.snapGrid" "Snap to Grid" "View" (Just (scShift "'")) (ToggleEditorFlag "snapGrid") needsDoc
    , Command "view.snapObjects" "Snap to Objects" "View" Nothing (ToggleEditorFlag "snapObjects") needsDoc
    , Command "view.snapArtboard" "Snap to Artboard" "View" Nothing (ToggleEditorFlag "snapArtboard") needsDoc
    , Command "view.outline" "Outline Mode" "View" (Just (sc "y")) (ToggleEditorFlag "outline") needsDoc
    , Command "view.motionPaths" "Show Motion Paths" "View" Nothing (ToggleEditorFlag "motionPaths") needsDoc
    , Command "view.onion" "Onion Skin" "View" (Just (scShift "o" |> withAlt)) ToggleOnionSkin needsDoc
    , Command "view.checker" "Checkerboard" "View" Nothing (ToggleEditorFlag "checker") needsDoc
    , Command "view.leftPanel" "Toggle Layers Panel" "View" Nothing (ToggleCollapse "left") needsDoc
    , Command "view.rightPanel" "Toggle Inspector" "View" Nothing (ToggleCollapse "right") needsDoc
    , Command "view.timelinePanel" "Toggle Timeline" "View" Nothing (ToggleCollapse "timeline") needsDoc
    , Command "view.resetWorkspace" "Reset Workspace" "View" Nothing ResetWorkspace always
    , Command "view.preview" "Full Screen Preview" "View" (Just (sc "Enter")) OpenPreview needsDoc

    -- Insert
    , Command "insert.rect" "Rectangle" "Insert" (Just (plain "r" "canvas")) (ChooseTool RectTool) needsDoc
    , Command "insert.ellipse" "Ellipse" "Insert" (Just (plain "o" "canvas")) (ChooseTool EllipseTool) needsDoc
    , Command "insert.line" "Line" "Insert" (Just (plain "l" "canvas")) (ChooseTool LineTool) needsDoc
    , Command "insert.pen" "Pen Path" "Insert" (Just (plain "p" "canvas")) (ChooseTool PenTool) needsDoc
    , Command "insert.polygon" "Polygon" "Insert" (Just (plain "y" "canvas")) (ChooseTool PolygonTool) needsDoc
    , Command "insert.star" "Star" "Insert" Nothing (ChooseTool StarTool) needsDoc
    , Command "insert.text" "Text" "Insert" (Just (plain "t" "canvas")) (ChooseTool TextTool) needsDoc
    , Command "insert.image" "Image…" "Insert" Nothing ImportImage needsDoc
    , Command "insert.group" "Group" "Insert" Nothing (GroupSelection False) needsSelection
    , Command "insert.clipGroup" "Clip Group" "Insert" Nothing (GroupSelection True) needsMulti
    , Command "insert.scene" "Scene" "Insert" Nothing AddScene needsDoc
    , Command "insert.keyframe" "Default Keyframe" "Insert" (Just (plain "k" "global")) AddKeyAtPlayhead needsSelection
    , Command "insert.motionPath" "Motion Path" "Insert" (Just (plain "m" "canvas")) (ChooseTool MotionPathTool) needsSelection

    -- Object
    , Command "object.group" "Group" "Object" (Just (sc "g")) (GroupSelection False) needsSelection
    , Command "object.ungroup" "Ungroup" "Object" (Just (scShift "g")) UngroupSelection hasGroupSelected
    , Command "object.clipToShape" "Clip to Shape" "Object" (Just (sc "7")) (GroupSelection True) needsMulti
    , Command "object.releaseClip" "Release Clip" "Object" Nothing UngroupSelection hasGroupSelected
    , Command "object.convertToPath" "Convert to Path" "Object" (Just (scShift "p")) ConvertToPath canConvert
    , Command "object.togglePath" "Close/Open Path" "Object" Nothing ToggleClosedPath needsPathSelection
    , Command "object.reversePath" "Reverse Path Direction" "Object" Nothing ReversePath needsPathSelection
    , Command "object.flipH" "Flip Horizontal" "Object" (Just (scShift "h")) (FlipSelection True) needsSelection
    , Command "object.flipV" "Flip Vertical" "Object" (Just (scShift "j")) (FlipSelection False) needsSelection
    , Command "object.resetTransform" "Reset Transform" "Object" Nothing ResetTransform needsSelection
    , Command "object.alignLeft" "Align Left" "Object" Nothing (SetAlign "left") needsSelection
    , Command "object.alignCenterH" "Align Horizontal Centres" "Object" Nothing (SetAlign "centerH") needsSelection
    , Command "object.alignRight" "Align Right" "Object" Nothing (SetAlign "right") needsSelection
    , Command "object.alignTop" "Align Top" "Object" Nothing (SetAlign "top") needsSelection
    , Command "object.alignCenterV" "Align Vertical Centres" "Object" Nothing (SetAlign "centerV") needsSelection
    , Command "object.alignBottom" "Align Bottom" "Object" Nothing (SetAlign "bottom") needsSelection
    , Command "object.distributeH" "Distribute Horizontally" "Object" Nothing (Distribute "h") needsMulti
    , Command "object.distributeV" "Distribute Vertically" "Object" Nothing (Distribute "v") needsMulti
    , Command "object.setPivot" "Set Pivot" "Object" Nothing (ChooseTool PivotTool) needsSelection
    , Command "object.createMotionPath" "Create Motion Path from Path" "Object" Nothing CreateMotionPathFromSelection needsMulti

    -- Layer
    , Command "layer.duplicate" "Duplicate Layer" "Layer" Nothing DuplicateSelection needsSelection
    , Command "layer.moveUp" "Move Up" "Layer" (Just (sc "]")) (ReorderSelection "up") needsSelection
    , Command "layer.moveDown" "Move Down" "Layer" (Just (sc "[")) (ReorderSelection "down") needsSelection
    , Command "layer.front" "Bring to Front" "Layer" (Just (scShift "]")) (ReorderSelection "front") needsSelection
    , Command "layer.back" "Send to Back" "Layer" (Just (scShift "[")) (ReorderSelection "back") needsSelection
    , Command "layer.lock" "Lock/Unlock" "Layer" (Just (sc "l")) (RunCommand "layer.lock") needsSelection
    , Command "layer.hide" "Hide/Show" "Layer" (Just (scShift "h" |> withAlt)) (RunCommand "layer.hide") needsSelection
    , Command "layer.isolate" "Isolate Selection" "Layer" Nothing (RunCommand "layer.isolate") hasGroupSelected
    , Command "layer.exitIsolation" "Exit Isolation" "Layer" Nothing ExitIsolation needsDoc
    , Command "layer.selectParent" "Select Parent" "Layer" (Just (scShift "Enter")) SelectParent needsSelection
    , Command "layer.selectChildren" "Select Children" "Layer" Nothing SelectChildren hasGroupSelected
    , Command "layer.expandAll" "Expand All" "Layer" Nothing (RunCommand "layer.expandAll") needsDoc
    , Command "layer.collapseAll" "Collapse All" "Layer" Nothing (RunCommand "layer.collapseAll") needsDoc
    , Command "layer.removeAnimation" "Remove All Animation" "Layer" Nothing (RunCommand "layer.removeAnimation") needsSelection
    , Command "layer.split" "Split Layer at Playhead" "Layer" (Just (scShift "d")) (RunCommand "layer.split") needsSelection
    , Command "layer.trimIn" "Trim In Point to Playhead" "Layer" (Just (plain "[" "global" |> withAlt)) (RunCommand "layer.trimIn") needsSelection
    , Command "layer.trimOut" "Trim Out Point to Playhead" "Layer" (Just (plain "]" "global" |> withAlt)) (RunCommand "layer.trimOut") needsSelection
    , Command "layer.moveIn" "Move In Point to Playhead" "Layer" (Just (plain "[" "global")) (RunCommand "layer.moveIn") needsSelection
    , Command "layer.moveOut" "Move Out Point to Playhead" "Layer" (Just (plain "]" "global")) (RunCommand "layer.moveOut") needsSelection
    , Command "layer.resetSpan" "Reset Layer Span" "Layer" Nothing (RunCommand "layer.resetSpan") needsSelection

    -- Animate
    , Command "animate.addKey" "Add Keyframe" "Animate" Nothing AddKeyAtPlayhead needsSelection
    , Command "animate.removeKeys" "Remove Keyframe" "Animate" (Just (plain "Delete" "timeline")) RemoveSelectedKeys needsKeys
    , Command "animate.autoKey" "Auto-Keyframe" "Animate" (Just (scShift "k")) ToggleAutoKey needsDoc
    , Command "animate.copyKeys" "Copy Keyframes" "Animate" (Just (sc "c" |> inContext "timeline")) CopyKeys needsKeys
    , Command "animate.pasteKeys" "Paste Keyframes" "Animate" (Just (sc "v" |> inContext "timeline")) PasteKeys needsSelection
    , Command "animate.reverse" "Reverse Keyframes" "Animate" Nothing ReverseKeys needsKeys
    , Command "animate.shiftLeft" "Shift Keyframes Left" "Animate" Nothing (ShiftKeys -1) needsKeys
    , Command "animate.shiftRight" "Shift Keyframes Right" "Animate" Nothing (ShiftKeys 1) needsKeys
    , Command "animate.scaleUp" "Scale Keyframes 200%" "Animate" Nothing (ScaleKeys 2) needsKeys
    , Command "animate.scaleDown" "Scale Keyframes 50%" "Animate" Nothing (ScaleKeys 0.5) needsKeys
    , Command "animate.distribute" "Distribute Keyframes" "Animate" Nothing DistributeKeys needsKeys
    , Command "animate.hold" "Easing: Hold" "Animate" Nothing (SetKeyEasing Domain.Easing.Hold) needsKeys
    , Command "animate.linear" "Easing: Linear" "Animate" Nothing (SetKeyEasing Domain.Easing.Linear) needsKeys
    , Command "animate.easeIn" "Easing: Ease In" "Animate" Nothing (SetKeyEasing (Domain.Easing.Preset Domain.Easing.EaseIn)) needsKeys
    , Command "animate.easeOut" "Easing: Ease Out" "Animate" Nothing (SetKeyEasing (Domain.Easing.Preset Domain.Easing.EaseOut)) needsKeys
    , Command "animate.easeInOut" "Easing: Ease In Out" "Animate" Nothing (SetKeyEasing (Domain.Easing.Preset Domain.Easing.EaseInOut)) needsKeys
    , Command "animate.spring" "Easing: Spring" "Animate" Nothing (SetKeyEasing (Domain.Easing.Spring Domain.Easing.defaultSpring)) needsKeys
    , Command "animate.setWorkRange" "Set Work Range to Selection" "Animate" Nothing (RunCommand "animate.setWorkRange") needsKeys
    , Command "animate.rangeStart" "Set Work Range Start to Playhead" "Animate" (Just (plain "b" "global")) (SetRangeEdgeAtPlayhead True) needsDoc
    , Command "animate.rangeEnd" "Set Work Range End to Playhead" "Animate" (Just (plain "n" "global")) (SetRangeEdgeAtPlayhead False) needsDoc
    , Command "animate.clearWorkRange" "Clear Work Range" "Animate" Nothing (SetWorkRange Nothing) needsDoc
    , Command "animate.stagger" "Stagger…" "Animate" Nothing (SetDialog (Model.StaggerDialog { startFrame = "0", spacing = "5", order = "layer" })) needsMulti
    , Command "animate.onion" "Toggle Onion Skin" "Animate" Nothing ToggleOnionSkin needsDoc
    , Command "animate.resetPlayhead" "Reset Playhead" "Animate" (Just (plain "Home" "timeline")) (SetPlayhead 0) needsDoc
    , Command "animate.play" "Play/Pause" "Animate" (Just (plain " " "timeline")) TogglePlay needsDoc
    , Command "animate.speedHalf" "Playback Speed 0.5×" "Animate" Nothing (SetSpeed 0.5) needsDoc
    , Command "animate.speedNormal" "Playback Speed 1×" "Animate" Nothing (SetSpeed 1) needsDoc
    , Command "animate.speedDouble" "Playback Speed 2×" "Animate" Nothing (SetSpeed 2) needsDoc
    , Command "animate.reversePlay" "Reverse Playback" "Animate" Nothing ToggleReverse needsDoc
    , Command "animate.loopOnce" "Loop: Once" "Animate" Nothing (SetLoopMode Domain.Scene.PlayOnce) needsDoc
    , Command "animate.loopRepeat" "Loop: Repeat" "Animate" Nothing (SetLoopMode Domain.Scene.Repeat) needsDoc
    , Command "animate.loopPingPong" "Loop: Ping-pong" "Animate" Nothing (SetLoopMode Domain.Scene.PingPong) needsDoc
    , Command "animate.preview" "Preview" "Animate" Nothing OpenPreview needsDoc

    -- Window
    , Command "window.layers" "Layers" "Window" Nothing (RunCommand "window.layers") needsDoc
    , Command "window.assets" "Assets" "Window" Nothing (RunCommand "window.assets") needsDoc
    , Command "window.scenes" "Scenes" "Window" Nothing (RunCommand "window.scenes") needsDoc
    , Command "window.inspector" "Inspector" "Window" Nothing (ToggleCollapse "right") needsDoc
    , Command "window.timeline" "Timeline" "Window" Nothing (ToggleCollapse "timeline") needsDoc
    , Command "window.history" "History" "Window" (Just (scShift "y" |> withAlt)) (SetDialog Model.HistoryDialog) needsDoc
    , Command "window.exportQueue" "Export Queue" "Window" Nothing OpenExport needsDoc
    , Command "window.timelineFocus" "Timeline Focus" "Window" Nothing (SetFocusContext Model.TimelineFocus) needsDoc
    , Command "window.canvasFocus" "Canvas Focus" "Window" Nothing (SetFocusContext Model.CanvasFocus) needsDoc
    , Command "window.resetLayout" "Reset Layout" "Window" Nothing ResetWorkspace always
    , Command "window.palette" "Command Palette" "Window" (Just (sc "k")) OpenPalette always

    -- Help
    , Command "help.gettingStarted" "Getting Started" "Help" Nothing (SetDialog (Model.DocsDialog "getting-started" "")) always
    , Command "help.concepts" "Editor Concepts" "Help" Nothing (SetDialog (Model.DocsDialog "editor-concepts" "")) always
    , Command "help.export" "Export Compatibility" "Help" Nothing (SetDialog (Model.DocsDialog "export-compatibility" "")) always
    , Command "help.import" "SVG Import Notes" "Help" Nothing (SetDialog (Model.DocsDialog "svg-import" "")) always
    , Command "help.troubleshooting" "Troubleshooting" "Help" Nothing (SetDialog (Model.DocsDialog "troubleshooting" "")) always
    , Command "help.accessibility" "Accessibility" "Help" Nothing (SetDialog (Model.DocsDialog "accessibility" "")) always
    , Command "help.fileFormat" "File Format" "Help" Nothing (SetDialog (Model.DocsDialog "file-format" "")) always
    , Command "help.shortcuts" "Shortcut Reference" "Help" Nothing (SetDialog (Model.ShortcutsDialog "")) always
    , Command "help.whatsNew" "What's New" "Help" Nothing (SetDialog (Model.DocsDialog "whats-new" "")) always
    , Command "help.licences" "Open Source Licences" "Help" Nothing (SetDialog (Model.DocsDialog "licences" "")) always
    , Command "help.about" "About Framewise" "Help" Nothing (SetDialog Model.AboutDialog) always
    ]


{-| Keys that run a command alongside its own shortcut. With the timeline
focused, single letters cut layers the way video editors do: S splits at the
playhead, Q trims away everything before it and W everything after.
-}
extraShortcuts : List ( String, Shortcut )
extraShortcuts =
    [ ( "layer.split", plain "s" "timeline" )
    , ( "layer.trimIn", plain "q" "timeline" )
    , ( "layer.trimOut", plain "w" "timeline" )
    ]


{-| Every key binding: each command's own shortcut, then the extra keys.
-}
bindings : List ( Command, Shortcut )
bindings =
    List.filterMap (\c -> Maybe.map (Tuple.pair c) c.shortcut) all
        ++ List.filterMap (\( id, s ) -> Maybe.map (\c -> ( c, s )) (find id)) extraShortcuts


{-| The `KeyboardEvent.code` of the physical key that types a shortcut key on
a US layout.
-}
codeFor : String -> String
codeFor key =
    case key of
        "[" ->
            "BracketLeft"

        "]" ->
            "BracketRight"

        "/" ->
            "Slash"

        _ ->
            if String.length key == 1 && Char.isAlpha (Maybe.withDefault ' ' (List.head (String.toList key))) then
                "Key" ++ String.toUpper key

            else if String.length key == 1 && Char.isDigit (Maybe.withDefault ' ' (List.head (String.toList key))) then
                "Digit" ++ key

            else
                key


withAlt : Shortcut -> Shortcut
withAlt s =
    { s | alt = True }


inContext : String -> Shortcut -> Shortcut
inContext ctx s =
    { s | context = ctx }


byId : Dict.Dict String Command
byId =
    Dict.fromList (List.map (\c -> ( c.id, c )) all)


find : String -> Maybe Command
find id =
    Dict.get id byId


enabled : Model -> Command -> Result String ()
enabled model cmd =
    cmd.enable model


{-| Menu bar structure: menu title and ordered command ids, with `"-"` as a
separator.
-}
menuGroups : List ( String, List String )
menuGroups =
    [ ( "File"
      , [ "file.new", "file.newScene", "file.open", "-", "file.importSvg", "file.importImage", "-", "file.save", "file.saveAs", "file.saveCopy", "file.saveJson", "file.revert", "file.recover", "-", "file.documentSettings", "file.sceneSettings", "-", "file.export", "file.quickExport", "-", "file.close", "file.closeAll" ]
      )
    , ( "Edit"
      , [ "edit.undo", "edit.redo", "-", "edit.cut", "edit.copy", "edit.paste", "edit.pasteInPlace", "edit.copyStyle", "edit.pasteStyle", "edit.copySvg", "-", "edit.duplicate", "edit.delete", "-", "edit.selectAll", "edit.deselect", "edit.invert", "edit.findLayer", "edit.rename", "-", "edit.preferences", "edit.shortcuts" ]
      )
    , ( "View"
      , [ "view.zoomIn", "view.zoomOut", "view.actualSize", "view.fitScene", "view.fitSelection", "-", "view.rulers", "view.grid", "view.guides", "view.snapGrid", "view.snapObjects", "view.snapArtboard", "-", "view.outline", "view.motionPaths", "view.onion", "view.checker", "-", "view.leftPanel", "view.rightPanel", "view.timelinePanel", "view.resetWorkspace", "-", "view.preview" ]
      )
    , ( "Insert"
      , [ "insert.rect", "insert.ellipse", "insert.line", "insert.pen", "insert.polygon", "insert.star", "insert.text", "insert.image", "-", "insert.group", "insert.clipGroup", "insert.scene", "-", "insert.keyframe", "insert.motionPath" ]
      )
    , ( "Object"
      , [ "object.group", "object.ungroup", "object.clipToShape", "object.releaseClip", "-", "object.convertToPath", "object.togglePath", "object.reversePath", "-", "object.flipH", "object.flipV", "object.resetTransform", "object.setPivot", "-", "object.alignLeft", "object.alignCenterH", "object.alignRight", "object.alignTop", "object.alignCenterV", "object.alignBottom", "object.distributeH", "object.distributeV", "-", "object.createMotionPath" ]
      )
    , ( "Layer"
      , [ "edit.rename", "layer.duplicate", "-", "layer.moveUp", "layer.moveDown", "layer.front", "layer.back", "-", "layer.lock", "layer.hide", "layer.isolate", "layer.exitIsolation", "-", "layer.selectParent", "layer.selectChildren", "layer.expandAll", "layer.collapseAll", "-", "layer.split", "layer.trimIn", "layer.trimOut", "layer.moveIn", "layer.moveOut", "layer.resetSpan", "-", "layer.removeAnimation" ]
      )
    , ( "Animate"
      , [ "animate.addKey", "animate.removeKeys", "animate.autoKey", "-", "animate.copyKeys", "animate.pasteKeys", "animate.reverse", "animate.shiftLeft", "animate.shiftRight", "animate.scaleUp", "animate.scaleDown", "animate.distribute", "-", "animate.hold", "animate.linear", "animate.easeIn", "animate.easeOut", "animate.easeInOut", "animate.spring", "-", "animate.setWorkRange", "animate.rangeStart", "animate.rangeEnd", "animate.clearWorkRange", "animate.stagger", "-", "animate.play", "animate.reversePlay", "animate.speedHalf", "animate.speedNormal", "animate.speedDouble", "animate.loopOnce", "animate.loopRepeat", "animate.loopPingPong", "animate.resetPlayhead", "animate.onion", "animate.preview" ]
      )
    , ( "Window"
      , [ "window.layers", "window.assets", "window.scenes", "window.inspector", "window.timeline", "window.history", "window.exportQueue", "-", "window.timelineFocus", "window.canvasFocus", "window.palette", "-", "window.resetLayout" ]
      )
    , ( "Help"
      , [ "help.gettingStarted", "help.concepts", "help.export", "help.import", "help.troubleshooting", "help.accessibility", "help.fileFormat", "help.shortcuts", "help.whatsNew", "-", "help.licences", "help.about" ]
      )
    ]


shortcutLabel : Bool -> Shortcut -> String
shortcutLabel isMac s =
    let
        mods =
            (if s.primary then
                if isMac then
                    [ "⌘" ]

                else
                    [ "Ctrl" ]

             else
                []
            )
                ++ (if s.shift then
                        if isMac then
                            [ "⇧" ]

                        else
                            [ "Shift" ]

                    else
                        []
                   )
                ++ (if s.alt then
                        if isMac then
                            [ "⌥" ]

                        else
                            [ "Alt" ]

                    else
                        []
                   )

        keyName =
            case s.key of
                " " ->
                    "Space"

                "Enter" ->
                    "↵"

                "Delete" ->
                    "Del"

                k ->
                    String.toUpper k

        joiner =
            if isMac then
                ""

            else
                "+"
    in
    String.join joiner (mods ++ [ keyName ])


shortcutMatches : Bool -> String -> KeyEvent -> Shortcut -> Bool
shortcutMatches isMac context ev s =
    let
        primaryDown =
            if isMac then
                ev.meta

            else
                ev.ctrl

        -- Option on a Mac changes the character (Option+[ is “), so with Alt
        -- held fall back to the physical key
        keyMatches =
            String.toLower ev.key == String.toLower s.key || (s.key == "Delete" && ev.key == "Backspace") || (ev.alt && ev.code /= "" && ev.code == codeFor s.key)

        contextOk =
            s.context == "global" || s.context == context
    in
    keyMatches
        && (s.primary == primaryDown)
        && (s.shift == ev.shift)
        && (s.alt == ev.alt)
        && contextOk
