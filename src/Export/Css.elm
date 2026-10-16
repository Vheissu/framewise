module Export.Css exposing (Options, defaultOptions, export)

{-| SVG + CSS export. The scene is rendered with nested channel groups that
carry stable ids; an embedded `<style>` element animates them with
`@keyframes`. Only transform, opacity, visibility and paint channels are
exported; the capability report blocks anything else unless the user chooses
to skip affected tracks.
-}

import Dict
import Domain.Color as Color
import Domain.Document exposing (Document)
import Domain.Easing
import Domain.Evaluate as Evaluate
import Domain.Fps as Fps
import Domain.Keyframe exposing (Track)
import Domain.Node exposing (Node)
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (PlaybackMode(..), Scene)
import Export.Animated as Animated exposing (Channel(..))
import Export.Capability as Capability
import Export.Format
import Export.Spans as Spans
import Export.Timing as Timing
import Render.SvgDoc as Svg exposing (Element)


type alias Options =
    { includeBackground : Bool
    , title : Maybe String
    , description : Maybe String
    , skipUnsupported : Bool
    , reducedMotionPause : Bool
    }


defaultOptions : Options
defaultOptions =
    { includeBackground = True, title = Nothing, description = Nothing, skipUnsupported = False, reducedMotionPause = True }


export : Options -> Document -> Scene -> Result String { svg : String, css : String, report : Capability.Report }
export options doc unbaked =
    let
        -- layer in and out points become visibility keys
        scene =
            Spans.bake unbaked

        report =
            Capability.report Export.Format.SvgCss scene
    in
    if report.unsupportedCount > 0 && not options.skipUnsupported then
        Err "Some tracks cannot be represented with CSS. Switch to SMIL or the HTML player, or choose Skip Affected Tracks."

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
                        { scene = scene, report = report, prefix = prefix }

                    hooks =
                        { channelAttrs = channelAttrs ctx
                        , channelChildren = \_ _ -> []
                        , shapeAttrs = \node -> [ ( "id", channelId ctx node Shape ) ]
                        , shapeChildren = \_ -> []
                        , filterChildren = \_ -> []
                        }

                    body =
                        Animated.renderAnimatedScene renderOptions hooks scene resolved

                    css =
                        stylesheet options ctx

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
                            (meta ++ [ Svg.el "style" [] [ Svg.text css ] ] ++ body)
                in
                Ok
                    { svg = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" ++ Svg.toString root
                    , css = css
                    , report = report
                    }


type alias Ctx =
    { scene : Scene, report : Capability.Report, prefix : String }


channelId : Ctx -> Node -> Channel -> String
channelId ctx node channel =
    ctx.prefix ++ "-" ++ Animated.channelCode channel ++ "-" ++ node.id


channelAttrs : Ctx -> Node -> Channel -> List ( String, String )
channelAttrs ctx node channel =
    case channel of
        Outer ->
            []

        _ ->
            [ ( "id", channelId ctx node channel ) ]


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


stylesheet : Options -> Ctx -> String
stylesheet options ctx =
    let
        rules =
            Dict.values ctx.scene.nodes
                |> List.concatMap (nodeRules ctx)

        reduced =
            if options.reducedMotionPause then
                "\n@media (prefers-reduced-motion: reduce) { [id^=\"" ++ ctx.prefix ++ "-\"] { animation-play-state: paused; } }\n"

            else
                ""
    in
    "\n[id^=\"" ++ ctx.prefix ++ "-\"] { transform-box: view-box; transform-origin: 0 0; }\n" ++ String.join "\n" rules ++ reduced


nodeRules : Ctx -> Node -> List String
nodeRules ctx node =
    let
        tracks =
            Scene.tracksFor node.id ctx.scene
                |> List.filter (\t -> t.enabled && not (List.isEmpty t.keyframes) && isSupported ctx t)

        rulesFor track =
            case track.target.property of
                Position ->
                    [ transformRule ctx node Translate "translate" pointPx track ]

                Scale ->
                    [ transformRule ctx node ScaleChannel "scale" pointPlain track ]

                Rotation ->
                    [ transformRule ctx node Rotate "rotate" angleDeg track ]

                Skew ->
                    [ transformRule ctx node SkewX "skewX" (componentDeg .x) track
                    , transformRule ctx node SkewY "skewY" (componentDeg .y) track
                    ]

                Pivot ->
                    [ transformRule ctx node PivotIn "translate" pointPx track
                    , transformRule ctx node PivotOut "translate" negPointPx track
                    ]

                Opacity ->
                    [ propertyRule ctx node (ctx.prefix ++ "-node-" ++ node.id) "opacity" scalar track ]

                Visible ->
                    [ propertyRule ctx node (ctx.prefix ++ "-node-" ++ node.id) "visibility" visibility track ]

                FillColor ->
                    [ propertyRule ctx node (channelId ctx node Shape) "fill" colorRgba track ]

                StrokeColor ->
                    [ propertyRule ctx node (channelId ctx node Shape) "stroke" colorRgba track ]

                StrokeWidth ->
                    [ propertyRule ctx node (channelId ctx node Shape) "stroke-width" scalarPx track ]

                DashOffset ->
                    [ propertyRule ctx node (channelId ctx node Shape) "stroke-dashoffset" scalarPx track ]

                _ ->
                    []
    in
    List.concatMap rulesFor tracks


transformRule : Ctx -> Node -> Channel -> String -> (PropertyValue -> String) -> Track -> String
transformRule ctx node channel fn format track =
    propertyRule ctx node (channelId ctx node channel) "transform" (\v -> fn ++ "(" ++ format v ++ ")") track


propertyRule : Ctx -> Node -> String -> String -> (PropertyValue -> String) -> Track -> String
propertyRule ctx _ elementId property format track =
    let
        scene =
            ctx.scene

        n =
            max 1 scene.durationFrames

        name =
            elementId ++ "-" ++ String.replace "-" "_" property

        seconds =
            Fps.framesToSeconds scene.fps (toFloat n)

        ( iteration, direction ) =
            case scene.playbackMode of
                PlayOnce ->
                    ( "1", "normal" )

                Repeat ->
                    ( "infinite", "normal" )

                PingPong ->
                    ( "infinite", "alternate" )

        discreteProp =
            property == "visibility"

        -- discrete values step at their keys whatever the easing says
        planned =
            if discreteProp then
                { track | keyframes = List.map (\k -> { k | easing = Domain.Easing.Linear }) track.keyframes }

            else
                track

        frames =
            case Timing.planTrack False n planned of
                Timing.Native keys ->
                    List.indexedMap
                        (\i k ->
                            let
                                isLast =
                                    i == List.length keys - 1

                                timing =
                                    if isLast then
                                        ""

                                    else if discreteProp then
                                        " animation-timing-function: step-end;"

                                    else
                                        case k.spline of
                                            Just s ->
                                                " animation-timing-function: cubic-bezier(" ++ String.join ", " (List.map Animated.num [ s.x1, s.y1, s.x2, s.y2 ]) ++ ");"

                                            Nothing ->
                                                ""
                            in
                            percent k.frame n ++ " { " ++ property ++ ": " ++ format k.value ++ ";" ++ timing ++ " }"
                        )
                        keys

                Timing.BakedPlan samples _ ->
                    List.map
                        (\s ->
                            percent s.frame n
                                ++ " { "
                                ++ property
                                ++ ": "
                                ++ format s.value
                                ++ ";"
                                ++ (if discreteProp then
                                        " animation-timing-function: step-end;"

                                    else
                                        " animation-timing-function: linear;"
                                   )
                                ++ " }"
                        )
                        samples
    in
    "#"
        ++ elementId
        ++ " { animation: "
        ++ name
        ++ " "
        ++ Animated.num seconds
        ++ "s linear "
        ++ iteration
        ++ " "
        ++ direction
        ++ " both; }\n@keyframes "
        ++ name
        ++ " { "
        ++ String.join " " frames
        ++ " }"


percent : Int -> Int -> String
percent frame n =
    Animated.num (toFloat frame / toFloat n * 100) ++ "%"



-- FORMATTERS


scalar : PropertyValue -> String
scalar v =
    case v of
        Scalar s ->
            Animated.num s

        _ ->
            "0"


scalarPx : PropertyValue -> String
scalarPx v =
    scalar v ++ "px"


angleDeg : PropertyValue -> String
angleDeg v =
    case v of
        Angle a ->
            Animated.num a ++ "deg"

        _ ->
            "0deg"


componentDeg : ({ x : Float, y : Float } -> Float) -> PropertyValue -> String
componentDeg get v =
    case v of
        PointValue p ->
            Animated.num (get p) ++ "deg"

        _ ->
            "0deg"


pointPx : PropertyValue -> String
pointPx v =
    case v of
        PointValue p ->
            Animated.num p.x ++ "px, " ++ Animated.num p.y ++ "px"

        _ ->
            "0px, 0px"


negPointPx : PropertyValue -> String
negPointPx v =
    case v of
        PointValue p ->
            Animated.num -p.x ++ "px, " ++ Animated.num -p.y ++ "px"

        _ ->
            "0px, 0px"


pointPlain : PropertyValue -> String
pointPlain v =
    case v of
        PointValue p ->
            Animated.num p.x ++ ", " ++ Animated.num p.y

        _ ->
            "1, 1"


colorRgba : PropertyValue -> String
colorRgba v =
    case v of
        ColorValue c ->
            Color.toCss c

        _ ->
            "rgba(0,0,0,1)"


visibility : PropertyValue -> String
visibility v =
    case v of
        BoolValue True ->
            "visible"

        _ ->
            "hidden"
