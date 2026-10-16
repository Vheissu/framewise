module DocumentIO.Encode exposing
    ( document
    , easing
    , node
    , paint
    , pathGeometry
    , propertyPath
    , propertyValue
    , scene
    , stroke
    , track
    , vec2
    )

import Dict
import Domain.Color exposing (Rgba)
import Domain.Document exposing (AssetMeta, Document)
import Domain.Easing as Easing exposing (Easing(..))
import Domain.Keyframe exposing (Keyframe, Track)
import Domain.Node as Node exposing (Effect(..), Node, NodeGeometry(..))
import Domain.Paint as Paint exposing (Gradient, GradientKind(..), Paint(..), Stroke)
import Domain.Path as Path exposing (PathGeometry, Segment(..))
import Domain.Property as Property exposing (PropertyPath, PropertyValue(..))
import Domain.Scene as Scene exposing (Background(..), MotionPath, Scene)
import Domain.Transform exposing (Transform)
import Domain.Vec2 exposing (Vec2)
import Json.Encode as E


document : Document -> E.Value
document doc =
    E.object
        [ ( "id", E.string doc.id )
        , ( "schemaVersion", E.int doc.schemaVersion )
        , ( "metadata"
          , E.object
                [ ( "name", E.string doc.metadata.name )
                , ( "description", E.string doc.metadata.description )
                , ( "createdAt", E.string doc.metadata.createdAt )
                , ( "modifiedAt", E.string doc.metadata.modifiedAt )
                ]
          )
        , ( "sceneOrder", E.list E.string doc.sceneOrder )
        , ( "scenes", E.list scene (Domain.Document.orderedScenes doc) )
        , ( "assets", E.list asset (Dict.values doc.assets) )
        ]


asset : AssetMeta -> E.Value
asset a =
    E.object
        [ ( "id", E.string a.id )
        , ( "name", E.string a.name )
        , ( "mimeType", E.string a.mimeType )
        , ( "byteLength", E.int a.byteLength )
        , ( "sha256", E.string a.sha256 )
        , ( "width", E.int a.width )
        , ( "height", E.int a.height )
        ]


scene : Scene -> E.Value
scene s =
    E.object
        [ ( "id", E.string s.id )
        , ( "name", E.string s.name )
        , ( "description", E.string s.description )
        , ( "width", E.float s.width )
        , ( "height", E.float s.height )
        , ( "background", background s.background )
        , ( "fps", E.object [ ( "numerator", E.int s.fps.numerator ), ( "denominator", E.int s.fps.denominator ) ] )
        , ( "durationFrames", E.int s.durationFrames )
        , ( "playbackMode", E.string (Scene.playbackModeToCode s.playbackMode) )
        , ( "markers", E.list (\m -> E.object [ ( "frame", E.int m.frame ), ( "label", E.string m.label ) ]) s.markers )
        , ( "workRange"
          , case s.workRange of
                Just r ->
                    E.object [ ( "start", E.int r.start ), ( "end", E.int r.end ) ]

                Nothing ->
                    E.null
          )
        , ( "rootNodeIds", E.list E.string s.rootNodeIds )
        , ( "nodes", E.list node (List.filterMap (\id -> Dict.get id s.nodes) (Scene.flattenOrder s)) )
        , ( "tracks", E.list track (Dict.values s.tracks) )
        , ( "motionPaths", E.list motionPath (Dict.values s.motionPaths) )
        , ( "guides", E.list (\g -> E.object [ ( "horizontal", E.bool g.horizontal ), ( "position", E.float g.position ) ]) s.guides )
        ]


background : Background -> E.Value
background b =
    case b of
        Transparent ->
            E.object [ ( "type", E.string "transparent" ) ]

        SolidBackground c ->
            E.object [ ( "type", E.string "solid" ), ( "color", color c ) ]


motionPath : MotionPath -> E.Value
motionPath mp =
    E.object
        [ ( "id", E.string mp.id )
        , ( "name", E.string mp.name )
        , ( "geometry", path mp.geometry )
        , ( "revision", E.int mp.revision )
        ]


node : Node -> E.Value
node n =
    E.object
        ([ ( "id", E.string n.id )
         , ( "name", E.string n.name )
         , ( "kind", E.string (Node.kindCode n.geometry) )
         , ( "parentId", maybe E.string n.parentId )
         , ( "childIds", E.list E.string n.childIds )
         , ( "hidden", E.bool n.hidden )
         , ( "locked", E.bool n.locked )
         , ( "opacity", E.float n.opacity )
         , ( "transform", transform n.transform )
         , ( "geometry", geometry n.geometry )
         , ( "fill", paint n.fill )
         , ( "stroke", stroke n.stroke )
         , ( "effects", E.list effect n.effects )
         , ( "motion"
           , maybe (\m -> E.object [ ( "pathId", E.string m.pathId ), ( "orient", E.bool m.orient ) ]) n.motion
           )
         ]
            ++ (case n.importedElementId of
                    Just s ->
                        [ ( "metadata", E.object [ ( "importedElementId", E.string s ) ] ) ]

                    Nothing ->
                        []
               )
            ++ (case n.span of
                    Just s ->
                        [ ( "span", E.object [ ( "in", E.int s.inFrame ), ( "out", E.int s.outFrame ) ] ) ]

                    Nothing ->
                        []
               )
        )


transform : Transform -> E.Value
transform t =
    E.object
        [ ( "translation", vec2 t.translation )
        , ( "scale", vec2 t.scale )
        , ( "rotation", E.float t.rotation )
        , ( "skew", vec2 t.skew )
        , ( "pivot", vec2 t.pivot )
        ]


geometry : NodeGeometry -> E.Value
geometry g =
    case g of
        Rectangle r ->
            E.object [ ( "size", vec2 r.size ), ( "cornerRadius", E.float r.cornerRadius ) ]

        Ellipse e ->
            E.object [ ( "radii", vec2 e.radii ) ]

        Line l ->
            E.object [ ( "start", vec2 l.start ), ( "end", vec2 l.end ) ]

        Polygon p ->
            E.object
                [ ( "sides", E.int p.sides )
                , ( "radius", E.float p.radius )
                , ( "innerRadius", maybe E.float p.innerRadius )
                ]

        Path p ->
            path p

        Text t ->
            E.object
                [ ( "content", E.string t.content )
                , ( "fontFamily", E.string t.fontFamily )
                , ( "fontSize", E.float t.fontSize )
                , ( "fontWeight", E.int t.fontWeight )
                , ( "italic", E.bool t.italic )
                , ( "letterSpacing", E.float t.letterSpacing )
                , ( "align", E.string (Node.alignToCode t.align) )
                ]

        RasterImage i ->
            E.object
                [ ( "assetId", E.string i.assetId )
                , ( "size", vec2 i.size )
                , ( "naturalSize", vec2 i.naturalSize )
                ]

        Group ->
            E.object []

        ClippingGroup ->
            E.object []


pathGeometry : PathGeometry -> E.Value
pathGeometry =
    path


path : PathGeometry -> E.Value
path p =
    E.object
        [ ( "subpaths"
          , E.list
                (\s ->
                    E.object
                        [ ( "start", vec2 s.start )
                        , ( "closed", E.bool s.closed )
                        , ( "segments", E.list segment s.segments )
                        ]
                )
                p.subpaths
          )
        ]


segment : Segment -> E.Value
segment s =
    case s of
        LineTo p ->
            E.object [ ( "type", E.string "line" ), ( "to", vec2 p ) ]

        CubicTo a b p ->
            E.object [ ( "type", E.string "cubic" ), ( "c1", vec2 a ), ( "c2", vec2 b ), ( "to", vec2 p ) ]


paint : Paint -> E.Value
paint p =
    case p of
        NoPaint ->
            E.object [ ( "type", E.string "none" ) ]

        Solid c ->
            E.object [ ( "type", E.string "solid" ), ( "color", color c ) ]

        GradientPaint g ->
            gradient g


gradient : Gradient -> E.Value
gradient g =
    let
        kindFields =
            case g.kind of
                LinearGradient l ->
                    [ ( "type", E.string "linearGradient" ), ( "start", vec2 l.start ), ( "end", vec2 l.end ) ]

                RadialGradient r ->
                    [ ( "type", E.string "radialGradient" ), ( "center", vec2 r.center ), ( "radius", E.float r.radius ) ]
    in
    E.object
        (kindFields
            ++ [ ( "stops", E.list (\s -> E.object [ ( "offset", E.float s.offset ), ( "color", color s.color ) ]) g.stops ) ]
        )


stroke : Stroke -> E.Value
stroke s =
    E.object
        [ ( "paint", paint s.paint )
        , ( "width", E.float s.width )
        , ( "cap", E.string (Paint.capToCode s.cap) )
        , ( "join", E.string (Paint.joinToCode s.join) )
        , ( "miterLimit", E.float s.miterLimit )
        , ( "dashArray", E.list E.float s.dashArray )
        , ( "dashOffset", E.float s.dashOffset )
        ]


effect : Effect -> E.Value
effect e =
    case e of
        Blur r ->
            E.object [ ( "type", E.string "blur" ), ( "radius", E.float r ) ]

        DropShadow d ->
            E.object
                [ ( "type", E.string "dropShadow" )
                , ( "offset", vec2 d.offset )
                , ( "blur", E.float d.blur )
                , ( "color", color d.color )
                ]


track : Track -> E.Value
track t =
    E.object
        [ ( "id", E.string t.id )
        , ( "target", E.object [ ( "nodeId", E.string t.target.nodeId ), ( "property", propertyPath t.target.property ) ] )
        , ( "enabled", E.bool t.enabled )
        , ( "locked", E.bool t.locked )
        , ( "keyframes", E.list keyframe t.keyframes )
        ]


keyframe : Keyframe -> E.Value
keyframe k =
    E.object
        [ ( "id", E.string k.id )
        , ( "frame", E.int k.frame )
        , ( "value", propertyValue k.value )
        , ( "easing", easing k.easing )
        ]


easing : Easing -> E.Value
easing e =
    case e of
        Hold ->
            E.object [ ( "type", E.string "hold" ) ]

        Linear ->
            E.object [ ( "type", E.string "linear" ) ]

        Preset p ->
            E.object [ ( "type", E.string "preset" ), ( "name", E.string (Easing.presetToCode p) ) ]

        CubicBezier x1 y1 x2 y2 ->
            E.object
                [ ( "type", E.string "cubicBezier" )
                , ( "x1", E.float x1 )
                , ( "y1", E.float y1 )
                , ( "x2", E.float x2 )
                , ( "y2", E.float y2 )
                ]

        Spring s ->
            E.object
                [ ( "type", E.string "spring" )
                , ( "mass", E.float s.mass )
                , ( "stiffness", E.float s.stiffness )
                , ( "damping", E.float s.damping )
                , ( "velocity", E.float s.velocity )
                ]


propertyPath : PropertyPath -> E.Value
propertyPath p =
    E.string (Property.pathToCode p)


propertyValue : PropertyValue -> E.Value
propertyValue v =
    case v of
        Scalar f ->
            E.object [ ( "type", E.string "scalar" ), ( "value", E.float f ) ]

        Angle a ->
            E.object [ ( "type", E.string "angle" ), ( "value", E.float a ) ]

        PointValue p ->
            E.object [ ( "type", E.string "point" ), ( "value", vec2 p ) ]

        SizeValue p ->
            E.object [ ( "type", E.string "size" ), ( "value", vec2 p ) ]

        ColorValue c ->
            E.object [ ( "type", E.string "color" ), ( "value", color c ) ]

        BoolValue b ->
            E.object [ ( "type", E.string "bool" ), ( "value", E.bool b ) ]

        StringValue s ->
            E.object [ ( "type", E.string "string" ), ( "value", E.string s ) ]

        PathValue p ->
            E.object [ ( "type", E.string "path" ), ( "value", path p ) ]

        NumberList l ->
            E.object [ ( "type", E.string "numbers" ), ( "value", E.list E.float l ) ]


vec2 : Vec2 -> E.Value
vec2 v =
    E.object [ ( "x", E.float v.x ), ( "y", E.float v.y ) ]


color : Rgba -> E.Value
color c =
    E.object [ ( "r", E.float c.r ), ( "g", E.float c.g ), ( "b", E.float c.b ), ( "a", E.float c.a ) ]


maybe : (a -> E.Value) -> Maybe a -> E.Value
maybe f m =
    case m of
        Just v ->
            f v

        Nothing ->
            E.null
