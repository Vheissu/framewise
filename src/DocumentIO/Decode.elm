module DocumentIO.Decode exposing
    ( document
    , easing
    , node
    , paintDecoder
    , pathGeometryDecoder
    , propertyPath
    , propertyValue
    , scene
    , strokeDecoder
    , track
    )

{-| Strict decoders. Every enum code is validated; numbers must be finite.
-}

import Dict
import Domain.Color as Color exposing (Rgba)
import Domain.Document exposing (AssetMeta, Document)
import Domain.Easing as Easing exposing (Easing(..))
import Domain.Fps as Fps exposing (Fps)
import Domain.Keyframe exposing (Keyframe, Track)
import Domain.Node as Node exposing (Effect(..), Node, NodeGeometry(..))
import Domain.Paint as Paint exposing (Paint(..), Stroke)
import Domain.Path exposing (PathGeometry, Segment(..))
import Domain.Property as Property exposing (PropertyPath, PropertyValue(..))
import Domain.Scene as Scene exposing (Background(..), MotionPath, Scene)
import Domain.Transform exposing (Transform)
import Domain.Vec2 exposing (Vec2)
import Json.Decode as D exposing (Decoder)


document : Decoder Document
document =
    D.field "schemaVersion" D.int
        |> D.andThen
            (\v ->
                if v /= Domain.Document.currentSchemaVersion then
                    D.fail ("Unsupported schema version " ++ String.fromInt v)

                else
                    D.map6
                        (\id meta sceneOrder scenes assets _ ->
                            { id = id
                            , schemaVersion = v
                            , metadata = meta
                            , sceneOrder = sceneOrder
                            , scenes = Dict.fromList (List.map (\s -> ( s.id, s )) scenes)
                            , assets = Dict.fromList (List.map (\a -> ( a.id, a )) assets)
                            }
                        )
                        (D.field "id" nonEmptyString)
                        (D.field "metadata" metadata)
                        (D.field "sceneOrder" (D.list D.string))
                        (D.field "scenes" (D.list scene))
                        (optionalField "assets" (D.list asset) [])
                        (D.succeed ())
            )


metadata : Decoder Domain.Document.Metadata
metadata =
    D.map4 Domain.Document.Metadata
        (D.field "name" D.string)
        (optionalField "description" D.string "")
        (optionalField "createdAt" D.string "")
        (optionalField "modifiedAt" D.string "")


asset : Decoder AssetMeta
asset =
    D.map7 AssetMeta
        (D.field "id" nonEmptyString)
        (D.field "name" D.string)
        (D.field "mimeType" D.string)
        (D.field "byteLength" D.int)
        (D.field "sha256" D.string)
        (optionalField "width" D.int 0)
        (optionalField "height" D.int 0)


scene : Decoder Scene
scene =
    let
        base =
            D.map8
                (\id name description width height bg rate duration ->
                    { id = id, name = name, description = description, width = width, height = height, background = bg, fps = rate, durationFrames = duration }
                )
                (D.field "id" nonEmptyString)
                (D.field "name" D.string)
                (optionalField "description" D.string "")
                (D.field "width" positiveFloat)
                (D.field "height" positiveFloat)
                (D.field "background" background)
                (D.field "fps" fps)
                (D.field "durationFrames" D.int)
    in
    base
        |> D.andThen
            (\b ->
                D.map8
                    (\mode markers range rootNodeIds nodes tracks motionPaths guides ->
                        { id = b.id
                        , name = b.name
                        , description = b.description
                        , width = b.width
                        , height = b.height
                        , background = b.background
                        , fps = b.fps
                        , durationFrames = b.durationFrames
                        , playbackMode = mode
                        , markers = markers
                        , workRange = range
                        , rootNodeIds = rootNodeIds
                        , nodes = Dict.fromList (List.map (\n -> ( n.id, n )) nodes)
                        , tracks = Dict.fromList (List.map (\t -> ( t.id, t )) tracks)
                        , motionPaths = Dict.fromList (List.map (\m -> ( m.id, m )) motionPaths)
                        , guides = guides
                        }
                    )
                    (optionalField "playbackMode" playbackMode Scene.Repeat)
                    (optionalField "markers" (D.list marker) [])
                    (optionalField "workRange" (D.nullable workRange) Nothing)
                    (D.field "rootNodeIds" (D.list D.string))
                    (D.field "nodes" (D.list node))
                    (optionalField "tracks" (D.list track) [])
                    (optionalField "motionPaths" (D.list motionPath) [])
                    (optionalField "guides" (D.list guide) [])
            )


playbackMode : Decoder Scene.PlaybackMode
playbackMode =
    enum "playback mode" Scene.playbackModeFromCode


marker : Decoder Scene.Marker
marker =
    D.map2 Scene.Marker (D.field "frame" D.int) (D.field "label" D.string)


workRange : Decoder Scene.WorkRange
workRange =
    D.map2 Scene.WorkRange (D.field "start" D.int) (D.field "end" D.int)


guide : Decoder Scene.Guide
guide =
    D.map2 Scene.Guide (D.field "horizontal" D.bool) (D.field "position" finiteFloat)


background : Decoder Background
background =
    D.field "type" D.string
        |> D.andThen
            (\t ->
                case t of
                    "transparent" ->
                        D.succeed Transparent

                    "solid" ->
                        D.map SolidBackground (D.field "color" color)

                    _ ->
                        D.fail ("Unknown background type " ++ t)
            )


fps : Decoder Fps
fps =
    D.map2 Fps.fps (D.field "numerator" D.int) (D.field "denominator" D.int)
        |> D.andThen
            (\f ->
                if Fps.isValid f then
                    D.succeed f

                else
                    D.fail "Invalid frame rate"
            )


motionPath : Decoder MotionPath
motionPath =
    D.map4 MotionPath
        (D.field "id" nonEmptyString)
        (D.field "name" D.string)
        (D.field "geometry" path)
        (optionalField "revision" D.int 0)


node : Decoder Node
node =
    D.field "kind" D.string
        |> D.andThen
            (\kind ->
                D.field "geometry" (geometry kind)
                    |> D.andThen
                        (\geo ->
                            let
                                part1 =
                                    D.map7
                                        (\id name parentId childIds hidden locked opacity ->
                                            { id = id, name = name, parentId = parentId, childIds = childIds, hidden = hidden, locked = locked, opacity = opacity }
                                        )
                                        (D.field "id" nonEmptyString)
                                        (D.field "name" D.string)
                                        (optionalField "parentId" (D.nullable D.string) Nothing)
                                        (optionalField "childIds" (D.list D.string) [])
                                        (optionalField "hidden" D.bool False)
                                        (optionalField "locked" D.bool False)
                                        (optionalField "opacity" unitFloat 1)
                            in
                            part1
                                |> D.andThen
                                    (\p ->
                                        D.map6
                                            (\tr fillPaint strokeStyle effects motionAtt importedElementId ->
                                                { id = p.id
                                                , name = p.name
                                                , parentId = p.parentId
                                                , childIds = p.childIds
                                                , hidden = p.hidden
                                                , locked = p.locked
                                                , opacity = p.opacity
                                                , transform = tr
                                                , geometry = geo
                                                , fill = fillPaint
                                                , stroke = strokeStyle
                                                , effects = effects
                                                , motion = motionAtt
                                                , importedElementId = importedElementId
                                                }
                                            )
                                            (optionalField "transform" transform Domain.Transform.identity)
                                            (optionalField "fill" paint NoPaint)
                                            (optionalField "stroke" stroke Paint.noStroke)
                                            (optionalField "effects" (D.list effect) [])
                                            (optionalField "motion" (D.nullable motionAttachment) Nothing)
                                            (optionalField "metadata" (optionalField "importedElementId" (D.nullable D.string) Nothing) Nothing)
                                    )
                        )
            )


motionAttachment : Decoder Node.MotionAttachment
motionAttachment =
    D.map2 Node.MotionAttachment (D.field "pathId" nonEmptyString) (optionalField "orient" D.bool True)


transform : Decoder Transform
transform =
    D.map5 Transform
        (D.field "translation" vec2)
        (D.field "scale" vec2)
        (D.field "rotation" finiteFloat)
        (optionalField "skew" vec2 { x = 0, y = 0 })
        (optionalField "pivot" vec2 { x = 0, y = 0 })


geometry : String -> Decoder NodeGeometry
geometry kind =
    case kind of
        "rect" ->
            D.map2 (\size cr -> Rectangle { size = size, cornerRadius = cr })
                (D.field "size" vec2)
                (optionalField "cornerRadius" nonNegativeFloat 0)

        "ellipse" ->
            D.map (\r -> Ellipse { radii = r }) (D.field "radii" vec2)

        "line" ->
            D.map2 (\s e -> Line { start = s, end = e }) (D.field "start" vec2) (D.field "end" vec2)

        "polygon" ->
            D.map3 (\sides r inner -> Polygon { sides = sides, radius = r, innerRadius = inner })
                (D.field "sides" D.int)
                (D.field "radius" nonNegativeFloat)
                (optionalField "innerRadius" (D.nullable nonNegativeFloat) Nothing)

        "path" ->
            D.map Path path

        "path-d" ->
            -- raw SVG path data from the importer, normalised by the Elm parser
            D.field "d" D.string
                |> D.andThen
                    (\d ->
                        case Domain.Path.parse d of
                            Ok g ->
                                D.succeed (Path g)

                            Err e ->
                                D.fail ("Invalid path data: " ++ e)
                    )

        "text" ->
            D.map7
                (\content family size weight italic spacing align ->
                    Text { content = content, fontFamily = family, fontSize = size, fontWeight = weight, italic = italic, letterSpacing = spacing, align = align }
                )
                (D.field "content" D.string)
                (optionalField "fontFamily" D.string "sans-serif")
                (D.field "fontSize" positiveFloat)
                (optionalField "fontWeight" D.int 400)
                (optionalField "italic" D.bool False)
                (optionalField "letterSpacing" finiteFloat 0)
                (optionalField "align" (enum "text align" Node.alignFromCode) Node.AlignStart)

        "image" ->
            D.map3 (\a s n -> RasterImage { assetId = a, size = s, naturalSize = n })
                (D.field "assetId" nonEmptyString)
                (D.field "size" vec2)
                (optionalField "naturalSize" vec2 { x = 0, y = 0 })

        "group" ->
            D.succeed Group

        "clipGroup" ->
            D.succeed ClippingGroup

        _ ->
            D.fail ("Unknown node kind " ++ kind)


pathGeometryDecoder : Decoder PathGeometry
pathGeometryDecoder =
    path


path : Decoder PathGeometry
path =
    D.map (\subpaths -> { subpaths = subpaths })
        (D.field "subpaths"
            (D.list
                (D.map3 (\start closed segments -> { start = start, closed = closed, segments = segments })
                    (D.field "start" vec2)
                    (optionalField "closed" D.bool False)
                    (D.field "segments" (D.list segment))
                )
            )
        )


segment : Decoder Segment
segment =
    D.field "type" D.string
        |> D.andThen
            (\t ->
                case t of
                    "line" ->
                        D.map LineTo (D.field "to" vec2)

                    "cubic" ->
                        D.map3 CubicTo (D.field "c1" vec2) (D.field "c2" vec2) (D.field "to" vec2)

                    _ ->
                        D.fail ("Unknown segment type " ++ t)
            )


paintDecoder : Decoder Paint
paintDecoder =
    paint


strokeDecoder : Decoder Stroke
strokeDecoder =
    stroke


paint : Decoder Paint
paint =
    D.field "type" D.string
        |> D.andThen
            (\t ->
                case t of
                    "none" ->
                        D.succeed NoPaint

                    "solid" ->
                        D.map Solid (D.field "color" color)

                    "linearGradient" ->
                        D.map3 (\s e stops -> GradientPaint { kind = Paint.LinearGradient { start = s, end = e }, stops = stops })
                            (D.field "start" vec2)
                            (D.field "end" vec2)
                            (D.field "stops" (nonEmptyList stop))

                    "radialGradient" ->
                        D.map3 (\c r stops -> GradientPaint { kind = Paint.RadialGradient { center = c, radius = r }, stops = stops })
                            (D.field "center" vec2)
                            (D.field "radius" nonNegativeFloat)
                            (D.field "stops" (nonEmptyList stop))

                    _ ->
                        D.fail ("Unknown paint type " ++ t)
            )


stop : Decoder Paint.GradientStop
stop =
    D.map2 Paint.GradientStop (D.field "offset" unitFloat) (D.field "color" color)


stroke : Decoder Stroke
stroke =
    D.map7 Stroke
        (D.field "paint" paint)
        (D.field "width" nonNegativeFloat)
        (optionalField "cap" (enum "line cap" Paint.capFromCode) Paint.CapButt)
        (optionalField "join" (enum "line join" Paint.joinFromCode) Paint.JoinMiter)
        (optionalField "miterLimit" nonNegativeFloat 4)
        (optionalField "dashArray" (D.list nonNegativeFloat) [])
        (optionalField "dashOffset" finiteFloat 0)


effect : Decoder Effect
effect =
    D.field "type" D.string
        |> D.andThen
            (\t ->
                case t of
                    "blur" ->
                        D.map Blur (D.field "radius" nonNegativeFloat)

                    "dropShadow" ->
                        D.map3 (\o b c -> DropShadow { offset = o, blur = b, color = c })
                            (D.field "offset" vec2)
                            (D.field "blur" nonNegativeFloat)
                            (D.field "color" color)

                    _ ->
                        D.fail ("Unknown effect type " ++ t)
            )


track : Decoder Track
track =
    D.map5 Track
        (D.field "id" nonEmptyString)
        (D.field "target" (D.map2 Domain.Keyframe.TrackTarget (D.field "nodeId" nonEmptyString) (D.field "property" propertyPath)))
        (optionalField "enabled" D.bool True)
        (optionalField "locked" D.bool False)
        (D.field "keyframes" (D.list keyframe))
        |> D.andThen
            (\t ->
                if List.all (\k -> Property.valueTypeMatches t.target.property k.value) t.keyframes then
                    D.succeed { t | keyframes = List.sortBy .frame t.keyframes }

                else
                    D.fail ("Keyframe value type does not match " ++ Property.pathToCode t.target.property)
            )


keyframe : Decoder Keyframe
keyframe =
    D.map4 Keyframe
        (D.field "id" nonEmptyString)
        (D.field "frame" nonNegativeInt)
        (D.field "value" propertyValue)
        (optionalField "easing" easing Linear)


easing : Decoder Easing
easing =
    D.field "type" D.string
        |> D.andThen
            (\t ->
                case t of
                    "hold" ->
                        D.succeed Hold

                    "linear" ->
                        D.succeed Linear

                    "preset" ->
                        D.map Preset (D.field "name" (enum "easing preset" Easing.presetFromCode))

                    "cubicBezier" ->
                        D.map4 CubicBezier
                            (D.field "x1" unitFloat)
                            (D.field "y1" finiteFloat)
                            (D.field "x2" unitFloat)
                            (D.field "y2" finiteFloat)

                    "spring" ->
                        D.map4 (\m s d v -> Spring { mass = m, stiffness = s, damping = d, velocity = v })
                            (D.field "mass" positiveFloat)
                            (D.field "stiffness" positiveFloat)
                            (D.field "damping" nonNegativeFloat)
                            (optionalField "velocity" finiteFloat 0)

                    _ ->
                        D.fail ("Unknown easing type " ++ t)
            )


propertyPath : Decoder PropertyPath
propertyPath =
    enum "property path" Property.pathFromCode


propertyValue : Decoder PropertyValue
propertyValue =
    D.field "type" D.string
        |> D.andThen
            (\t ->
                case t of
                    "scalar" ->
                        D.map Scalar (D.field "value" finiteFloat)

                    "angle" ->
                        D.map Angle (D.field "value" finiteFloat)

                    "point" ->
                        D.map PointValue (D.field "value" vec2)

                    "size" ->
                        D.map SizeValue (D.field "value" vec2)

                    "color" ->
                        D.map ColorValue (D.field "value" color)

                    "bool" ->
                        D.map BoolValue (D.field "value" D.bool)

                    "string" ->
                        D.map StringValue (D.field "value" D.string)

                    "path" ->
                        D.map PathValue (D.field "value" path)

                    "numbers" ->
                        D.map NumberList (D.field "value" (D.list finiteFloat))

                    _ ->
                        D.fail ("Unknown value type " ++ t)
            )



-- PRIMITIVES


vec2 : Decoder Vec2
vec2 =
    D.map2 Vec2 (D.field "x" finiteFloat) (D.field "y" finiteFloat)


color : Decoder Rgba
color =
    D.map4 Color.rgba
        (D.field "r" unitFloat)
        (D.field "g" unitFloat)
        (D.field "b" unitFloat)
        (D.field "a" unitFloat)


finiteFloat : Decoder Float
finiteFloat =
    D.float
        |> D.andThen
            (\f ->
                if isNaN f || isInfinite f then
                    D.fail "Number must be finite"

                else
                    D.succeed f
            )


positiveFloat : Decoder Float
positiveFloat =
    finiteFloat
        |> D.andThen
            (\f ->
                if f > 0 then
                    D.succeed f

                else
                    D.fail "Number must be positive"
            )


nonNegativeFloat : Decoder Float
nonNegativeFloat =
    finiteFloat
        |> D.andThen
            (\f ->
                if f >= 0 then
                    D.succeed f

                else
                    D.fail "Number must be non-negative"
            )


unitFloat : Decoder Float
unitFloat =
    finiteFloat
        |> D.andThen
            (\f ->
                if f >= 0 && f <= 1 then
                    D.succeed f

                else
                    D.fail "Number must be between 0 and 1"
            )


nonNegativeInt : Decoder Int
nonNegativeInt =
    D.int
        |> D.andThen
            (\i ->
                if i >= 0 then
                    D.succeed i

                else
                    D.fail "Integer must be non-negative"
            )


nonEmptyString : Decoder String
nonEmptyString =
    D.string
        |> D.andThen
            (\s ->
                if String.isEmpty s then
                    D.fail "Identifier must not be empty"

                else
                    D.succeed s
            )


nonEmptyList : Decoder a -> Decoder (List a)
nonEmptyList d =
    D.list d
        |> D.andThen
            (\l ->
                if List.isEmpty l then
                    D.fail "List must not be empty"

                else
                    D.succeed l
            )


enum : String -> (String -> Maybe a) -> Decoder a
enum label fromCode =
    D.string
        |> D.andThen
            (\s ->
                case fromCode s of
                    Just v ->
                        D.succeed v

                    Nothing ->
                        D.fail ("Unknown " ++ label ++ ": " ++ s)
            )


optionalField : String -> Decoder a -> a -> Decoder a
optionalField name d default =
    D.oneOf
        [ D.field name (D.nullable d) |> D.map (Maybe.withDefault default)
        , D.succeed default
        ]
