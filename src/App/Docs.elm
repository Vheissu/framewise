module App.Docs exposing (Page, find, pages, search)

{-| Built-in documentation. Pages are plain structured text rendered by the
docs dialog; nothing is fetched remotely.
-}


type alias Page =
    { id : String
    , title : String
    , sections : List ( String, List String )
    }


pages : List Page
pages =
    [ Page "getting-started"
        "Getting Started"
        [ ( "Create a document", [ "Choose New Document on the welcome screen, pick a preset or enter a size, frame rate and duration, then press Create. The editor opens with one scene and the canvas focused.", "Everything stays in your browser. Nothing is uploaded." ] )
        , ( "Draw something", [ "Pick the Rectangle (R), Ellipse (O), Line (L), Polygon (Y) or Pen (P) tool and drag on the canvas. Hold Shift to constrain proportions. Click without dragging to place a default 100 by 100 shape.", "Use the Text tool (T) to place text; edit the content in the inspector." ] )
        , ( "Animate", [ "Select an object and move the playhead in the timeline. With Auto-Keyframe on (the key icon in the timeline header), changing any animatable value at a non-zero frame records a keyframe and adds a frame-0 baseline automatically.", "Click the diamond next to any inspector field to add or remove a key at the playhead without changing the value.", "Press Space to play, Left and Right to step frames, K to key the selection." ] )
        , ( "Save and export", [ "Save (Ctrl/Cmd+S) writes an editable .framewise file. In Chromium browsers this overwrites the file you picked; elsewhere it downloads a new file each time and the status bar says so.", "Export (Ctrl/Cmd+E) opens the Export Studio, which lists exactly which tracks each format can represent before you download anything." ] )
        ]
    , Page "editor-concepts"
        "Editor Concepts"
        [ ( "Scenes", [ "A document holds one or more scenes. Each scene has its own size, frame rate, duration, background, loop mode and timeline. Scenes export independently." ] )
        , ( "Nodes and layers", [ "Every shape, text, image or group is a node with a stable id and an editable name. The layer panel shows paint order: items lower in the list are painted first. Groups apply their transform and opacity to children. A clip group uses its first child as the clipping shape for the rest." ] )
        , ( "Transforms", [ "Each node stores translation, scale, rotation, skew and a pivot in its parent's space. The pivot is the fixed point for rotate and scale. Use the Pivot tool from the Object menu to move it without moving the artwork." ] )
        , ( "Tracks and keyframes", [ "An animation track targets one property of one node. Keyframes live on integer frames and never share a frame. The easing on a key controls the segment that follows it; the last key has no outgoing segment.", "Values before the first key hold the first key's value; values after the last key hold the last. Disabled tracks fall back to the base value without deleting keys." ] )
        , ( "Isolation", [ "Double-click a group to isolate it. Canvas clicks then select the group's children. Double-click empty canvas or press Escape to leave." ] )
        ]
    , Page "shortcuts"
        "Keyboard Shortcuts"
        [ ( "Context", [ "Shortcuts are context-sensitive. Letter shortcuts for tools only apply when the canvas has focus and no text field is active. Space plays and pauses when the timeline has focus and pans the canvas while held over it." ] ) ]
    , Page "svg-import"
        "SVG Import Notes"
        [ ( "Safety first", [ "Imported SVG is treated as hostile. Scripts, event handlers, foreignObject, external references, DTDs and entity declarations are removed or rejected before anything reaches the page. Framewise never fetches remote resources referenced by an SVG." ] )
        , ( "What becomes editable", [ "rect, circle, ellipse, line, polyline, polygon, path and g elements become editable nodes with their names (from id or inkscape:label), fills, strokes, dashes, opacity and transforms. Linear and radial gradients with userSpaceOnUse or objectBoundingBox units are converted. Simple clipPath references become clip groups." ] )
        , ( "What is reported", [ "Filters, masks, patterns, markers, symbols with use, embedded images, text layout details, CSS animations and SMIL are listed in the compatibility review as approximated or unsupported. Nothing is silently dropped: the review shows counts and affected element ids before the import commits." ] )
        , ( "Arcs and shorthands", [ "Arc commands are converted to cubic Bézier segments (reported as approximated). Quadratic curves and shorthand commands convert exactly." ] )
        ]
    , Page "export-compatibility"
        "Export Compatibility"
        [ ( "One evaluator", [ "Every export reads the same evaluated scene the editor renders. The Export Studio classifies each animation track for the chosen format as Exact, Baked or Unsupported before you download." ] )
        , ( "Static SVG", [ "The evaluated still at a chosen frame. Everything is exact. Raster images are embedded as data URIs." ] )
        , ( "Animated SVG (SMIL)", [ "Transform channels, opacity, visibility, fill and stroke colour, stroke width, dash offset, rectangle size and corner radius, ellipse radii, compatible path morphs, font size, motion paths and blur are exported natively. Smooth easing becomes keySplines; hold, spring and overshoot easing is baked to per-frame samples (reported). Ping-pong is baked into a mirrored cycle. Text content changes and animated clipping shapes are unsupported." ] )
        , ( "SVG + CSS", [ "Transform channels, opacity, visibility, fill and stroke colour, stroke width and dash offset use @keyframes. Geometry attributes, path morphs, motion paths, font size and filters are unsupported in CSS; the report offers SMIL or the HTML player instead." ] )
        , ( "HTML + Framewise Player", [ "A standalone page with a small runtime that evaluates the portable animation JSON. Supports every animatable property including text content. The runtime is CSP-safe, has no network access and exposes play, pause, stop, seekFrame, seekSeconds, setSpeed, setLoop, getCurrentFrame, getDurationSeconds and destroy." ] )
        , ( "PNG", [ "Stills render one frame at 1x, 2x or 3x. Sequences render every frame in the chosen range into a ZIP with a manifest recording fps, size, alpha and index origin." ] )
        , ( "Not available in this build", [ "GIF, APNG, WebM, MP4 and Lottie are listed in the Export Studio as unavailable with the reason. A PNG sequence plus an external encoder is the documented fallback." ] )
        ]
    , Page "troubleshooting"
        "Troubleshooting"
        [ ( "Save says Downloaded, not Saved", [ "Your browser does not expose writable file handles (Firefox and Safari). Each save downloads a new .framewise file. The document is also autosaved locally so you can recover it from the welcome screen." ] )
        , ( "Autosave failed", [ "Browser storage may be full or disabled (private windows). Download a copy with Save As and free up storage in Preferences, Privacy & Storage." ] )
        , ( "An export is blocked", [ "The chosen format cannot express one or more tracks. Switch to the HTML player, or tick Skip Affected Tracks to export without them. The report lists each affected layer." ] )
        , ( "Shortcuts do nothing", [ "Click the canvas or timeline first; tool letters only work when the canvas has focus and no text field is active." ] )
        ]
    , Page "accessibility"
        "Accessibility"
        [ ( "Keyboard", [ "Every menu, dialog, inspector control and the command palette (Ctrl/Cmd+K) is keyboard operable. The layer tree uses arrow keys for navigation. Timeline keys can be selected and edited numerically in the keyframe inspector." ] )
        , ( "Motion", [ "Framewise respects prefers-reduced-motion for its own interface and starts previews paused when it is set. Exports can include a reduced-motion rule that pauses CSS animation. Authored animation is never removed from documents." ] )
        , ( "Announcements", [ "Save state, selection changes, export completion and import problems are announced through a live region." ] )
        ]
    , Page "file-format"
        "File Format"
        [ ( "Container", [ "A .framewise file is a ZIP archive containing manifest.json, document.json, an assets folder of content-addressed binaries and optional thumbnails. Paths are relative and validated; archives with traversal, oversized entries or executable content are rejected." ] )
        , ( "Document", [ "document.json holds scenes, nodes, tracks, keyframes and motion paths with stable string codes for every enum. Numbers must be finite. The schema version is 1; incompatible changes increment it and ship with a migration." ] )
        , ( "Snapshots", [ "Save Snapshot as JSON writes document.json alone for inspection and version control. It omits binary assets and is not a replacement for the archive." ] )
        ]
    , Page "whats-new"
        "What's New"
        [ ( "0.1.0", [ "First public release: vector drawing tools, layers, groups and clip groups, keyframe timeline with easing editor, motion paths, compatible path morphing, autosave and recovery, .framewise archives, SVG import with a compatibility review, and SVG, SMIL, SVG+CSS, HTML player, PNG and PNG sequence exports." ] ) ]
    , Page "licences"
        "Open Source Licences"
        [ ( "Framewise", [ "MIT licence." ] )
        , ( "Runtime dependencies", [ "DOMPurify (Apache-2.0 or MPL-2.0) for SVG sanitisation. fflate (MIT) for ZIP archives.", "Elm packages: elm/core, elm/browser, elm/html, elm/svg, elm/json, elm/url, elm/time (BSD-3-Clause)." ] )
        , ( "Icons and fonts", [ "Interface icons are original line drawings included in this repository under the MIT licence. The interface uses the system font stack; no fonts are downloaded." ] )
        ]
    ]


find : String -> Maybe Page
find id =
    List.filter (\p -> p.id == id) pages |> List.head


search : String -> List ( Page, String, String )
search query =
    let
        q =
            String.toLower (String.trim query)
    in
    if String.isEmpty q then
        []

    else
        pages
            |> List.concatMap
                (\p ->
                    p.sections
                        |> List.concatMap
                            (\( heading, paragraphs ) ->
                                paragraphs
                                    |> List.filter (\para -> String.contains q (String.toLower para) || String.contains q (String.toLower heading))
                                    |> List.map (\para -> ( p, heading, para ))
                            )
                )
