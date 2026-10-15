module Export.Smil exposing (Options, defaultOptions, export)

{-| Animated SVG export using SMIL. Each animated channel becomes an
`<animate>`/`<animateTransform>`/`<animateMotion>` child of the group that
owns that channel, so animations never conflict on one attribute.

Easing representable as a cubic Bézier with all control values in `[0,1]`
is exported with `calcMode="spline"`. Anything else is baked to per-frame
samples with `calcMode="linear"`. Ping-pong is baked into a mirrored cycle.

-}

import Dict
import Domain.Color as Color
import Domain.Document exposing (Document)
import Domain.Evaluate as Evaluate
import Domain.Fps as Fps
import Domain.Interpolation as Interpolation
import Domain.Keyframe exposing (Track)
import Domain.Node as Node exposing (Node)
import Domain.Path as Path
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (PlaybackMode(..), Scene)
import Export.Animated as Animated exposing (Channel(..))
import Export.Capability as Capability
import Export.Format
import Export.Timing as Timing
import Render.SvgDoc as Svg exposing (Element)


type alias Options =
    { includeBackground : Bool
    , title : Maybe String
    , description : Maybe String
    , skipUnsupported : Bool
    }


defaultOptions : Options
defaultOptions =
    { includeBackground = True, title = Nothing, description = Nothing, skipUnsupported = False }


export : Options -> Document -> Scene -> Result String { svg : String, report : Capability.Report }
export options doc scene =
    let
        report =
            Capability.report Export.Format.AnimatedSvg scene
    in
    if report.unsupportedCount > 0 && not options.skipUnsupported then
        Err "Some tracks cannot be represented in SMIL. Switch to the HTML player or choose Skip Affected Tracks."

    else
        case Evaluate.evaluateScene doc scene.id 0 of
            Nothing ->
                Err "Scene not found"

            Just resolved ->
                let
                    prefix =
                        "fw-" ++ String.left 8 (String.filter Char.isAlphaNum scene.id)

                    renderOptions =
                        { idPrefix = prefix
                        , assetUrls = Dict.map (\id _ -> "fw-asset://" ++ id) doc.assets
                        , includeBackground = options.includeBackground
                        , includeIds = True
                        , title = options.title
                        , description = options.description
                        , standalone = True
                        }

                    ctx =
                        { scene = scene, report = report }

                    hooks =
                        { channelAttrs = \_ _ -> []
                        , channelChildren = channelAnimations ctx
                        , shapeAttrs = \_ -> []
                        , shapeChildren = shapeAnimations ctx
                        , filterChildren = filterAnimations ctx
                        }

                    body =
                        Animated.renderAnimatedScene renderOptions hooks scene resolved

                    meta =
                        List.filterMap identity
                            [ Maybe.map (\t -> Svg.el "title" [] [ Svg.text t ]) options.title
                            , Maybe.map (\d -> Svg.el "desc" [] [ Svg.text d ]) options.description
                            ]

                    root =
                        Svg.el "svg"
                            [ ( "xmlns", "http://www.w3.org/2000/svg" )
                            , ( "xmlns:xlink", "http://www.w3.org/1999/xlink" )
                            , ( "width", Animated.num scene.width )
                            , ( "height", Animated.num scene.height )
                            , ( "viewBox", "0 0 " ++ Animated.num scene.width ++ " " ++ Animated.num scene.height )
                            ]
                            (meta ++ body)
                in
                Ok { svg = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" ++ Svg.toString root, report = report }


type alias Ctx =
    { scene : Scene, report : Capability.Report }


isSupported : Ctx -> Track -> Bool
isSupported ctx track =
    ctx.report.items
        |> List.filter (\i -> i.nodeId == track.target.nodeId && i.property == Just track.target.property)
        |> List.all
            (\i ->
                case i.status of
                    Capability.Unsupported _ ->
                        False

                    _ ->
                        True
            )


trackOf : Ctx -> Node -> PropertyPath -> Maybe Track
trackOf ctx node property =
    Scene.trackFor node.id property ctx.scene
        |> Maybe.andThen
            (\t ->
                if t.enabled && List.length t.keyframes >= 1 && isSupported ctx t then
                    Just t

                else
                    Nothing
            )


channelAnimations : Ctx -> Node -> Channel -> List Element
channelAnimations ctx node channel =
    let
        withTrack property f =
            trackOf ctx node property |> Maybe.map (f ctx.scene) |> Maybe.withDefault []
    in
    case channel of
        Outer ->
            withTrack Opacity (\scene t -> [ animate scene "opacity" (plainValues scalarString) t ])
                ++ withTrack Visible (\scene t -> [ discrete scene "visibility" visibilityString t ])

        Translate ->
            withTrack Position (\scene t -> [ animateTransform scene "translate" (plainValues pointString) t ])

        Motion ->
            withTrack MotionProgress (animateMotion node)

        PivotIn ->
            withTrack Pivot (\scene t -> [ animateTransform scene "translate" (plainValues pointString) t ])

        Rotate ->
            withTrack Rotation (\scene t -> [ animateTransform scene "rotate" (plainValues angleString) t ])

        SkewX ->
            withTrack Skew (\scene t -> [ animateTransform scene "skewX" (plainValues (componentString .x)) t ])

        SkewY ->
            withTrack Skew (\scene t -> [ animateTransform scene "skewY" (plainValues (componentString .y)) t ])

        ScaleChannel ->
            withTrack Scale (\scene t -> [ animateTransform scene "scale" (plainValues pointString) t ])

        PivotOut ->
            withTrack Pivot (\scene t -> [ animateTransform scene "translate" (plainValues negPointString) t ])

        Shape ->
            []


shapeAnimations : Ctx -> Node -> List Element
shapeAnimations ctx node =
    let
        withTrack property f =
            trackOf ctx node property |> Maybe.map (f ctx.scene) |> Maybe.withDefault []
    in
    withTrack FillColor (colorAnimations "fill")
        ++ withTrack StrokeColor (colorAnimations "stroke")
        ++ withTrack StrokeWidth (\scene t -> [ animate scene "stroke-width" (plainValues scalarString) t ])
        ++ withTrack DashOffset (\scene t -> [ animate scene "stroke-dashoffset" (plainValues scalarString) t ])
        ++ withTrack RectSize
            (\scene t ->
                [ animate scene "width" (plainValues (componentString .x)) t
                , animate scene "height" (plainValues (componentString .y)) t
                ]
            )
        ++ withTrack RectCornerRadius (\scene t -> [ animate scene "rx" (plainValues scalarString) t ])
        ++ withTrack EllipseRadii
            (\scene t ->
                [ animate scene "rx" (plainValues (componentString .x)) t
                , animate scene "ry" (plainValues (componentString .y)) t
                ]
            )
        ++ withTrack PathGeometryProp (\scene t -> [ animate scene "d" (plainValues pathString) t ])
        ++ withTrack FontSize (\scene t -> [ animate scene "font-size" (plainValues scalarString) t ])


filterAnimations : Ctx -> Node -> List Element
filterAnimations ctx node =
    trackOf ctx node BlurRadius
        |> Maybe.map (\t -> [ animate ctx.scene "stdDeviation" (plainValues scalarString) t ])
        |> Maybe.withDefault []


colorAnimations : String -> Scene -> Track -> List Element
colorAnimations attr scene track =
    let
        alphaVaries =
            track.keyframes
                |> List.any
                    (\k ->
                        case k.value of
                            ColorValue c ->
                                c.a < 1

                            _ ->
                                False
                    )
    in
    animate scene attr (plainValues colorHexString) track
        :: (if alphaVaries then
                [ animate scene (attr ++ "-opacity") (plainValues colorAlphaString) track ]

            else
                []
           )



-- VALUE FORMATTERS


plainValues : (PropertyValue -> String) -> PropertyValue -> String
plainValues f =
    f


scalarString : PropertyValue -> String
scalarString v =
    case v of
        Scalar s ->
            Animated.num s

        Angle a ->
            Animated.num a

        _ ->
            "0"


angleString : PropertyValue -> String
angleString =
    scalarString


pointString : PropertyValue -> String
pointString v =
    case v of
        PointValue p ->
            Animated.num p.x ++ " " ++ Animated.num p.y

        SizeValue p ->
            Animated.num p.x ++ " " ++ Animated.num p.y

        _ ->
            "0 0"


negPointString : PropertyValue -> String
negPointString v =
    case v of
        PointValue p ->
            Animated.num -p.x ++ " " ++ Animated.num -p.y

        _ ->
            "0 0"


componentString : ({ x : Float, y : Float } -> Float) -> PropertyValue -> String
componentString get v =
    case v of
        PointValue p ->
            Animated.num (get p)

        SizeValue p ->
            Animated.num (get p)

        _ ->
            "0"


colorHexString : PropertyValue -> String
colorHexString v =
    case v of
        ColorValue c ->
            Color.toHex { c | a = 1 }

        _ ->
            "#000000"


colorAlphaString : PropertyValue -> String
colorAlphaString v =
    case v of
        ColorValue c ->
            Animated.num c.a

        _ ->
            "1"


pathString : PropertyValue -> String
pathString v =
    case v of
        PathValue p ->
            Path.serialize p

        _ ->
            ""


visibilityString : PropertyValue -> String
visibilityString v =
    case v of
        BoolValue True ->
            "visible"

        _ ->
            "hidden"



-- ANIMATION ELEMENTS


{-| Frames of the exported cycle and its duration, accounting for ping-pong.
-}
cycle : Scene -> { frames : Int, dur : Float, repeat : String, freeze : Bool }
cycle scene =
    let
        n =
            max 1 scene.durationFrames

        seconds f =
            Fps.framesToSeconds scene.fps (toFloat f)
    in
    case scene.playbackMode of
        PlayOnce ->
            { frames = n, dur = seconds n, repeat = "1", freeze = True }

        Repeat ->
            { frames = n, dur = seconds n, repeat = "indefinite", freeze = False }

        PingPong ->
            { frames = 2 * n, dur = seconds (2 * n), repeat = "indefinite", freeze = False }


timingAttrs : Scene -> List ( String, String )
timingAttrs scene =
    let
        c =
            cycle scene
    in
    [ ( "begin", "0s" )
    , ( "dur", Animated.num c.dur ++ "s" )
    , ( "repeatCount", c.repeat )
    ]
        ++ (if c.freeze then
                [ ( "fill", "freeze" ) ]

            else
                []
           )


{-| Values/keyTimes/calcMode/keySplines attributes for a track.
-}
keyAttrs : Scene -> (PropertyValue -> String) -> Track -> List ( String, String )
keyAttrs scene format track =
    let
        n =
            max 1 scene.durationFrames
    in
    case scene.playbackMode of
        PingPong ->
            let
                samples =
                    Timing.bake n track

                mirrored =
                    samples ++ List.reverse (List.take (List.length samples - 1) samples)

                total =
                    toFloat (2 * n)

                frames =
                    List.indexedMap (\i s -> ( toFloat i / total, format s.value )) mirrored
            in
            [ ( "values", String.join ";" (List.map Tuple.second frames) )
            , ( "keyTimes", String.join ";" (List.map (Tuple.first >> Animated.num) frames) )
            , ( "calcMode", "linear" )
            ]

        _ ->
            case Timing.planTrack True n track of
                Timing.Native keys ->
                    let
                        splines =
                            keys
                                |> List.take (List.length keys - 1)
                                |> List.map (\k -> k.spline |> Maybe.withDefault Timing.linearSpline |> splineString)
                    in
                    [ ( "values", String.join ";" (List.map (.value >> format) keys) )
                    , ( "keyTimes", String.join ";" (List.map (\k -> Animated.num (toFloat k.frame / toFloat n)) keys) )
                    , ( "calcMode", "spline" )
                    , ( "keySplines", String.join ";" splines )
                    ]

                Timing.BakedPlan samples _ ->
                    [ ( "values", String.join ";" (List.map (.value >> format) samples) )
                    , ( "keyTimes", String.join ";" (List.map (\s -> Animated.num (toFloat s.frame / toFloat n)) samples) )
                    , ( "calcMode", "linear" )
                    ]


splineString : Timing.Spline -> String
splineString s =
    String.join " " (List.map Animated.num [ s.x1, s.y1, s.x2, s.y2 ])


animate : Scene -> String -> (PropertyValue -> String) -> Track -> Element
animate scene attr format track =
    Svg.el "animate"
        ([ ( "attributeName", attr ) ] ++ keyAttrs scene format track ++ timingAttrs scene)
        []


animateTransform : Scene -> String -> (PropertyValue -> String) -> Track -> Element
animateTransform scene transformType format track =
    Svg.el "animateTransform"
        ([ ( "attributeName", "transform" ), ( "type", transformType ) ]
            ++ keyAttrs scene format track
            ++ timingAttrs scene
        )
        []


discrete : Scene -> String -> (PropertyValue -> String) -> Track -> Element
discrete scene attr format track =
    let
        n =
            max 1 scene.durationFrames

        keys =
            track.keyframes |> List.filter (\k -> k.frame <= n)

        padded =
            case keys of
                first :: _ ->
                    if first.frame > 0 then
                        { first | frame = 0 } :: keys

                    else
                        keys

                [] ->
                    []
    in
    Svg.el "animate"
        ([ ( "attributeName", attr )
         , ( "values", String.join ";" (List.map (.value >> format) padded) )
         , ( "keyTimes", String.join ";" (List.map (\k -> Animated.num (toFloat k.frame / toFloat n)) padded) )
         , ( "calcMode", "discrete" )
         ]
            ++ timingAttrs scene
        )
        []


animateMotion : Node -> Scene -> Track -> List Element
animateMotion node scene track =
    case node.motion |> Maybe.andThen (\m -> Dict.get m.pathId scene.motionPaths) of
        Nothing ->
            []

        Just mp ->
            let
                orient =
                    node.motion |> Maybe.map .orient |> Maybe.withDefault True

                progress v =
                    case v of
                        Scalar p ->
                            Animated.num (clamp 0 1 p)

                        _ ->
                            "0"

                attrs =
                    keyAttrs scene progress track

                -- animateMotion uses keyPoints instead of values
                renamed =
                    List.map
                        (\( k, v ) ->
                            if k == "values" then
                                ( "keyPoints", v )

                            else
                                ( k, v )
                        )
                        attrs
            in
            [ Svg.el "animateMotion"
                ([ ( "path", Path.serialize mp.geometry )
                 , ( "rotate"
                   , if orient then
                        "auto"

                     else
                        "0"
                   )
                 ]
                    ++ renamed
                    ++ timingAttrs scene
                )
                []
            ]
