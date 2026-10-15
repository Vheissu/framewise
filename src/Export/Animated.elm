module Export.Animated exposing
    ( Channel(..)
    , NodeState
    , channelCode
    , channelTransform
    , nodeStateAt
    , num
    , renderAnimatedScene
    )

{-| Shared structure for the declarative animated exporters (SMIL and CSS).

Each node is rendered as nested groups, one per transform channel, so that
individual channels can be animated independently without conflicting
animations on the same attribute:

    g.outer   (id, opacity, filter)
      g.translate   translate(tx ty)
        g.motion    [motion path offset/rotation]
          g.pivot   translate(px py)
            g.rotate rotate(r)
              g.skewx skewX(sx)
                g.skewy skewY(sy)
                  g.scale scale(sx sy)
                    g.pivotInv translate(-px -py)
                      shape | children

The composition of these groups equals `Domain.Matrix.fromComponentsWithMotion`.

-}

import Dict
import Domain.Color as Color
import Domain.Evaluate as Evaluate exposing (ResolvedScene)
import Domain.Node as Node exposing (Node, NodeGeometry(..))
import Domain.Paint exposing (Paint(..))
import Domain.Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene as Scene exposing (Scene)
import Domain.Transform exposing (Transform)
import Domain.Vec2 exposing (Vec2)
import Render.Scene as Render
import Render.SvgDoc as Svg exposing (Element)


type Channel
    = Outer
    | Translate
    | Motion
    | PivotIn
    | Rotate
    | SkewX
    | SkewY
    | ScaleChannel
    | PivotOut
    | Shape


channelCode : Channel -> String
channelCode c =
    case c of
        Outer ->
            "outer"

        Translate ->
            "translate"

        Motion ->
            "motion"

        PivotIn ->
            "pivot"

        Rotate ->
            "rotate"

        SkewX ->
            "skewx"

        SkewY ->
            "skewy"

        ScaleChannel ->
            "scale"

        PivotOut ->
            "pivotinv"

        Shape ->
            "shape"


type alias NodeState =
    { transform : Transform
    , opacity : Float
    , hidden : Bool
    , fill : Paint
    , strokePaint : Paint
    , strokeWidth : Float
    , dashOffset : Float
    , geometry : NodeGeometry
    }


{-| Evaluated per-channel state of a node at a frame.
-}
nodeStateAt : Scene -> Float -> Node -> NodeState
nodeStateAt scene frame node =
    let
        value p =
            Evaluate.evaluateNodeProperty scene frame node p

        point p default =
            case value p of
                Just (PointValue v) ->
                    v

                _ ->
                    default

        scalar p default =
            case value p of
                Just (Scalar v) ->
                    v

                _ ->
                    default

        base =
            node.transform
    in
    { transform =
        { translation = point Position base.translation
        , scale = point Scale base.scale
        , rotation =
            case value Rotation of
                Just (Angle a) ->
                    a

                _ ->
                    base.rotation
        , skew = point Skew base.skew
        , pivot = point Pivot base.pivot
        }
    , opacity = scalar Opacity node.opacity
    , hidden =
        case value Visible of
            Just (BoolValue v) ->
                not v

            _ ->
                node.hidden
    , fill =
        case value FillColor of
            Just (ColorValue c) ->
                Domain.Paint.setPaintColor c node.fill

            _ ->
                node.fill
    , strokePaint =
        case value StrokeColor of
            Just (ColorValue c) ->
                Domain.Paint.setPaintColor c node.stroke.paint

            _ ->
                node.stroke.paint
    , strokeWidth = scalar StrokeWidth node.stroke.width
    , dashOffset = scalar DashOffset node.stroke.dashOffset
    , geometry =
        case node.geometry of
            Rectangle r ->
                Rectangle
                    { size =
                        case value RectSize of
                            Just (SizeValue s) ->
                                s

                            _ ->
                                r.size
                    , cornerRadius = scalar RectCornerRadius r.cornerRadius
                    }

            Ellipse e ->
                Ellipse
                    { radii =
                        case value EllipseRadii of
                            Just (SizeValue s) ->
                                s

                            _ ->
                                e.radii
                    }

            Path p ->
                case value PathGeometryProp of
                    Just (PathValue g) ->
                        Path g

                    _ ->
                        Path p

            Text t ->
                Text
                    { t
                        | fontSize = scalar FontSize t.fontSize
                        , content =
                            case value TextContent of
                                Just (StringValue s) ->
                                    s

                                _ ->
                                    t.content
                    }

            other ->
                other
    }


{-| Static transform attribute value for a channel.
-}
channelTransform : Channel -> Transform -> Maybe String
channelTransform channel t =
    case channel of
        Translate ->
            Just ("translate(" ++ num t.translation.x ++ " " ++ num t.translation.y ++ ")")

        PivotIn ->
            Just ("translate(" ++ num t.pivot.x ++ " " ++ num t.pivot.y ++ ")")

        Rotate ->
            Just ("rotate(" ++ num t.rotation ++ ")")

        SkewX ->
            Just ("skewX(" ++ num t.skew.x ++ ")")

        SkewY ->
            Just ("skewY(" ++ num t.skew.y ++ ")")

        ScaleChannel ->
            Just ("scale(" ++ num t.scale.x ++ " " ++ num t.scale.y ++ ")")

        PivotOut ->
            Just ("translate(" ++ num -t.pivot.x ++ " " ++ num -t.pivot.y ++ ")")

        _ ->
            Nothing


type alias Hooks =
    { channelAttrs : Node -> Channel -> List ( String, String )
    , channelChildren : Node -> Channel -> List Element
    , shapeAttrs : Node -> List ( String, String )
    , shapeChildren : Node -> List Element
    , filterChildren : Node -> List Element
    }


{-| Render the scene body (defs, background, nodes) using nested channel
groups. `resolved` is the scene evaluated at the base frame and is used for
defs and hidden-state; per-node attribute values come from `nodeStateAt`.
-}
renderAnimatedScene : Render.Options -> Hooks -> Scene -> ResolvedScene -> List Element
renderAnimatedScene options hooks scene resolved =
    let
        defs =
            Render.renderDefs options resolved
                |> List.map (augmentFilter hooks scene)

        bg =
            case ( options.includeBackground, scene.background ) of
                ( True, Scene.SolidBackground c ) ->
                    [ Svg.el "rect"
                        [ ( "width", num scene.width ), ( "height", num scene.height ), ( "fill", Color.toHex c ) ]
                        []
                    ]

                _ ->
                    []
    in
    (if List.isEmpty defs then
        []

     else
        [ Svg.el "defs" [] defs ]
    )
        ++ bg
        ++ List.concatMap (renderNode options hooks scene resolved) scene.rootNodeIds


augmentFilter : Hooks -> Scene -> Element -> Element
augmentFilter hooks scene element =
    case element of
        Svg.Element "filter" attrs children ->
            let
                nodeId =
                    attrs
                        |> List.filter (\( k, _ ) -> k == "id")
                        |> List.head
                        |> Maybe.map (\( _, v ) -> String.split "-filter-" v |> List.drop 1 |> String.join "-filter-")
            in
            case nodeId |> Maybe.andThen (\id -> Dict.get id scene.nodes) of
                Just node ->
                    Svg.Element "filter"
                        attrs
                        (List.map
                            (\child ->
                                case child of
                                    Svg.Element "feGaussianBlur" cattrs cchildren ->
                                        Svg.Element "feGaussianBlur" cattrs (cchildren ++ hooks.filterChildren node)

                                    other ->
                                        other
                            )
                            children
                        )

                Nothing ->
                    element

        other ->
            other


renderNode : Render.Options -> Hooks -> Scene -> ResolvedScene -> String -> List Element
renderNode options hooks scene resolved nodeId =
    case ( Dict.get nodeId scene.nodes, Dict.get nodeId resolved.byId ) of
        ( Just node, Just res ) ->
            if node.hidden && not (Scene.trackFor node.id Visible scene /= Nothing) then
                -- statically hidden nodes with no visibility animation are omitted
                []

            else
                let
                    state =
                        nodeStateAt scene resolved.frame node

                    group channel inner =
                        let
                            tAttr =
                                channelTransform channel state.transform
                                    |> Maybe.map (\v -> [ ( "transform", v ) ])
                                    |> Maybe.withDefault []
                        in
                        Svg.el "g" (tAttr ++ hooks.channelAttrs node channel) (hooks.channelChildren node channel ++ inner)

                    content =
                        case node.geometry of
                            Group ->
                                List.concatMap (renderNode options hooks scene resolved) node.childIds

                            ClippingGroup ->
                                [ Svg.el "g"
                                    [ ( "clip-path", "url(#" ++ options.idPrefix ++ "-clip-" ++ node.id ++ ")" ) ]
                                    (List.concatMap (renderNode options hooks scene resolved) (List.drop 1 node.childIds))
                                ]

                            _ ->
                                let
                                    shapeRes =
                                        { res | geometry = state.geometry, fill = state.fill, stroke = stroke }

                                    stroke =
                                        let
                                            s =
                                                node.stroke
                                        in
                                        { s | paint = state.strokePaint, width = state.strokeWidth, dashOffset = state.dashOffset }
                                in
                                Render.shapeElement options shapeRes (Render.paintAttrs options shapeRes ++ hooks.shapeAttrs node)
                                    |> List.map (appendChildren (hooks.shapeChildren node))

                    motionWrap inner =
                        case node.motion of
                            Just _ ->
                                [ group Motion inner ]

                            Nothing ->
                                inner

                    outerAttrs =
                        (if options.includeIds then
                            [ ( "id", options.idPrefix ++ "-node-" ++ node.id ) ]

                         else
                            []
                        )
                            ++ (if state.opacity < 1 then
                                    [ ( "opacity", num state.opacity ) ]

                                else
                                    []
                               )
                            ++ (if state.hidden then
                                    [ ( "visibility", "hidden" ) ]

                                else
                                    []
                               )
                            ++ (if List.isEmpty node.effects then
                                    []

                                else
                                    [ ( "filter", "url(#" ++ options.idPrefix ++ "-filter-" ++ node.id ++ ")" ) ]
                               )
                            ++ [ ( "data-fw-name", node.name ) ]
                            ++ hooks.channelAttrs node Outer
                in
                [ Svg.el "g"
                    outerAttrs
                    (hooks.channelChildren node Outer
                        ++ [ group Translate
                                (motionWrap
                                    [ group PivotIn
                                        [ group Rotate
                                            [ group SkewX
                                                [ group SkewY
                                                    [ group ScaleChannel
                                                        [ group PivotOut content ]
                                                    ]
                                                ]
                                            ]
                                        ]
                                    ]
                                )
                           ]
                    )
                ]

        _ ->
            []


appendChildren : List Element -> Element -> Element
appendChildren extra element =
    case element of
        Svg.Element tag attrs children ->
            Svg.Element tag attrs (children ++ extra)

        other ->
            other


num : Float -> String
num v =
    let
        r =
            toFloat (round (v * 1000)) / 1000
    in
    if isNaN r || isInfinite r then
        "0"

    else if r == toFloat (round r) then
        String.fromInt (round r)

    else
        String.fromFloat r
