module App.Examples exposing (Example, all, build, find)

{-| Bundled example documents. Each is constructed in Elm so it is always
valid against the current schema and needs no network access. Opening an
example copies it into a new document with a fresh document id.
-}

import Dict
import Domain.Color as Color
import Domain.Document as Document exposing (Document)
import Domain.Easing exposing (Easing(..), Preset(..))
import Domain.Fps as Fps
import Domain.Keyframe as Keyframe exposing (Track)
import Domain.Node as Node exposing (Node, NodeGeometry(..))
import Domain.Paint as Paint exposing (Paint(..))
import Domain.Path as Path
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Domain.Vec2 exposing (Vec2)


type alias Example =
    { id : String
    , name : String
    , description : String
    }


all : List Example
all =
    [ Example "bouncing-ball" "Bouncing ball" "Position keys with ease-in and ease-out. The last key matches the first so the loop has no jump."
    , Example "spinner" "Loading spinner" "A dashed ring rotating continuously with linear easing."
    , Example "logo-reveal" "Logo reveal" "Stroke draw-on using dash offset, then a fill fade."
    , Example "morph" "Path morph" "Two compatible closed paths interpolating point-wise."
    , Example "motion-path" "Motion path" "A shape following a curved path with automatic orientation."
    , Example "illustration" "Illustrated scene" "Layered groups with a clipping group and a spring bounce."
    ]


find : String -> Maybe Example
find id =
    List.filter (\e -> e.id == id) all |> List.head


{-| Build an example into a document with the given document id and scene id.
-}
build : String -> String -> String -> String -> Maybe Document
build exampleId docId sceneId createdAt =
    case exampleId of
        "bouncing-ball" ->
            Just (bouncingBall docId sceneId createdAt)

        "spinner" ->
            Just (spinner docId sceneId createdAt)

        "logo-reveal" ->
            Just (logoReveal docId sceneId createdAt)

        "morph" ->
            Just (morph docId sceneId createdAt)

        "motion-path" ->
            Just (motionPath docId sceneId createdAt)

        "illustration" ->
            Just (illustration docId sceneId createdAt)

        _ ->
            Nothing



-- HELPERS


key : String -> Int -> PropertyValue -> Easing -> Keyframe.Keyframe
key id frame value easing =
    { id = id, frame = frame, value = value, easing = easing }


track : String -> String -> PropertyPath -> List Keyframe.Keyframe -> Track
track id nodeId property keys =
    let
        t =
            Keyframe.newTrack id nodeId property
    in
    List.foldl Keyframe.insert t keys


addNodes : List Node -> Scene -> Scene
addNodes nodes scene =
    { scene
        | nodes = List.foldl (\n d -> Dict.insert n.id n d) scene.nodes nodes
        , rootNodeIds =
            scene.rootNodeIds
                ++ List.filterMap
                    (\n ->
                        if n.parentId == Nothing then
                            Just n.id

                        else
                            Nothing
                    )
                    nodes
    }


addTracks : List Track -> Scene -> Scene
addTracks tracks scene =
    List.foldl Scene.upsertTrack scene tracks


solid : Float -> Float -> Float -> Paint
solid r g b =
    Solid (Color.rgba r g b 1)


strokeWith : Paint -> Float -> Paint.Stroke
strokeWith paint width =
    { paint = paint, width = width, cap = Paint.CapRound, join = Paint.JoinRound, miterLimit = 4, dashArray = [], dashOffset = 0 }


at : Float -> Float -> Node -> Node
at x y node =
    let
        t =
            node.transform
    in
    { node | transform = { t | translation = { x = x, y = y } } }


pivot : Float -> Float -> Node -> Node
pivot x y node =
    let
        t =
            node.transform
    in
    { node | transform = { t | pivot = { x = x, y = y } } }


withFill : Paint -> Node -> Node
withFill p node =
    { node | fill = p }


withStroke : Paint.Stroke -> Node -> Node
withStroke s node =
    { node | stroke = s }


pt : Float -> Float -> Vec2
pt x y =
    { x = x, y = y }


withChildren : List String -> Node -> Node
withChildren ids node =
    { node | childIds = ids }



-- EXAMPLES


bouncingBall : String -> String -> String -> Document
bouncingBall docId sceneId createdAt =
    let
        ball =
            Node.new "ball" "Ball" (Ellipse { radii = pt 50 50 })
                |> at 200 90
                |> withFill (solid 0.2 0.5 0.95)

        shadow =
            Node.new "shadow" "Shadow" (Ellipse { radii = pt 46 10 })
                |> at 200 330
                |> withFill (Solid (Color.rgba 0 0 0 0.25))

        ground =
            Node.new "ground" "Ground" (Rectangle { size = pt 400 6, cornerRadius = 3 })
                |> at 0 338
                |> withFill (solid 0.3 0.3 0.33)

        scene =
            Scene.new sceneId "Bounce" 400 400 (Fps.fps 30 1) 60 Scene.Transparent
                |> addNodes [ ground, shadow, ball ]
                |> addTracks
                    [ track "t-pos"
                        "ball"
                        Position
                        [ key "k1" 0 (PointValue (pt 200 90)) (Preset EaseIn)
                        , key "k2" 30 (PointValue (pt 200 280)) (Preset EaseOut)
                        , key "k3" 60 (PointValue (pt 200 90)) Linear
                        ]
                    , track "t-scale"
                        "ball"
                        Scale
                        [ key "k4" 0 (PointValue (pt 1 1)) (Preset EaseIn)
                        , key "k5" 30 (PointValue (pt 1.15 0.85)) (Preset EaseOut)
                        , key "k6" 60 (PointValue (pt 1 1)) Linear
                        ]
                    , track "t-shadow"
                        "shadow"
                        Scale
                        [ key "k7" 0 (PointValue (pt 0.6 0.6)) (Preset EaseIn)
                        , key "k8" 30 (PointValue (pt 1 1)) (Preset EaseOut)
                        , key "k9" 60 (PointValue (pt 0.6 0.6)) Linear
                        ]
                    , track "t-shadow-op"
                        "shadow"
                        Opacity
                        [ key "k10" 0 (Scalar 0.4) (Preset EaseIn)
                        , key "k11" 30 (Scalar 1) (Preset EaseOut)
                        , key "k12" 60 (Scalar 0.4) Linear
                        ]
                    ]
    in
    Document.new docId "Bouncing ball" createdAt scene


spinner : String -> String -> String -> Document
spinner docId sceneId createdAt =
    let
        ring =
            Node.new "ring" "Ring" (Ellipse { radii = pt 40 40 })
                |> at 64 64
                |> withFill NoPaint
                |> withStroke { paint = solid 0.95 0.55 0.2, width = 10, cap = Paint.CapRound, join = Paint.JoinRound, miterLimit = 4, dashArray = [ 60, 192 ], dashOffset = 0 }

        trackRing =
            Node.new "trackring" "Track" (Ellipse { radii = pt 40 40 })
                |> at 64 64
                |> withFill NoPaint
                |> withStroke (strokeWith (Solid (Color.rgba 0.5 0.5 0.55 0.3)) 10)

        scene =
            Scene.new sceneId "Spinner" 128 128 (Fps.fps 30 1) 45 Scene.Transparent
                |> addNodes [ trackRing, ring ]
                |> addTracks
                    [ track "t-rot"
                        "ring"
                        Rotation
                        [ key "k1" 0 (Angle 0) Linear
                        , key "k2" 45 (Angle 360) Linear
                        ]
                    ]
    in
    Document.new docId "Loading spinner" createdAt scene


logoReveal : String -> String -> String -> Document
logoReveal docId sceneId createdAt =
    let
        outlinePath =
            Path.parse "M 40 200 L 120 40 L 200 200 L 160 200 L 120 120 L 80 200 Z"
                |> Result.withDefault Path.empty

        barPath =
            Path.parse "M 230 40 L 260 40 L 260 200 L 230 200 Z"
                |> Result.withDefault Path.empty

        letterA =
            Node.new "letter-a" "Letter A" (Path outlinePath)
                |> withFill (Solid (Color.rgba 0.15 0.15 0.18 1))
                |> withStroke { paint = solid 0.15 0.15 0.18, width = 6, cap = Paint.CapRound, join = Paint.JoinRound, miterLimit = 4, dashArray = [ 900 ], dashOffset = 900 }

        bar =
            Node.new "bar" "Bar" (Path barPath)
                |> withFill (solid 0.93 0.45 0.2)
                |> pivot 245 200

        group =
            withChildren [ "letter-a", "bar" ] (Node.new "logo" "Logo" Group)

        letterA2 =
            { letterA | parentId = Just "logo" }

        bar2 =
            { bar | parentId = Just "logo" }

        scene =
            Scene.new sceneId "Logo reveal" 300 240 (Fps.fps 30 1) 90 (Scene.SolidBackground (Color.rgba 0.98 0.97 0.95 1))
                |> addNodes [ group, letterA2, bar2 ]
                |> addTracks
                    [ track "t-dash"
                        "letter-a"
                        DashOffset
                        [ key "k1" 0 (Scalar 900) (Preset EaseInOut)
                        , key "k2" 45 (Scalar 0) Linear
                        ]
                    , track "t-fill"
                        "letter-a"
                        FillColor
                        [ key "k3" 35 (ColorValue (Color.rgba 0.15 0.15 0.18 0)) (Preset EaseOut)
                        , key "k4" 60 (ColorValue (Color.rgba 0.15 0.15 0.18 1)) Linear
                        ]
                    , track "t-bar"
                        "bar"
                        Scale
                        [ key "k5" 40 (PointValue (pt 1 0)) (Preset BackOut)
                        , key "k6" 70 (PointValue (pt 1 1)) Linear
                        ]
                    , track "t-group"
                        "logo"
                        Opacity
                        [ key "k7" 0 (Scalar 0) (Preset EaseOut)
                        , key "k8" 10 (Scalar 1) Linear
                        ]
                    ]
    in
    Document.new docId "Logo reveal" createdAt { scene | playbackMode = Scene.PlayOnce }


morph : String -> String -> String -> Document
morph docId sceneId createdAt =
    let
        circle =
            Node.toPathGeometry (Ellipse { radii = pt 80 80 }) |> Maybe.withDefault Path.empty

        -- a rounded square with the same 4-cubic structure as the circle
        square =
            { subpaths =
                [ { start = pt 80 -80
                  , closed = True
                  , segments =
                        [ Path.CubicTo (pt 80 -30) (pt 80 30) (pt 80 80)
                        , Path.CubicTo (pt 30 80) (pt -30 80) (pt -80 80)
                        , Path.CubicTo (pt -80 30) (pt -80 -30) (pt -80 -80)
                        , Path.CubicTo (pt -30 -80) (pt 30 -80) (pt 80 -80)
                        ]
                  }
                ]
            }

        shape =
            Node.new "blob" "Blob" (Path circle)
                |> at 160 160
                |> withFill (solid 0.55 0.3 0.75)

        scene =
            Scene.new sceneId "Morph" 320 320 (Fps.fps 30 1) 60 Scene.Transparent
                |> addNodes [ shape ]
                |> addTracks
                    [ track "t-morph"
                        "blob"
                        PathGeometryProp
                        [ key "k1" 0 (PathValue circle) (Preset EaseInOut)
                        , key "k2" 30 (PathValue square) (Preset EaseInOut)
                        , key "k3" 60 (PathValue circle) Linear
                        ]
                    , track "t-fill"
                        "blob"
                        FillColor
                        [ key "k4" 0 (ColorValue (Color.rgba 0.55 0.3 0.75 1)) (Preset EaseInOut)
                        , key "k5" 30 (ColorValue (Color.rgba 0.95 0.5 0.2 1)) (Preset EaseInOut)
                        , key "k6" 60 (ColorValue (Color.rgba 0.55 0.3 0.75 1)) Linear
                        ]
                    ]
    in
    Document.new docId "Path morph" createdAt scene


motionPath : String -> String -> String -> Document
motionPath docId sceneId createdAt =
    let
        curve =
            Path.parse "M 40 260 C 120 40 220 40 300 260 S 400 380 440 200"
                |> Result.withDefault Path.empty

        arrow =
            Node.new "arrow" "Arrow" (Polygon { sides = 3, radius = 22, innerRadius = Nothing })
                |> withFill (solid 0.2 0.65 0.5)

        arrowWithMotion =
            { arrow | motion = Just { pathId = "mp1", orient = True }, transform = { translation = pt 0 0, scale = pt 1 1, rotation = 90, skew = pt 0 0, pivot = pt 0 0 } }

        guide =
            Node.new "guide" "Path guide" (Path curve)
                |> withFill NoPaint
                |> withStroke { paint = Solid (Color.rgba 0.4 0.4 0.45 0.5), width = 2, cap = Paint.CapRound, join = Paint.JoinRound, miterLimit = 4, dashArray = [ 6, 6 ], dashOffset = 0 }

        scene =
            Scene.new sceneId "Motion path" 480 400 (Fps.fps 30 1) 90 Scene.Transparent
                |> addNodes [ guide, arrowWithMotion ]
                |> addTracks
                    [ track "t-progress"
                        "arrow"
                        MotionProgress
                        [ key "k1" 0 (Scalar 0) (Preset EaseInOut)
                        , key "k2" 90 (Scalar 1) Linear
                        ]
                    ]

        withPath =
            { scene | motionPaths = Dict.singleton "mp1" { id = "mp1", name = "Arc", geometry = curve, revision = 0 } }
    in
    Document.new docId "Motion path" createdAt withPath


illustration : String -> String -> String -> Document
illustration docId sceneId createdAt =
    let
        sky =
            Node.new "sky" "Sky" (Rectangle { size = pt 480 300, cornerRadius = 0 })
                |> withFill (GradientPaint { kind = Paint.LinearGradient { start = pt 0 0, end = pt 0 300 }, stops = [ { offset = 0, color = Color.rgba 0.98 0.78 0.55 1 }, { offset = 1, color = Color.rgba 0.95 0.55 0.45 1 } ] })

        sun =
            Node.new "sun" "Sun" (Ellipse { radii = pt 48 48 })
                |> at 360 110
                |> withFill (solid 1 0.9 0.6)

        hill1 =
            Node.new "hill1" "Far hill" (Ellipse { radii = pt 260 110 })
                |> at 140 320
                |> withFill (solid 0.45 0.55 0.4)

        hill2 =
            Node.new "hill2" "Near hill" (Ellipse { radii = pt 300 120 })
                |> at 380 350
                |> withFill (solid 0.3 0.42 0.3)

        frame =
            Node.new "frame" "Frame mask" (Rectangle { size = pt 480 300, cornerRadius = 24 })

        clip =
            withChildren [ "frame", "sky", "sun", "hill1", "hill2" ] (Node.new "clip" "Scene clip" ClippingGroup)

        inClip n =
            { n | parentId = Just "clip" }

        ball =
            Node.new "ball" "Bouncy" (Ellipse { radii = pt 18 18 })
                |> at 240 60
                |> withFill (solid 0.95 0.3 0.3)

        scene =
            Scene.new sceneId "Hills" 480 300 (Fps.fps 30 1) 90 Scene.Transparent
                |> addNodes [ clip, inClip frame, inClip sky, inClip sun, inClip hill1, inClip hill2, ball ]
                |> addTracks
                    [ track "t-sun"
                        "sun"
                        Position
                        [ key "k1" 0 (PointValue (pt 360 150)) (Preset EaseOut)
                        , key "k2" 90 (PointValue (pt 300 70)) Linear
                        ]
                    , track "t-ball"
                        "ball"
                        Position
                        [ key "k3" 0 (PointValue (pt 240 40)) (Spring { mass = 1, stiffness = 120, damping = 8, velocity = 0 })
                        , key "k4" 60 (PointValue (pt 240 200)) Linear
                        ]
                    , track "t-hill"
                        "hill2"
                        Position
                        [ key "k5" 0 (PointValue (pt 380 350)) (Preset EaseInOut)
                        , key "k6" 45 (PointValue (pt 370 340)) (Preset EaseInOut)
                        , key "k7" 90 (PointValue (pt 380 350)) Linear
                        ]
                    ]
    in
    Document.new docId "Illustrated scene" createdAt scene
