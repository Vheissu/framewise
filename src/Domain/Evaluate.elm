module Domain.Evaluate exposing
    ( ResolvedNode
    , ResolvedScene
    , evaluate
    , evaluateNodeProperty
    , evaluateScene
    , resolvedBounds
    , worldBounds
    )

{-| The single canonical evaluator. Given a document, a scene and a continuous
frame it produces a resolved render tree. Playback, preview, thumbnails and
every exporter use this function; editor selection state is never an input.
-}

import Dict exposing (Dict)
import Domain.Document exposing (Document)
import Domain.Interpolation as Interpolation
import Domain.Matrix as Matrix exposing (Matrix)
import Domain.Node as Node exposing (Effect(..), Node, NodeGeometry(..))
import Domain.Paint as Paint exposing (Paint(..), Stroke)
import Domain.Path as Path
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Domain.Transform exposing (Transform)
import Domain.Vec2 as Vec2 exposing (Vec2)
import Shared.Ids exposing (NodeId, SceneId)


type alias ResolvedNode =
    { id : NodeId
    , name : String
    , depth : Int
    , parentId : Maybe NodeId
    , childIds : List NodeId
    , geometry : NodeGeometry
    , localMatrix : Matrix
    , worldMatrix : Matrix
    , opacity : Float
    , hidden : Bool
    , inheritedHidden : Bool
    , fill : Paint
    , stroke : Stroke
    , effects : List Effect
    , isClipGroup : Bool
    , locked : Bool
    , diagnostics : List String
    }


type alias ResolvedScene =
    { sceneId : SceneId
    , frame : Float
    , width : Float
    , height : Float
    , background : Scene.Background
    , nodes : List ResolvedNode
    , byId : Dict NodeId ResolvedNode
    , diagnostics : List String
    }


evaluateScene : Document -> SceneId -> Float -> Maybe ResolvedScene
evaluateScene doc sceneId frame =
    Dict.get sceneId doc.scenes
        |> Maybe.map (\scene -> evaluate scene frame)


evaluate : Scene -> Float -> ResolvedScene
evaluate scene frame =
    let
        safeFrame =
            if isNaN frame || isInfinite frame then
                0

            else
                frame

        nodes =
            List.concatMap (resolveFrom scene safeFrame Matrix.identity 0 False) scene.rootNodeIds
    in
    { sceneId = scene.id
    , frame = safeFrame
    , width = scene.width
    , height = scene.height
    , background = scene.background
    , nodes = nodes
    , byId = Dict.fromList (List.map (\n -> ( n.id, n )) nodes)
    , diagnostics = List.concatMap .diagnostics nodes
    }


resolveFrom : Scene -> Float -> Matrix -> Int -> Bool -> NodeId -> List ResolvedNode
resolveFrom scene frame parentWorld depth parentHidden nodeId =
    case Dict.get nodeId scene.nodes of
        Nothing ->
            []

        Just node ->
            let
                resolved =
                    resolveNode scene frame parentWorld depth parentHidden node
            in
            resolved
                :: List.concatMap
                    (resolveFrom scene frame resolved.worldMatrix (depth + 1) resolved.inheritedHidden)
                    node.childIds


resolveNode : Scene -> Float -> Matrix -> Int -> Bool -> Node -> ResolvedNode
resolveNode scene frame parentWorld depth parentHidden node =
    let
        tracks =
            Scene.tracksFor node.id scene |> List.filter .enabled

        valueOf property =
            tracks
                |> List.filter (\t -> t.target.property == property)
                |> List.head
                |> Maybe.andThen (Interpolation.evaluateTrack frame)

        transform =
            evaluateTransform node.transform valueOf

        motion =
            node.motion
                |> Maybe.andThen
                    (\att ->
                        Dict.get att.pathId scene.motionPaths
                            |> Maybe.map (\mp -> motionOffset mp att.orient (valueOf MotionProgress))
                    )

        ( motionTransform, motionDiag ) =
            case motion of
                Just ( offset, rot, diag ) ->
                    ( Just { offset = offset, angle = rot }, diag )

                Nothing ->
                    ( Nothing, [] )

        localMatrix =
            Matrix.fromComponentsWithMotion transform motionTransform

        opacity =
            case valueOf Opacity of
                Just (Scalar o) ->
                    clamp 0 1 o

                _ ->
                    clamp 0 1 node.opacity

        hidden =
            not (Node.inSpan scene.durationFrames frame node)
                || (case valueOf Visible of
                        Just (BoolValue v) ->
                            not v

                        _ ->
                            node.hidden
                   )

        fill =
            case valueOf FillColor of
                Just (ColorValue c) ->
                    Paint.setPaintColor c node.fill

                _ ->
                    node.fill

        strokePaint =
            case valueOf StrokeColor of
                Just (ColorValue c) ->
                    Paint.setPaintColor c node.stroke.paint

                _ ->
                    node.stroke.paint

        strokeWidth =
            case valueOf StrokeWidth of
                Just (Scalar w) ->
                    max 0 w

                _ ->
                    node.stroke.width

        dashOffset =
            case valueOf DashOffset of
                Just (Scalar d) ->
                    d

                _ ->
                    node.stroke.dashOffset

        stroke =
            let
                s =
                    node.stroke
            in
            { s | paint = strokePaint, width = strokeWidth, dashOffset = dashOffset }

        geometry =
            evaluateGeometry node.geometry valueOf

        effects =
            List.map
                (\e ->
                    case ( e, valueOf BlurRadius ) of
                        ( Blur _, Just (Scalar r) ) ->
                            Blur (max 0 r)

                        _ ->
                            e
                )
                node.effects

        finiteDiag =
            if Matrix.isFinite localMatrix then
                []

            else
                [ "Node " ++ node.id ++ " has a non-finite transform at frame " ++ String.fromFloat frame ]

        safeLocal =
            if Matrix.isFinite localMatrix then
                localMatrix

            else
                Matrix.identity
    in
    { id = node.id
    , name = node.name
    , depth = depth
    , parentId = node.parentId
    , childIds = node.childIds
    , geometry = geometry
    , localMatrix = safeLocal
    , worldMatrix = Matrix.multiply parentWorld safeLocal
    , opacity = opacity
    , hidden = hidden
    , inheritedHidden = parentHidden || hidden
    , fill = fill
    , stroke = stroke
    , effects = effects
    , isClipGroup = node.geometry == ClippingGroup
    , locked = node.locked
    , diagnostics = finiteDiag ++ motionDiag
    }


evaluateTransform : Transform -> (PropertyPath -> Maybe PropertyValue) -> Transform
evaluateTransform base valueOf =
    { translation =
        case valueOf Position of
            Just (PointValue p) ->
                p

            _ ->
                base.translation
    , scale =
        case valueOf Scale of
            Just (PointValue p) ->
                p

            _ ->
                base.scale
    , rotation =
        case valueOf Rotation of
            Just (Angle a) ->
                a

            _ ->
                base.rotation
    , skew =
        case valueOf Skew of
            Just (PointValue p) ->
                p

            _ ->
                base.skew
    , pivot =
        case valueOf Pivot of
            Just (PointValue p) ->
                p

            _ ->
                base.pivot
    }


evaluateGeometry : NodeGeometry -> (PropertyPath -> Maybe PropertyValue) -> NodeGeometry
evaluateGeometry geometry valueOf =
    case geometry of
        Rectangle r ->
            Rectangle
                { size =
                    case valueOf RectSize of
                        Just (SizeValue s) ->
                            { x = max 0 s.x, y = max 0 s.y }

                        _ ->
                            r.size
                , cornerRadius =
                    case valueOf RectCornerRadius of
                        Just (Scalar c) ->
                            max 0 c

                        _ ->
                            r.cornerRadius
                }

        Ellipse e ->
            Ellipse
                { radii =
                    case valueOf EllipseRadii of
                        Just (SizeValue s) ->
                            { x = max 0 s.x, y = max 0 s.y }

                        _ ->
                            e.radii
                }

        Path p ->
            case valueOf PathGeometryProp of
                Just (PathValue g) ->
                    Path g

                _ ->
                    Path p

        Text t ->
            Text
                { t
                    | fontSize =
                        case valueOf FontSize of
                            Just (Scalar s) ->
                                max 0.1 s

                            _ ->
                                t.fontSize
                    , content =
                        case valueOf TextContent of
                            Just (StringValue s) ->
                                s

                            _ ->
                                t.content
                }

        other ->
            other


{-| Position offset and rotation contributed by a motion path at the given
progress. Progress maps to arc length, not raw curve parameter.
-}
motionOffset : Scene.MotionPath -> Bool -> Maybe PropertyValue -> ( Vec2, Float, List String )
motionOffset mp orient progressValue =
    let
        progress =
            case progressValue of
                Just (Scalar p) ->
                    clamp 0 1 p

                _ ->
                    0

        table =
            Path.arcTable 16 mp.geometry

        sample =
            Path.pointAtLength table (progress * Path.totalLength table)

        rotation =
            if orient then
                atan2 sample.tangent.y sample.tangent.x * 180 / pi

            else
                0

        diag =
            if Path.totalLength table <= 0 then
                [ "Motion path " ++ mp.id ++ " has zero length" ]

            else
                []
    in
    ( sample.point, rotation, diag )


{-| Evaluate a single property of a node at a frame, returning the base value
when it has no track. Used by the inspector to show values at the playhead.
-}
evaluateNodeProperty : Scene -> Float -> Node -> PropertyPath -> Maybe PropertyValue
evaluateNodeProperty scene frame node property =
    case Scene.trackFor node.id property scene |> Maybe.andThen (Interpolation.evaluateTrack frame) of
        Just v ->
            Just v

        Nothing ->
            baseValue scene node property


baseValue : Scene -> Node -> PropertyPath -> Maybe PropertyValue
baseValue _ node property =
    case property of
        Position ->
            Just (PointValue node.transform.translation)

        Scale ->
            Just (PointValue node.transform.scale)

        Rotation ->
            Just (Angle node.transform.rotation)

        Skew ->
            Just (PointValue node.transform.skew)

        Pivot ->
            Just (PointValue node.transform.pivot)

        Opacity ->
            Just (Scalar node.opacity)

        Visible ->
            Just (BoolValue (not node.hidden))

        FillColor ->
            Paint.paintColor node.fill |> Maybe.map ColorValue

        StrokeColor ->
            Paint.paintColor node.stroke.paint |> Maybe.map ColorValue

        StrokeWidth ->
            Just (Scalar node.stroke.width)

        DashOffset ->
            Just (Scalar node.stroke.dashOffset)

        RectSize ->
            case node.geometry of
                Rectangle r ->
                    Just (SizeValue r.size)

                _ ->
                    Nothing

        RectCornerRadius ->
            case node.geometry of
                Rectangle r ->
                    Just (Scalar r.cornerRadius)

                _ ->
                    Nothing

        EllipseRadii ->
            case node.geometry of
                Ellipse e ->
                    Just (SizeValue e.radii)

                _ ->
                    Nothing

        PathGeometryProp ->
            case node.geometry of
                Path p ->
                    Just (PathValue p)

                _ ->
                    Nothing

        FontSize ->
            case node.geometry of
                Text t ->
                    Just (Scalar t.fontSize)

                _ ->
                    Nothing

        TextContent ->
            case node.geometry of
                Text t ->
                    Just (StringValue t.content)

                _ ->
                    Nothing

        MotionProgress ->
            Just (Scalar 0)

        BlurRadius ->
            node.effects
                |> List.filterMap
                    (\e ->
                        case e of
                            Blur r ->
                                Just (Scalar r)

                            _ ->
                                Nothing
                    )
                |> List.head


{-| Axis-aligned world bounds of a resolved node, including descendants for
containers. Returns Nothing for empty groups.
-}
worldBounds : ResolvedScene -> ResolvedNode -> Maybe { minX : Float, minY : Float, maxX : Float, maxY : Float }
worldBounds scene node =
    let
        own =
            Node.geometryBounds node.geometry
                |> Maybe.map (transformBounds node.worldMatrix)

        childBounds =
            node.childIds
                |> List.filterMap (\cid -> Dict.get cid scene.byId)
                |> List.filterMap (worldBounds scene)
    in
    unionAll (List.filterMap identity [ own ] ++ childBounds)


resolvedBounds : ResolvedNode -> Maybe { minX : Float, minY : Float, maxX : Float, maxY : Float }
resolvedBounds node =
    Node.geometryBounds node.geometry |> Maybe.map (transformBounds node.worldMatrix)


transformBounds : Matrix -> { minX : Float, minY : Float, maxX : Float, maxY : Float } -> { minX : Float, minY : Float, maxX : Float, maxY : Float }
transformBounds m b =
    let
        corners =
            List.map (Matrix.apply m)
                [ { x = b.minX, y = b.minY }
                , { x = b.maxX, y = b.minY }
                , { x = b.maxX, y = b.maxY }
                , { x = b.minX, y = b.maxY }
                ]

        xs =
            List.map .x corners

        ys =
            List.map .y corners
    in
    { minX = List.minimum xs |> Maybe.withDefault 0
    , minY = List.minimum ys |> Maybe.withDefault 0
    , maxX = List.maximum xs |> Maybe.withDefault 0
    , maxY = List.maximum ys |> Maybe.withDefault 0
    }


unionAll : List { minX : Float, minY : Float, maxX : Float, maxY : Float } -> Maybe { minX : Float, minY : Float, maxX : Float, maxY : Float }
unionAll list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            Just
                (List.foldl
                    (\b acc ->
                        { minX = min acc.minX b.minX
                        , minY = min acc.minY b.minY
                        , maxX = max acc.maxX b.maxX
                        , maxY = max acc.maxY b.maxY
                        }
                    )
                    first
                    rest
                )
