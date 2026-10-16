module Export.Capability exposing
    ( Item
    , Report
    , Status(..)
    , classify
    , report
    , statusLabel
    )

{-| Classifies every animation track of a scene against an export target.
The result drives the Export Studio compatibility panel and the block/bake
decision before a file is produced.
-}

import Dict
import Domain.Keyframe exposing (Track)
import Domain.Node exposing (NodeGeometry(..))
import Domain.Path as Path
import Domain.Property as Property exposing (PropertyPath(..), PropertyValue(..))
import Domain.Scene exposing (PlaybackMode(..), Scene)
import Export.Format exposing (Format(..))
import Export.Spans as Spans
import Export.Timing as Timing


type Status
    = Exact
    | Baked String
    | Unsupported String


type alias Item =
    { nodeId : String
    , nodeName : String
    , property : Maybe PropertyPath
    , status : Status
    }


type alias Report =
    { items : List Item
    , exactCount : Int
    , bakedCount : Int
    , unsupportedCount : Int
    }


statusLabel : Status -> String
statusLabel s =
    case s of
        Exact ->
            "Exact"

        Baked _ ->
            "Baked"

        Unsupported _ ->
            "Unsupported"


report : Format -> Scene -> Report
report format unbaked =
    let
        scene =
            Spans.bake unbaked

        trackItems =
            Dict.values scene.tracks
                |> List.filter (\t -> t.enabled && not (List.isEmpty t.keyframes))
                |> List.map (\t -> classify format scene t)

        sceneItems =
            sceneLevel format scene

        items =
            sceneItems ++ trackItems

        count pred =
            List.length (List.filter (\i -> pred i.status) items)
    in
    { items = items
    , exactCount = count (\s -> s == Exact)
    , bakedCount = count isBaked
    , unsupportedCount = count isUnsupported
    }


isBaked : Status -> Bool
isBaked s =
    case s of
        Baked _ ->
            True

        _ ->
            False


isUnsupported : Status -> Bool
isUnsupported s =
    case s of
        Unsupported _ ->
            True

        _ ->
            False


sceneLevel : Format -> Scene -> List Item
sceneLevel format scene =
    let
        hasAnimation =
            Dict.values scene.tracks |> List.any (\t -> t.enabled && not (List.isEmpty t.keyframes))

        pingPong =
            case ( format, scene.playbackMode ) of
                ( AnimatedSvg, PingPong ) ->
                    [ Item scene.id scene.name Nothing (Baked "Ping-pong playback is baked into a mirrored cycle of twice the duration") ]

                ( SvgCss, PingPong ) ->
                    [ Item scene.id scene.name Nothing Exact ]

                _ ->
                    []

        textNodes =
            Dict.values scene.nodes
                |> List.filterMap
                    (\n ->
                        case n.geometry of
                            Text _ ->
                                if format == HtmlPlayer || format == StaticSvg || format == AnimatedSvg || format == SvgCss then
                                    Just (Item n.id n.name Nothing (Baked "Text depends on fonts installed on the viewing device; layout may differ"))

                                else
                                    Nothing

                            _ ->
                                Nothing
                    )

        missingImages =
            Dict.values scene.nodes
                |> List.filterMap
                    (\n ->
                        case n.geometry of
                            RasterImage _ ->
                                Just (Item n.id n.name Nothing (Baked "Raster image is embedded as a data URI, which increases file size"))

                            _ ->
                                Nothing
                    )
    in
    (if hasAnimation && not (Export.Format.isAnimated format) then
        [ Item scene.id scene.name Nothing (Baked "Animation is flattened to the selected frame") ]

     else
        []
    )
        ++ pingPong
        ++ textNodes
        ++ (if Export.Format.isRaster format then
                []

            else
                missingImages
           )


classify : Format -> Scene -> Track -> Item
classify format scene track =
    let
        node =
            Dict.get track.target.nodeId scene.nodes

        name =
            Maybe.map .name node |> Maybe.withDefault track.target.nodeId

        clipChild =
            case node |> Maybe.andThen .parentId |> Maybe.andThen (\pid -> Dict.get pid scene.nodes) of
                Just parent ->
                    parent.geometry == ClippingGroup && List.head parent.childIds == Just track.target.nodeId

                Nothing ->
                    False

        easingStatus requireUnitY =
            if Property.isDiscrete track.target.property then
                -- discrete values step at their keys in SMIL and CSS alike, so
                -- the easing never changes the output
                Exact

            else
                case Timing.planTrack requireUnitY scene.durationFrames track of
                    Timing.Native _ ->
                        Exact

                    Timing.BakedPlan _ reason ->
                        Baked reason

        pathCompatible =
            case List.map .value track.keyframes of
                (PathValue first) :: rest ->
                    List.all
                        (\v ->
                            case v of
                                PathValue p ->
                                    Path.isCompatible first p

                                _ ->
                                    False
                        )
                        rest

                _ ->
                    False

        status =
            case format of
                StaticSvg ->
                    Exact

                PngStill ->
                    Exact

                PngSequence ->
                    Exact

                HtmlPlayer ->
                    if track.target.property == PathGeometryProp && not pathCompatible then
                        Unsupported "Path keyframes have different structures; use Prepare Morph or hold between them"

                    else
                        Exact

                AnimatedSvg ->
                    if clipChild then
                        Unsupported "Animating a clipping shape is not exported; the clip is static"

                    else
                        case track.target.property of
                            TextContent ->
                                Unsupported "SMIL cannot change text content; use the HTML player"

                            PathGeometryProp ->
                                if pathCompatible then
                                    easingStatus True

                                else
                                    Unsupported "Path keyframes have different structures"

                            _ ->
                                easingStatus True

                SvgCss ->
                    if clipChild then
                        Unsupported "Animating a clipping shape is not exported; the clip is static"

                    else
                        case track.target.property of
                            TextContent ->
                                Unsupported "CSS cannot change text content; use the HTML player"

                            PathGeometryProp ->
                                Unsupported "CSS path morphing is not consistently supported across browsers; use SMIL or the HTML player"

                            MotionProgress ->
                                Unsupported "CSS motion paths are not exported; use SMIL or the HTML player"

                            RectSize ->
                                Unsupported "CSS cannot animate SVG geometry attributes consistently; use SMIL or the HTML player"

                            RectCornerRadius ->
                                Unsupported "CSS cannot animate SVG geometry attributes consistently; use SMIL or the HTML player"

                            EllipseRadii ->
                                Unsupported "CSS cannot animate SVG geometry attributes consistently; use SMIL or the HTML player"

                            FontSize ->
                                Unsupported "Font size animation is not exported to CSS; use SMIL or the HTML player"

                            BlurRadius ->
                                Unsupported "Filter animation is not exported to CSS; use SMIL or the HTML player"

                            Visible ->
                                easingStatus False

                            _ ->
                                easingStatus False

                Gif ->
                    Unsupported "Format unavailable"

                Apng ->
                    Unsupported "Format unavailable"

                WebM ->
                    Unsupported "Format unavailable"

                Mp4 ->
                    Unsupported "Format unavailable"

                Lottie ->
                    Unsupported "Format unavailable"
    in
    { nodeId = track.target.nodeId
    , nodeName = name
    , property = Just track.target.property
    , status = status
    }
