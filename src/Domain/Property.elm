module Domain.Property exposing
    ( PropertyPath(..)
    , PropertyValue(..)
    , allPaths
    , isDiscrete
    , pathFromCode
    , pathLabel
    , pathToCode
    , valueKind
    , valueTypeMatches
    )

{-| Typed property addresses and typed values. On-disk codes are stable
strings such as `transform.position`; Elm never passes free-form strings
around internally.
-}

import Domain.Color exposing (Rgba)
import Domain.Path exposing (PathGeometry)
import Domain.Vec2 exposing (Vec2)


type PropertyPath
    = Position
    | Scale
    | Rotation
    | Skew
    | Pivot
    | Opacity
    | Visible
    | FillColor
    | StrokeColor
    | StrokeWidth
    | DashOffset
    | RectSize
    | RectCornerRadius
    | EllipseRadii
    | PathGeometryProp
    | FontSize
    | TextContent
    | MotionProgress
    | BlurRadius


type PropertyValue
    = Scalar Float
    | Angle Float
    | PointValue Vec2
    | SizeValue Vec2
    | ColorValue Rgba
    | BoolValue Bool
    | StringValue String
    | PathValue PathGeometry
    | NumberList (List Float)


allPaths : List PropertyPath
allPaths =
    [ Position
    , Scale
    , Rotation
    , Skew
    , Pivot
    , Opacity
    , Visible
    , FillColor
    , StrokeColor
    , StrokeWidth
    , DashOffset
    , RectSize
    , RectCornerRadius
    , EllipseRadii
    , PathGeometryProp
    , FontSize
    , TextContent
    , MotionProgress
    , BlurRadius
    ]


pathToCode : PropertyPath -> String
pathToCode p =
    case p of
        Position ->
            "transform.position"

        Scale ->
            "transform.scale"

        Rotation ->
            "transform.rotation"

        Skew ->
            "transform.skew"

        Pivot ->
            "transform.pivot"

        Opacity ->
            "compositing.opacity"

        Visible ->
            "compositing.visible"

        FillColor ->
            "style.fill.color"

        StrokeColor ->
            "style.stroke.color"

        StrokeWidth ->
            "style.stroke.width"

        DashOffset ->
            "style.stroke.dashOffset"

        RectSize ->
            "shape.rect.size"

        RectCornerRadius ->
            "shape.rect.cornerRadius"

        EllipseRadii ->
            "shape.ellipse.radii"

        PathGeometryProp ->
            "shape.path.geometry"

        FontSize ->
            "text.fontSize"

        TextContent ->
            "text.content"

        MotionProgress ->
            "motion.progress"

        BlurRadius ->
            "effects.blur.radius"


pathFromCode : String -> Maybe PropertyPath
pathFromCode code =
    List.filter (\p -> pathToCode p == code) allPaths |> List.head


pathLabel : PropertyPath -> String
pathLabel p =
    case p of
        Position ->
            "Position"

        Scale ->
            "Scale"

        Rotation ->
            "Rotation"

        Skew ->
            "Skew"

        Pivot ->
            "Pivot"

        Opacity ->
            "Opacity"

        Visible ->
            "Visible"

        FillColor ->
            "Fill"

        StrokeColor ->
            "Stroke"

        StrokeWidth ->
            "Stroke Width"

        DashOffset ->
            "Dash Offset"

        RectSize ->
            "Size"

        RectCornerRadius ->
            "Corner Radius"

        EllipseRadii ->
            "Radii"

        PathGeometryProp ->
            "Path"

        FontSize ->
            "Font Size"

        TextContent ->
            "Text"

        MotionProgress ->
            "Path Progress"

        BlurRadius ->
            "Blur"


{-| Discrete properties step at the key boundary instead of interpolating.
-}
isDiscrete : PropertyPath -> Bool
isDiscrete p =
    case p of
        Visible ->
            True

        TextContent ->
            True

        _ ->
            False


{-| The kind tag a value must have for a property.
-}
valueKind : PropertyPath -> String
valueKind p =
    case p of
        Position ->
            "point"

        Scale ->
            "point"

        Rotation ->
            "angle"

        Skew ->
            "point"

        Pivot ->
            "point"

        Opacity ->
            "scalar"

        Visible ->
            "bool"

        FillColor ->
            "color"

        StrokeColor ->
            "color"

        StrokeWidth ->
            "scalar"

        DashOffset ->
            "scalar"

        RectSize ->
            "size"

        RectCornerRadius ->
            "scalar"

        EllipseRadii ->
            "size"

        PathGeometryProp ->
            "path"

        FontSize ->
            "scalar"

        TextContent ->
            "string"

        MotionProgress ->
            "scalar"

        BlurRadius ->
            "scalar"


valueTypeMatches : PropertyPath -> PropertyValue -> Bool
valueTypeMatches p v =
    let
        kind =
            case v of
                Scalar _ ->
                    "scalar"

                Angle _ ->
                    "angle"

                PointValue _ ->
                    "point"

                SizeValue _ ->
                    "size"

                ColorValue _ ->
                    "color"

                BoolValue _ ->
                    "bool"

                StringValue _ ->
                    "string"

                PathValue _ ->
                    "path"

                NumberList _ ->
                    "numbers"
    in
    kind == valueKind p
