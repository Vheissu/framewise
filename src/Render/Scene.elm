module Render.Scene exposing
    ( Options
    , defaultOptions
    , nodeElement
    , paintAttrs
    , renderDefs
    , renderScene
    , renderSceneBody
    , shapeElement
    )

{-| Render a resolved scene to the shared SVG element tree. Editor overlays
are never part of this output.
-}

import Dict exposing (Dict)
import Domain.Color as Color
import Domain.Evaluate exposing (ResolvedNode, ResolvedScene)
import Domain.Matrix as Matrix
import Domain.Node as Node exposing (Effect(..), NodeGeometry(..))
import Domain.Paint as Paint exposing (Paint(..))
import Domain.Path as Path
import Domain.Scene exposing (Background(..))
import Domain.Vec2 exposing (Vec2)
import Render.SvgDoc as Svg exposing (Element)
import Shared.Ids exposing (AssetId, NodeId)


type alias Options =
    { idPrefix : String
    , assetUrls : Dict AssetId String
    , includeBackground : Bool
    , includeIds : Bool
    , title : Maybe String
    , description : Maybe String
    , standalone : Bool
    }


defaultOptions : Options
defaultOptions =
    { idPrefix = "fw"
    , assetUrls = Dict.empty
    , includeBackground = True
    , includeIds = True
    , title = Nothing
    , description = Nothing
    , standalone = False
    }


renderScene : Options -> ResolvedScene -> Element
renderScene options scene =
    let
        rootAttrs =
            [ ( "xmlns", "http://www.w3.org/2000/svg" )
            , ( "width", num scene.width )
            , ( "height", num scene.height )
            , ( "viewBox", "0 0 " ++ num scene.width ++ " " ++ num scene.height )
            ]
                ++ (if options.standalone then
                        [ ( "xmlns:xlink", "http://www.w3.org/1999/xlink" ) ]

                    else
                        []
                   )

        meta =
            List.filterMap identity
                [ Maybe.map (\t -> Svg.el "title" [] [ Svg.text t ]) options.title
                , Maybe.map (\d -> Svg.el "desc" [] [ Svg.text d ]) options.description
                ]
    in
    Svg.el "svg" rootAttrs (meta ++ renderSceneBody options scene)


{-| Defs plus background plus artwork, without the `<svg>` root.
-}
renderSceneBody : Options -> ResolvedScene -> List Element
renderSceneBody options scene =
    let
        defs =
            renderDefs options scene

        bg =
            case ( options.includeBackground, scene.background ) of
                ( True, SolidBackground c ) ->
                    [ Svg.el "rect"
                        [ ( "width", num scene.width )
                        , ( "height", num scene.height )
                        , ( "fill", Color.toHex c )
                        , ( "data-fw-background", "true" )
                        ]
                        []
                    ]

                _ ->
                    []

        roots =
            scene.nodes |> List.filter (\n -> n.parentId == Nothing)
    in
    (if List.isEmpty defs then
        []

     else
        [ Svg.el "defs" [] defs ]
    )
        ++ bg
        ++ List.concatMap (nodeElement options scene) roots


renderDefs : Options -> ResolvedScene -> List Element
renderDefs options scene =
    List.concatMap (nodeDefs options scene) scene.nodes


nodeDefs : Options -> ResolvedScene -> ResolvedNode -> List Element
nodeDefs options scene node =
    let
        fillDef =
            gradientDef (gradientId options node.id "fill") node.fill

        strokeDef =
            gradientDef (gradientId options node.id "stroke") node.stroke.paint

        filterDef =
            if List.isEmpty node.effects then
                []

            else
                [ filterElement (filterId options node.id) node.effects ]

        clipDef =
            if node.isClipGroup then
                case List.head node.childIds |> Maybe.andThen (\cid -> Dict.get cid scene.byId) of
                    Just clipChild ->
                        -- clipPath only accepts shapes, text and use as children, so the
                        -- clip shape's transform goes on the clipPath itself; a wrapping
                        -- <g> would be ignored and clip everything away.
                        [ Svg.el "clipPath"
                            [ ( "id", clipId options node.id ), ( "transform", Matrix.toSvgTransform clipChild.localMatrix ) ]
                            (shapeElement options clipChild [])
                        ]

                    Nothing ->
                        []

            else
                []
    in
    fillDef ++ strokeDef ++ filterDef ++ clipDef


gradientId : Options -> NodeId -> String -> String
gradientId options nodeId kind =
    options.idPrefix ++ "-grad-" ++ kind ++ "-" ++ nodeId


filterId : Options -> NodeId -> String
filterId options nodeId =
    options.idPrefix ++ "-filter-" ++ nodeId


clipId : Options -> NodeId -> String
clipId options nodeId =
    options.idPrefix ++ "-clip-" ++ nodeId


gradientDef : String -> Paint -> List Element
gradientDef id paint =
    case paint of
        GradientPaint g ->
            let
                stops =
                    List.map
                        (\s ->
                            Svg.el "stop"
                                [ ( "offset", num (s.offset * 100) ++ "%" )
                                , ( "stop-color", Color.toHex { r = s.color.r, g = s.color.g, b = s.color.b, a = 1 } )
                                , ( "stop-opacity", num s.color.a )
                                ]
                                []
                        )
                        g.stops
            in
            case g.kind of
                Paint.LinearGradient l ->
                    [ Svg.el "linearGradient"
                        [ ( "id", id )
                        , ( "gradientUnits", "userSpaceOnUse" )
                        , ( "x1", num l.start.x )
                        , ( "y1", num l.start.y )
                        , ( "x2", num l.end.x )
                        , ( "y2", num l.end.y )
                        ]
                        stops
                    ]

                Paint.RadialGradient r ->
                    [ Svg.el "radialGradient"
                        [ ( "id", id )
                        , ( "gradientUnits", "userSpaceOnUse" )
                        , ( "cx", num r.center.x )
                        , ( "cy", num r.center.y )
                        , ( "r", num r.radius )
                        ]
                        stops
                    ]

        _ ->
            []


filterElement : String -> List Effect -> Element
filterElement id effects =
    let
        primitives =
            List.concatMap
                (\e ->
                    case e of
                        Blur r ->
                            [ Svg.el "feGaussianBlur" [ ( "stdDeviation", num r ) ] [] ]

                        DropShadow d ->
                            [ Svg.el "feDropShadow"
                                [ ( "dx", num d.offset.x )
                                , ( "dy", num d.offset.y )
                                , ( "stdDeviation", num d.blur )
                                , ( "flood-color", Color.toHex { r = d.color.r, g = d.color.g, b = d.color.b, a = 1 } )
                                , ( "flood-opacity", num d.color.a )
                                ]
                                []
                            ]
                )
                effects
    in
    Svg.el "filter"
        [ ( "id", id )
        , ( "x", "-50%" )
        , ( "y", "-50%" )
        , ( "width", "200%" )
        , ( "height", "200%" )
        , ( "color-interpolation-filters", "sRGB" )
        ]
        primitives


{-| Render a node and its descendants as a `<g>` wrapper carrying the local
transform, opacity and filters, with the shape inside.
-}
nodeElement : Options -> ResolvedScene -> ResolvedNode -> List Element
nodeElement options scene node =
    if node.inheritedHidden then
        []

    else
        let
            idAttrs =
                if options.includeIds then
                    [ ( "id", options.idPrefix ++ "-node-" ++ node.id ) ]

                else
                    []

            wrapperAttrs =
                idAttrs
                    ++ [ ( "transform", Matrix.toSvgTransform node.localMatrix ) ]
                    ++ (if node.opacity < 1 then
                            [ ( "opacity", num node.opacity ) ]

                        else
                            []
                       )
                    ++ (if List.isEmpty node.effects then
                            []

                        else
                            [ ( "filter", "url(#" ++ filterId options node.id ++ ")" ) ]
                       )
                    ++ [ ( "data-fw-name", node.name ) ]

            children =
                node.childIds
                    |> List.filterMap (\cid -> Dict.get cid scene.byId)

            content =
                case node.geometry of
                    Group ->
                        List.concatMap (nodeElement options scene) children

                    ClippingGroup ->
                        let
                            clipped =
                                List.drop 1 children
                        in
                        [ Svg.el "g"
                            [ ( "clip-path", "url(#" ++ clipId options node.id ++ ")" ) ]
                            (List.concatMap (nodeElement options scene) clipped)
                        ]

                    _ ->
                        shapeElement options node (paintAttrs options node)
        in
        [ Svg.el "g" wrapperAttrs content ]


paintAttrs : Options -> ResolvedNode -> List ( String, String )
paintAttrs options node =
    let
        fillAttr =
            case node.fill of
                NoPaint ->
                    [ ( "fill", "none" ) ]

                Solid c ->
                    ( "fill", Color.toHex { r = c.r, g = c.g, b = c.b, a = 1 } )
                        :: (if c.a < 1 then
                                [ ( "fill-opacity", num c.a ) ]

                            else
                                []
                           )

                GradientPaint _ ->
                    [ ( "fill", "url(#" ++ gradientId options node.id "fill" ++ ")" ) ]

        stroke =
            node.stroke

        strokeAttr =
            case stroke.paint of
                NoPaint ->
                    []

                Solid c ->
                    [ ( "stroke", Color.toHex { r = c.r, g = c.g, b = c.b, a = 1 } ) ]
                        ++ (if c.a < 1 then
                                [ ( "stroke-opacity", num c.a ) ]

                            else
                                []
                           )
                        ++ strokeStyleAttrs

                GradientPaint _ ->
                    ( "stroke", "url(#" ++ gradientId options node.id "stroke" ++ ")" ) :: strokeStyleAttrs

        strokeStyleAttrs =
            [ ( "stroke-width", num stroke.width ) ]
                ++ (if stroke.cap /= Paint.CapButt then
                        [ ( "stroke-linecap", Paint.capToCode stroke.cap ) ]

                    else
                        []
                   )
                ++ (if stroke.join /= Paint.JoinMiter then
                        [ ( "stroke-linejoin", Paint.joinToCode stroke.join ) ]

                    else
                        []
                   )
                ++ (if List.isEmpty stroke.dashArray then
                        []

                    else
                        [ ( "stroke-dasharray", String.join " " (List.map num stroke.dashArray) ) ]
                            ++ (if stroke.dashOffset /= 0 then
                                    [ ( "stroke-dashoffset", num stroke.dashOffset ) ]

                                else
                                    []
                               )
                   )
    in
    fillAttr ++ strokeAttr


{-| The bare shape element(s) for a node's geometry in local coordinates.
-}
shapeElement : Options -> ResolvedNode -> List ( String, String ) -> List Element
shapeElement options node extraAttrs =
    case node.geometry of
        Rectangle r ->
            [ Svg.el "rect"
                ([ ( "width", num r.size.x ), ( "height", num r.size.y ) ]
                    ++ (if r.cornerRadius > 0 then
                            [ ( "rx", num r.cornerRadius ) ]

                        else
                            []
                       )
                    ++ extraAttrs
                )
                []
            ]

        Ellipse e ->
            [ Svg.el "ellipse" ([ ( "rx", num e.radii.x ), ( "ry", num e.radii.y ) ] ++ extraAttrs) [] ]

        Line l ->
            [ Svg.el "line"
                ([ ( "x1", num l.start.x ), ( "y1", num l.start.y ), ( "x2", num l.end.x ), ( "y2", num l.end.y ) ] ++ extraAttrs)
                []
            ]

        Polygon p ->
            [ Svg.el "polygon"
                (( "points", String.join " " (List.map (\pt -> num pt.x ++ "," ++ num pt.y) (Node.polygonPoints p)) ) :: extraAttrs)
                []
            ]

        Path p ->
            [ Svg.el "path" (( "d", Path.serialize p ) :: extraAttrs) [] ]

        Text t ->
            [ Svg.el "text"
                ([ ( "font-family", t.fontFamily )
                 , ( "font-size", num t.fontSize )
                 , ( "font-weight", String.fromInt t.fontWeight )
                 , ( "text-anchor", Node.alignToCode t.align )
                 ]
                    ++ (if t.italic then
                            [ ( "font-style", "italic" ) ]

                        else
                            []
                       )
                    ++ (if t.letterSpacing /= 0 then
                            [ ( "letter-spacing", num t.letterSpacing ) ]

                        else
                            []
                       )
                    ++ extraAttrs
                )
                [ Svg.text t.content ]
            ]

        RasterImage i ->
            case Dict.get i.assetId options.assetUrls of
                Just url ->
                    [ Svg.el "image"
                        [ ( "href", url )
                        , ( "width", num i.size.x )
                        , ( "height", num i.size.y )
                        , ( "preserveAspectRatio", "none" )
                        ]
                        []
                    ]

                Nothing ->
                    [ Svg.el "rect"
                        [ ( "width", num i.size.x )
                        , ( "height", num i.size.y )
                        , ( "fill", "#8884" )
                        , ( "stroke", "#f55" )
                        , ( "stroke-dasharray", "4 4" )
                        , ( "data-fw-missing-asset", i.assetId )
                        ]
                        []
                    ]

        Group ->
            []

        ClippingGroup ->
            []


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
