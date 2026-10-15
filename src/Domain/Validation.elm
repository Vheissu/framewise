module Domain.Validation exposing
    ( Issue
    , Severity(..)
    , validateDocument
    , validateScene
    )

{-| Structural validation run on open, before save and before export. Issues
carry object ids so the UI can link to the affected item.
-}

import Dict
import Domain.Document exposing (Document)
import Domain.Fps as Fps
import Domain.Keyframe as Keyframe
import Domain.Limits as Limits
import Domain.Node as Node exposing (NodeGeometry(..))
import Domain.Paint as Paint
import Domain.Path as Path
import Domain.Property as Property
import Domain.Scene as Scene exposing (Scene)
import Domain.Transform as Transform


type Severity
    = Error
    | Warning


type alias Issue =
    { severity : Severity
    , objectId : String
    , message : String
    }


validateDocument : Document -> List Issue
validateDocument doc =
    let
        orderIssues =
            List.filterMap
                (\id ->
                    if Dict.member id doc.scenes then
                        Nothing

                    else
                        Just (Issue Error id "Scene order references a missing scene")
                )
                doc.sceneOrder

        missingFromOrder =
            Dict.keys doc.scenes
                |> List.filter (\id -> not (List.member id doc.sceneOrder))
                |> List.map (\id -> Issue Error id "Scene is not listed in scene order")

        empty =
            if List.isEmpty doc.sceneOrder then
                [ Issue Error doc.id "Document has no scenes" ]

            else
                []
    in
    empty ++ orderIssues ++ missingFromOrder ++ List.concatMap validateScene (Dict.values doc.scenes)


validateScene : Scene -> List Issue
validateScene scene =
    sceneIssues scene ++ treeIssues scene ++ nodeIssues scene ++ trackIssues scene


sceneIssues : Scene -> List Issue
sceneIssues scene =
    List.filterMap identity
        [ check (scene.width > 0 && scene.height > 0) Error scene.id "Scene dimensions must be positive"
        , check (scene.width <= Limits.maxCanvasDimension && scene.height <= Limits.maxCanvasDimension) Error scene.id "Scene exceeds the maximum canvas dimension"
        , check (Fps.isValid scene.fps) Error scene.id "Frame rate must be a positive rational up to 240 fps"
        , check (scene.durationFrames >= 1) Error scene.id "Scene duration must be at least one frame"
        , check (scene.durationFrames <= Limits.maxDurationFrames) Error scene.id "Scene duration exceeds the limit"
        , check (Dict.size scene.nodes <= Limits.maxNodesPerScene) Error scene.id "Scene has too many nodes"
        , check (Dict.size scene.tracks <= Limits.maxTracksPerScene) Error scene.id "Scene has too many animation tracks"
        ]


treeIssues : Scene -> List Issue
treeIssues scene =
    let
        rootsMissing =
            scene.rootNodeIds
                |> List.filter (\id -> not (Dict.member id scene.nodes))
                |> List.map (\id -> Issue Error id "Root node reference is missing")

        reciprocal =
            Dict.values scene.nodes
                |> List.concatMap
                    (\n ->
                        let
                            parentOk =
                                case n.parentId of
                                    Nothing ->
                                        List.member n.id scene.rootNodeIds

                                    Just pid ->
                                        Dict.get pid scene.nodes
                                            |> Maybe.map (\p -> List.member n.id p.childIds)
                                            |> Maybe.withDefault False

                            childrenOk =
                                List.all
                                    (\cid ->
                                        Dict.get cid scene.nodes
                                            |> Maybe.map (\c -> c.parentId == Just n.id)
                                            |> Maybe.withDefault False
                                    )
                                    n.childIds
                        in
                        List.filterMap identity
                            [ check parentOk Error n.id "Node parent link is not reciprocal"
                            , check childrenOk Error n.id "Node child links are not reciprocal"
                            ]
                    )

        cycles =
            Dict.keys scene.nodes
                |> List.filterMap
                    (\id ->
                        if List.member id (Scene.ancestors id scene) then
                            Just (Issue Error id "Node hierarchy contains a cycle")

                        else
                            Nothing
                    )

        depth =
            Dict.keys scene.nodes
                |> List.filterMap
                    (\id ->
                        if List.length (Scene.ancestors id scene) > Limits.maxNestingDepth then
                            Just (Issue Error id "Node nesting is too deep")

                        else
                            Nothing
                    )
    in
    rootsMissing ++ reciprocal ++ cycles ++ depth


nodeIssues : Scene -> List Issue
nodeIssues scene =
    Dict.values scene.nodes
        |> List.concatMap
            (\n ->
                List.filterMap identity
                    [ check (Transform.isFinite n.transform) Error n.id "Transform contains a non-finite value"
                    , check (n.opacity >= 0 && n.opacity <= 1) Error n.id "Opacity must be between 0 and 1"
                    , check (Paint.isValid n.fill) Error n.id "Fill paint is invalid"
                    , check (Paint.isValid n.stroke.paint) Error n.id "Stroke paint is invalid"
                    , check (n.stroke.width >= 0) Error n.id "Stroke width must be non-negative"
                    , check (List.all (\d -> d >= 0) n.stroke.dashArray) Error n.id "Dash values must be non-negative"
                    , geometryCheck n
                    , check
                        (case n.motion of
                            Just m ->
                                Dict.member m.pathId scene.motionPaths

                            Nothing ->
                                True
                        )
                        Error
                        n.id
                        "Motion path reference is missing"
                    , check (Node.isContainer n || List.isEmpty n.childIds) Error n.id "Only groups may have children"
                    ]
            )


geometryCheck : Node.Node -> Maybe Issue
geometryCheck n =
    case n.geometry of
        Rectangle r ->
            check (r.size.x >= 0 && r.size.y >= 0 && r.cornerRadius >= 0) Error n.id "Rectangle dimensions must be non-negative"

        Ellipse e ->
            check (e.radii.x >= 0 && e.radii.y >= 0) Error n.id "Ellipse radii must be non-negative"

        Polygon p ->
            check (p.sides >= 3 && p.radius >= 0) Error n.id "Polygon needs at least 3 sides"

        Path p ->
            if not (Path.isFinite p) then
                Just (Issue Error n.id "Path contains non-finite coordinates")

            else
                check (Path.segmentCount p <= Limits.maxPathSegments) Error n.id "Path has too many segments"

        Text t ->
            check (t.fontSize > 0) Error n.id "Font size must be positive"

        RasterImage i ->
            check (i.size.x >= 0 && i.size.y >= 0) Error n.id "Image size must be non-negative"

        _ ->
            Nothing


trackIssues : Scene -> List Issue
trackIssues scene =
    Dict.values scene.tracks
        |> List.concatMap
            (\t ->
                let
                    nodeExists =
                        Dict.get t.target.nodeId scene.nodes

                    typeOk =
                        List.all (\k -> Property.valueTypeMatches t.target.property k.value) t.keyframes

                    supported =
                        nodeExists
                            |> Maybe.map (\n -> Node.supportsProperty n t.target.property)
                            |> Maybe.withDefault True

                    duplicates =
                        let
                            fs =
                                Keyframe.frames t
                        in
                        List.length fs /= List.length (dedupe fs)

                    outOfRange =
                        List.any (\k -> k.frame > scene.durationFrames) t.keyframes
                in
                List.filterMap identity
                    [ check (nodeExists /= Nothing) Error t.id "Track targets a missing node"
                    , check typeOk Error t.id ("Track " ++ Property.pathToCode t.target.property ++ " has a keyframe of the wrong value type")
                    , check supported Warning t.id "Track targets a property the node does not support"
                    , check (Keyframe.isSorted t) Error t.id "Keyframes are not sorted"
                    , check (not duplicates) Error t.id "Track has two keyframes at the same frame"
                    , check (List.all (\k -> k.frame >= 0) t.keyframes) Error t.id "Keyframe frame must be non-negative"
                    , check (not outOfRange) Warning t.id "Track has keyframes beyond the scene duration"
                    , check (List.length t.keyframes <= Limits.maxKeyframesPerTrack) Error t.id "Track has too many keyframes"
                    ]
            )


dedupe : List comparable -> List comparable
dedupe =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                x :: acc
        )
        []


check : Bool -> Severity -> String -> String -> Maybe Issue
check ok severity id message =
    if ok then
        Nothing

    else
        Just (Issue severity id message)
