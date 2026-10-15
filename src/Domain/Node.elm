module Domain.Node exposing
    ( Effect(..)
    , EllipseGeometry
    , ImageGeometry
    , LineGeometry
    , MotionAttachment
    , Node
    , NodeGeometry(..)
    , PolygonGeometry
    , RectGeometry
    , TextAlign(..)
    , TextGeometry
    , alignFromCode
    , alignToCode
    , animatableProperties
    , geometryBounds
    , isContainer
    , kindCode
    , kindLabel
    , new
    , polygonPoints
    , supportsProperty
    , toPathGeometry
    )

{-| Scene nodes. Geometry is stored in node-local coordinates; `transform`
maps local to parent space.
-}

import Domain.Color as Color
import Domain.Paint as Paint exposing (Paint(..), Stroke)
import Domain.Path as Path exposing (PathGeometry)
import Domain.Property exposing (PropertyPath(..))
import Domain.Transform as Transform exposing (Transform)
import Domain.Vec2 as Vec2 exposing (Vec2)
import Shared.Ids exposing (AssetId, MotionPathId, NodeId)


type alias RectGeometry =
    { size : Vec2, cornerRadius : Float }


type alias EllipseGeometry =
    { radii : Vec2 }


type alias LineGeometry =
    { start : Vec2, end : Vec2 }


type alias PolygonGeometry =
    { sides : Int, radius : Float, innerRadius : Maybe Float }


type TextAlign
    = AlignStart
    | AlignMiddle
    | AlignEnd


type alias TextGeometry =
    { content : String
    , fontFamily : String
    , fontSize : Float
    , fontWeight : Int
    , italic : Bool
    , letterSpacing : Float
    , align : TextAlign
    }


type alias ImageGeometry =
    { assetId : AssetId, size : Vec2, naturalSize : Vec2 }


type NodeGeometry
    = Rectangle RectGeometry
    | Ellipse EllipseGeometry
    | Line LineGeometry
    | Polygon PolygonGeometry
    | Path PathGeometry
    | Text TextGeometry
    | RasterImage ImageGeometry
    | Group
    | ClippingGroup


type Effect
    = Blur Float
    | DropShadow { offset : Vec2, blur : Float, color : Color.Rgba }


type alias Node =
    { id : NodeId
    , name : String
    , parentId : Maybe NodeId
    , childIds : List NodeId
    , hidden : Bool
    , locked : Bool
    , opacity : Float
    , transform : Transform
    , geometry : NodeGeometry
    , fill : Paint
    , stroke : Stroke
    , effects : List Effect
    , motion : Maybe MotionAttachment
    , importedElementId : Maybe String
    }


type alias MotionAttachment =
    { pathId : MotionPathId, orient : Bool }


new : NodeId -> String -> NodeGeometry -> Node
new id name geometry =
    { id = id
    , name = name
    , parentId = Nothing
    , childIds = []
    , hidden = False
    , locked = False
    , opacity = 1
    , transform = Transform.identity
    , geometry = geometry
    , fill =
        case geometry of
            Line _ ->
                NoPaint

            Group ->
                NoPaint

            ClippingGroup ->
                NoPaint

            RasterImage _ ->
                NoPaint

            _ ->
                Solid (Color.rgba 0.36 0.56 0.92 1)
    , stroke =
        case geometry of
            Line _ ->
                { paint = Solid (Color.rgba 0.12 0.12 0.14 1), width = 2, cap = Paint.CapButt, join = Paint.JoinMiter, miterLimit = 4, dashArray = [], dashOffset = 0 }

            _ ->
                Paint.noStroke
    , effects = []
    , motion = Nothing
    , importedElementId = Nothing
    }


isContainer : Node -> Bool
isContainer n =
    case n.geometry of
        Group ->
            True

        ClippingGroup ->
            True

        _ ->
            False


kindCode : NodeGeometry -> String
kindCode g =
    case g of
        Rectangle _ ->
            "rect"

        Ellipse _ ->
            "ellipse"

        Line _ ->
            "line"

        Polygon _ ->
            "polygon"

        Path _ ->
            "path"

        Text _ ->
            "text"

        RasterImage _ ->
            "image"

        Group ->
            "group"

        ClippingGroup ->
            "clipGroup"


kindLabel : NodeGeometry -> String
kindLabel g =
    case g of
        Rectangle _ ->
            "Rectangle"

        Ellipse _ ->
            "Ellipse"

        Line _ ->
            "Line"

        Polygon _ ->
            "Polygon"

        Path _ ->
            "Path"

        Text _ ->
            "Text"

        RasterImage _ ->
            "Image"

        Group ->
            "Group"

        ClippingGroup ->
            "Clip Group"


alignToCode : TextAlign -> String
alignToCode a =
    case a of
        AlignStart ->
            "start"

        AlignMiddle ->
            "middle"

        AlignEnd ->
            "end"


alignFromCode : String -> Maybe TextAlign
alignFromCode s =
    case s of
        "start" ->
            Just AlignStart

        "middle" ->
            Just AlignMiddle

        "end" ->
            Just AlignEnd

        _ ->
            Nothing


{-| Properties that can carry animation tracks for this node.
-}
animatableProperties : Node -> List PropertyPath
animatableProperties n =
    let
        common =
            [ Position, Scale, Rotation, Skew, Pivot, Opacity, Visible ]

        paint =
            case n.geometry of
                Group ->
                    []

                ClippingGroup ->
                    []

                RasterImage _ ->
                    []

                Line _ ->
                    [ StrokeColor, StrokeWidth, DashOffset ]

                _ ->
                    [ FillColor, StrokeColor, StrokeWidth, DashOffset ]

        shape =
            case n.geometry of
                Rectangle _ ->
                    [ RectSize, RectCornerRadius ]

                Ellipse _ ->
                    [ EllipseRadii ]

                Path _ ->
                    [ PathGeometryProp ]

                Text _ ->
                    [ FontSize, TextContent ]

                _ ->
                    []

        motion =
            case n.motion of
                Just _ ->
                    [ MotionProgress ]

                Nothing ->
                    []

        effects =
            if List.any isBlur n.effects then
                [ BlurRadius ]

            else
                []
    in
    common ++ paint ++ shape ++ motion ++ effects


isBlur : Effect -> Bool
isBlur e =
    case e of
        Blur _ ->
            True

        _ ->
            False


supportsProperty : Node -> PropertyPath -> Bool
supportsProperty n p =
    List.member p (animatableProperties n)


{-| Regular polygon / star points in local coordinates centred on the origin.
-}
polygonPoints : PolygonGeometry -> List Vec2
polygonPoints g =
    let
        sides =
            max 3 g.sides

        pointAt i r =
            let
                angle =
                    -pi / 2 + toFloat i * 2 * pi / toFloat (sides * stepCount)

                stepCount =
                    1
            in
            { x = r * cos angle, y = r * sin angle }
    in
    case g.innerRadius of
        Nothing ->
            List.map (\i -> pointAt i g.radius) (List.range 0 (sides - 1))

        Just inner ->
            List.concatMap
                (\i ->
                    let
                        outerAngle =
                            -pi / 2 + toFloat i * 2 * pi / toFloat sides

                        innerAngle =
                            outerAngle + pi / toFloat sides
                    in
                    [ { x = g.radius * cos outerAngle, y = g.radius * sin outerAngle }
                    , { x = inner * cos innerAngle, y = inner * sin innerAngle }
                    ]
                )
                (List.range 0 (sides - 1))


{-| Local-space geometry bounds (before transform), ignoring stroke.
-}
geometryBounds : NodeGeometry -> Maybe { minX : Float, minY : Float, maxX : Float, maxY : Float }
geometryBounds g =
    case g of
        Rectangle r ->
            Just { minX = 0, minY = 0, maxX = r.size.x, maxY = r.size.y }

        Ellipse e ->
            Just { minX = -e.radii.x, minY = -e.radii.y, maxX = e.radii.x, maxY = e.radii.y }

        Line l ->
            Just
                { minX = min l.start.x l.end.x
                , minY = min l.start.y l.end.y
                , maxX = max l.start.x l.end.x
                , maxY = max l.start.y l.end.y
                }

        Polygon p ->
            Just { minX = -p.radius, minY = -p.radius, maxX = p.radius, maxY = p.radius }

        Path path ->
            Path.bounds path

        Text t ->
            -- Approximate advance width; the DOM measurement bridge refines it.
            let
                w =
                    toFloat (String.length t.content) * t.fontSize * 0.55 + toFloat (String.length t.content) * t.letterSpacing

                startX =
                    case t.align of
                        AlignStart ->
                            0

                        AlignMiddle ->
                            -w / 2

                        AlignEnd ->
                            -w
            in
            Just { minX = startX, minY = -t.fontSize * 0.8, maxX = startX + w, maxY = t.fontSize * 0.25 }

        RasterImage i ->
            Just { minX = 0, minY = 0, maxX = i.size.x, maxY = i.size.y }

        Group ->
            Nothing

        ClippingGroup ->
            Nothing


{-| Convert primitive geometry to an editable path.
-}
toPathGeometry : NodeGeometry -> Maybe PathGeometry
toPathGeometry g =
    case g of
        Rectangle r ->
            if r.cornerRadius <= 0 then
                Just (Path.fromPolyline [ Vec2.zero, { x = r.size.x, y = 0 }, r.size, { x = 0, y = r.size.y } ] True)

            else
                let
                    rr =
                        min r.cornerRadius (min r.size.x r.size.y / 2)

                    k =
                        0.5522847498 * rr

                    w =
                        r.size.x

                    h =
                        r.size.y
                in
                Just
                    { subpaths =
                        [ { start = { x = rr, y = 0 }
                          , closed = True
                          , segments =
                                [ Path.LineTo { x = w - rr, y = 0 }
                                , Path.CubicTo { x = w - rr + k, y = 0 } { x = w, y = rr - k } { x = w, y = rr }
                                , Path.LineTo { x = w, y = h - rr }
                                , Path.CubicTo { x = w, y = h - rr + k } { x = w - rr + k, y = h } { x = w - rr, y = h }
                                , Path.LineTo { x = rr, y = h }
                                , Path.CubicTo { x = rr - k, y = h } { x = 0, y = h - rr + k } { x = 0, y = h - rr }
                                , Path.LineTo { x = 0, y = rr }
                                , Path.CubicTo { x = 0, y = rr - k } { x = rr - k, y = 0 } { x = rr, y = 0 }
                                ]
                          }
                        ]
                    }

        Ellipse e ->
            let
                rx =
                    e.radii.x

                ry =
                    e.radii.y

                kx =
                    0.5522847498 * rx

                ky =
                    0.5522847498 * ry
            in
            Just
                { subpaths =
                    [ { start = { x = rx, y = 0 }
                      , closed = True
                      , segments =
                            [ Path.CubicTo { x = rx, y = ky } { x = kx, y = ry } { x = 0, y = ry }
                            , Path.CubicTo { x = -kx, y = ry } { x = -rx, y = ky } { x = -rx, y = 0 }
                            , Path.CubicTo { x = -rx, y = -ky } { x = -kx, y = -ry } { x = 0, y = -ry }
                            , Path.CubicTo { x = kx, y = -ry } { x = rx, y = -ky } { x = rx, y = 0 }
                            ]
                      }
                    ]
                }

        Line l ->
            Just (Path.fromPolyline [ l.start, l.end ] False)

        Polygon p ->
            Just (Path.fromPolyline (polygonPoints p) True)

        Path p ->
            Just p

        _ ->
            Nothing
