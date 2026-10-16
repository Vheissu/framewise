module UI.Icons exposing (icon)

{-| Original line icons, 16×16 grid, 1.5px stroke. Each is a small set of
path commands so the whole set ships inline with no font or image assets.
-}

import Html exposing (Html)
import Html.Attributes
import Svg
import Svg.Attributes as A


icon : String -> Html msg
icon name =
    Svg.svg
        [ A.viewBox "0 0 16 16"
        , A.width "16"
        , A.height "16"
        , A.fill "none"
        , A.stroke "currentColor"
        , A.strokeWidth "1.5"
        , A.strokeLinecap "round"
        , A.strokeLinejoin "round"
        , A.class "icon"
        , Html.Attributes.attribute "aria-hidden" "true"
        ]
        (paths name)


paths : String -> List (Html msg)
paths name =
    case name of
        "select" ->
            [ Svg.path [ A.d "M4 2.5 L12.5 8.5 L8.6 9.2 L6.6 13 Z" ] [] ]

        "direct" ->
            [ Svg.path [ A.d "M4 2.5 L12.5 8.5 L8.6 9.2 L6.6 13 Z" ] [], Svg.circle [ A.cx "12", A.cy "12.5", A.r "1.6", A.fill "currentColor", A.stroke "none" ] [] ]

        "hand" ->
            [ Svg.path [ A.d "M5 8.5 V4 a1 1 0 0 1 2 0 V7.5 M7 7 V3 a1 1 0 0 1 2 0 V7.5 M9 7.5 V3.8 a1 1 0 0 1 2 0 V8 M11 8 a1 1 0 0 1 2 0 V10.5 a4 4 0 0 1 -4 4 H8.5 a4 4 0 0 1 -3.2 -1.6 L3.2 9.8 a1 1 0 0 1 1.6 -1.2 L5 9" ] [] ]

        "zoom" ->
            [ Svg.circle [ A.cx "7", A.cy "7", A.r "4.5" ] [], Svg.path [ A.d "M10.3 10.3 L14 14 M5 7 H9 M7 5 V9" ] [] ]

        "pen" ->
            [ Svg.path [ A.d "M3 13 L5 9 L11 3 L13 5 L7 11 Z M5 9 L7 11" ] [] ]

        "rect" ->
            [ Svg.rect [ A.x "2.5", A.y "3.5", A.width "11", A.height "9", A.rx "0.5" ] [] ]

        "ellipse" ->
            [ Svg.ellipse [ A.cx "8", A.cy "8", A.rx "5.5", A.ry "4.5" ] [] ]

        "line" ->
            [ Svg.path [ A.d "M3 13 L13 3" ] [] ]

        "polygon" ->
            [ Svg.path [ A.d "M8 2.5 L13 6 L11.2 12.5 L4.8 12.5 L3 6 Z" ] [] ]

        "star" ->
            [ Svg.path [ A.d "M8 2.5 L9.6 6.3 L13.5 6.6 L10.5 9.2 L11.4 13 L8 11 L4.6 13 L5.5 9.2 L2.5 6.6 L6.4 6.3 Z" ] [] ]

        "text" ->
            [ Svg.path [ A.d "M3.5 4.5 V3 H12.5 V4.5 M8 3 V13 M6 13 H10" ] [] ]

        "pivot" ->
            [ Svg.circle [ A.cx "8", A.cy "8", A.r "2.5" ] [], Svg.path [ A.d "M8 2 V4.5 M8 11.5 V14 M2 8 H4.5 M11.5 8 H14" ] [] ]

        "motion" ->
            [ Svg.path [ A.d "M2.5 12 C4 5 8 5 9 8 C10 11 13 11 13.5 4" ] [], Svg.circle [ A.cx "13.5", A.cy "4", A.r "1.5", A.fill "currentColor", A.stroke "none" ] [] ]

        "image" ->
            [ Svg.rect [ A.x "2.5", A.y "3", A.width "11", A.height "10", A.rx "1" ] [], Svg.path [ A.d "M3 11.5 L6.5 8 L9 10.5 L10.5 9 L13 11.5" ] [], Svg.circle [ A.cx "10.5", A.cy "6", A.r "1" ] [] ]

        "eye" ->
            [ Svg.path [ A.d "M1.5 8 C3.5 4.5 12.5 4.5 14.5 8 C12.5 11.5 3.5 11.5 1.5 8 Z" ] [], Svg.circle [ A.cx "8", A.cy "8", A.r "2" ] [] ]

        "eye-off" ->
            [ Svg.path [ A.d "M1.5 8 C3.5 4.5 12.5 4.5 14.5 8 C13.7 9.4 12 10.6 10 11.2 M3 13 L13 3" ] [] ]

        "lock" ->
            [ Svg.rect [ A.x "3.5", A.y "7", A.width "9", A.height "7", A.rx "1" ] [], Svg.path [ A.d "M5.5 7 V5 a2.5 2.5 0 0 1 5 0 V7" ] [] ]

        "unlock" ->
            [ Svg.rect [ A.x "3.5", A.y "7", A.width "9", A.height "7", A.rx "1" ] [], Svg.path [ A.d "M5.5 7 V5 a2.5 2.5 0 0 1 4.8 -0.9" ] [] ]

        "chevron-right" ->
            [ Svg.path [ A.d "M6 4 L10 8 L6 12" ] [] ]

        "chevron-down" ->
            [ Svg.path [ A.d "M4 6 L8 10 L12 6" ] [] ]

        "group" ->
            [ Svg.rect [ A.x "2.5", A.y "2.5", A.width "6", A.height "6" ] [], Svg.rect [ A.x "7.5", A.y "7.5", A.width "6", A.height "6" ] [] ]

        "clip" ->
            [ Svg.rect [ A.x "2.5", A.y "2.5", A.width "11", A.height "11", A.rx "1", A.strokeDasharray "2 2" ] [], Svg.circle [ A.cx "8", A.cy "8", A.r "3" ] [] ]

        "path" ->
            [ Svg.path [ A.d "M3 12 C5 4 11 12 13 4" ] [], Svg.circle [ A.cx "3", A.cy "12", A.r "1.2", A.fill "currentColor", A.stroke "none" ] [], Svg.circle [ A.cx "13", A.cy "4", A.r "1.2", A.fill "currentColor", A.stroke "none" ] [] ]

        "play" ->
            [ Svg.path [ A.d "M5 3 L12.5 8 L5 13 Z", A.fill "currentColor" ] [] ]

        "pause" ->
            [ Svg.path [ A.d "M5 3 V13 M11 3 V13", A.strokeWidth "2.2" ] [] ]

        "stop" ->
            [ Svg.rect [ A.x "4", A.y "4", A.width "8", A.height "8", A.fill "currentColor" ] [] ]

        "skip-start" ->
            [ Svg.path [ A.d "M4 3 V13 M12 3.5 L6 8 L12 12.5 Z", A.fill "currentColor" ] [] ]

        "skip-end" ->
            [ Svg.path [ A.d "M12 3 V13 M4 3.5 L10 8 L4 12.5 Z", A.fill "currentColor" ] [] ]

        "step-back" ->
            [ Svg.path [ A.d "M10 4 L6 8 L10 12 M5 4 V12" ] [] ]

        "step-forward" ->
            [ Svg.path [ A.d "M6 4 L10 8 L6 12 M11 4 V12" ] [] ]

        "key-prev" ->
            [ Svg.path [ A.d "M9 4 L5 8 L9 12 M11 5.5 L13.5 8 L11 10.5 L8.5 8 Z", A.fill "currentColor" ] [] ]

        "key-next" ->
            [ Svg.path [ A.d "M7 4 L11 8 L7 12 M5 5.5 L7.5 8 L5 10.5 L2.5 8 Z", A.fill "currentColor" ] [] ]

        "loop" ->
            [ Svg.path [ A.d "M3 7 V6 a2 2 0 0 1 2 -2 H12 M11 2.5 L13 4 L11 5.5 M13 9 V10 a2 2 0 0 1 -2 2 H4 M5 13.5 L3 12 L5 10.5" ] [] ]

        "pingpong" ->
            [ Svg.path [ A.d "M3 8 H13 M10.5 5.5 L13 8 L10.5 10.5 M5.5 5.5 L3 8 L5.5 10.5" ] [] ]

        "once" ->
            [ Svg.path [ A.d "M3 8 H12 M9.5 5.5 L12 8 L9.5 10.5 M13.5 4 V12" ] [] ]

        "diamond" ->
            [ Svg.path [ A.d "M8 2.5 L13.5 8 L8 13.5 L2.5 8 Z" ] [] ]

        "diamond-filled" ->
            [ Svg.path [ A.d "M8 2.5 L13.5 8 L8 13.5 L2.5 8 Z", A.fill "currentColor" ] [] ]

        "key" ->
            [ Svg.circle [ A.cx "6", A.cy "6", A.r "3.5" ] [], Svg.path [ A.d "M8.5 8.5 L13.5 13.5 M11 13.5 L13.5 11" ] [] ]

        "undo" ->
            [ Svg.path [ A.d "M5 5 H10 a3 3 0 0 1 0 6 H6 M7 2.5 L4.5 5 L7 7.5" ] [] ]

        "redo" ->
            [ Svg.path [ A.d "M11 5 H6 a3 3 0 0 0 0 6 H10 M9 2.5 L11.5 5 L9 7.5" ] [] ]

        "plus" ->
            [ Svg.path [ A.d "M8 3 V13 M3 8 H13" ] [] ]

        "minus" ->
            [ Svg.path [ A.d "M3 8 H13" ] [] ]

        "close" ->
            [ Svg.path [ A.d "M4 4 L12 12 M12 4 L4 12" ] [] ]

        "trash" ->
            [ Svg.path [ A.d "M3 4.5 H13 M6 4.5 V3 H10 V4.5 M4.5 4.5 L5.2 13 H10.8 L11.5 4.5 M7 7 V11 M9 7 V11" ] [] ]

        "duplicate" ->
            [ Svg.rect [ A.x "5.5", A.y "5.5", A.width "8", A.height "8", A.rx "1" ] [], Svg.path [ A.d "M3 10.5 V3.5 a1 1 0 0 1 1 -1 H10.5" ] [] ]

        "export" ->
            [ Svg.path [ A.d "M8 10 V2.5 M5 5.5 L8 2.5 L11 5.5 M3 9.5 V12.5 a1 1 0 0 0 1 1 H12 a1 1 0 0 0 1 -1 V9.5" ] [] ]

        "import" ->
            [ Svg.path [ A.d "M8 2.5 V10 M5 7 L8 10 L11 7 M3 9.5 V12.5 a1 1 0 0 0 1 1 H12 a1 1 0 0 0 1 -1 V9.5" ] [] ]

        "save" ->
            [ Svg.path [ A.d "M3 3 H11 L13 5 V13 H3 Z M5 3 V7 H10 V3 M5.5 13 V10 H10.5 V13" ] [] ]

        "folder" ->
            [ Svg.path [ A.d "M2.5 4.5 a1 1 0 0 1 1 -1 H6.5 L8 5 H12.5 a1 1 0 0 1 1 1 V12 a1 1 0 0 1 -1 1 H3.5 a1 1 0 0 1 -1 -1 Z" ] [] ]

        "file" ->
            [ Svg.path [ A.d "M4 2.5 H9.5 L12.5 5.5 V13.5 H4 Z M9.5 2.5 V5.5 H12.5" ] [] ]

        "settings" ->
            [ Svg.circle [ A.cx "8", A.cy "8", A.r "2" ] [], Svg.path [ A.d "M8 2 V3.5 M8 12.5 V14 M2 8 H3.5 M12.5 8 H14 M3.8 3.8 L4.9 4.9 M11.1 11.1 L12.2 12.2 M3.8 12.2 L4.9 11.1 M11.1 4.9 L12.2 3.8" ] [] ]

        "search" ->
            [ Svg.circle [ A.cx "7", A.cy "7", A.r "4.5" ] [], Svg.path [ A.d "M10.3 10.3 L14 14" ] [] ]

        "warning" ->
            [ Svg.path [ A.d "M8 2.5 L14 13 H2 Z M8 6.5 V9.5 M8 11.5 V11.6" ] [] ]

        "info" ->
            [ Svg.circle [ A.cx "8", A.cy "8", A.r "6" ] [], Svg.path [ A.d "M8 7.5 V11.5 M8 5 V5.1" ] [] ]

        "check" ->
            [ Svg.path [ A.d "M3 8.5 L6.5 12 L13 4.5" ] [] ]

        "grid" ->
            [ Svg.path [ A.d "M2.5 6 H13.5 M2.5 10 H13.5 M6 2.5 V13.5 M10 2.5 V13.5" ] [] ]

        "magnet" ->
            [ Svg.path [ A.d "M4 3 V8 a4 4 0 0 0 8 0 V3 M4 3 H6.5 V8 a1.5 1.5 0 0 0 3 0 V3 H12" ] [] ]

        "film" ->
            [ Svg.path [ A.d "M2.5 3.5 H13.5 V12.5 H2.5 Z M5 3.5 V12.5 M11 3.5 V12.5 M2.5 6.5 H5 M2.5 9.5 H5 M11 6.5 H13.5 M11 9.5 H13.5" ] [] ]

        "layers" ->
            [ Svg.path [ A.d "M8 2.5 L14 5.5 L8 8.5 L2 5.5 Z M3 8.5 L8 11 L13 8.5 M3 11.2 L8 13.7 L13 11.2" ] [] ]

        "scenes" ->
            [ Svg.rect [ A.x "2.5", A.y "4", A.width "8", A.height "6.5", A.rx "0.5" ] [], Svg.path [ A.d "M5 12.5 H13.5 V6" ] [] ]

        "assets" ->
            [ Svg.rect [ A.x "2.5", A.y "2.5", A.width "4.5", A.height "4.5" ] [], Svg.rect [ A.x "9", A.y "2.5", A.width "4.5", A.height "4.5" ] [], Svg.rect [ A.x "2.5", A.y "9", A.width "4.5", A.height "4.5" ] [], Svg.rect [ A.x "9", A.y "9", A.width "4.5", A.height "4.5" ] [] ]

        "fullscreen" ->
            [ Svg.path [ A.d "M3 6 V3 H6 M10 3 H13 V6 M13 10 V13 H10 M6 13 H3 V10" ] [] ]

        "fit" ->
            [ Svg.rect [ A.x "2.5", A.y "2.5", A.width "11", A.height "11", A.rx "1" ] [], Svg.rect [ A.x "5.5", A.y "5.5", A.width "5", A.height "5" ] [] ]

        "arrow-up" ->
            [ Svg.path [ A.d "M8 13 V3 M4 7 L8 3 L12 7" ] [] ]

        "arrow-down" ->
            [ Svg.path [ A.d "M8 3 V13 M4 9 L8 13 L12 9" ] [] ]

        "arrow-left" ->
            [ Svg.path [ A.d "M13 8 H3 M7 4 L3 8 L7 12" ] [] ]

        "command" ->
            [ Svg.path [ A.d "M6 6 H10 V10 H6 Z M6 6 V4.5 a1.5 1.5 0 1 0 -1.5 1.5 Z M10 6 V4.5 a1.5 1.5 0 1 1 1.5 1.5 Z M10 10 V11.5 a1.5 1.5 0 1 0 1.5 -1.5 Z M6 10 V11.5 a1.5 1.5 0 1 1 -1.5 -1.5 Z" ] [] ]

        "onion" ->
            [ Svg.circle [ A.cx "6", A.cy "8", A.r "4", A.opacity "0.5" ] [], Svg.circle [ A.cx "10", A.cy "8", A.r "4" ] [] ]

        "logo" ->
            [ Svg.rect [ A.x "1.75", A.y "5.25", A.width "9", A.height "9", A.rx "1.5", A.opacity "0.55" ] []
            , Svg.rect [ A.x "5.25", A.y "1.75", A.width "9", A.height "9", A.rx "1.5", A.fill "currentColor", A.stroke "none" ] []
            ]

        "reverse" ->
            [ Svg.path [ A.d "M11 3 L3.5 8 L11 13 Z", A.fill "currentColor" ] [], Svg.path [ A.d "M13 3 V13" ] [] ]

        "speed" ->
            [ Svg.path [ A.d "M2.5 11 a5.5 5.5 0 0 1 11 0 M8 11 L10.5 7" ] [], Svg.circle [ A.cx "8", A.cy "11", A.r "1", A.fill "currentColor" ] [] ]

        "ruler" ->
            [ Svg.path [ A.d "M2.5 10.5 L10.5 2.5 L13.5 5.5 L5.5 13.5 Z M5 8 L6.5 9.5 M7 6 L8.5 7.5 M9 4 L10.5 5.5" ] [] ]

        "more" ->
            [ Svg.circle [ A.cx "4", A.cy "8", A.r "1", A.fill "currentColor" ] [], Svg.circle [ A.cx "8", A.cy "8", A.r "1", A.fill "currentColor" ] [], Svg.circle [ A.cx "12", A.cy "8", A.r "1", A.fill "currentColor" ] [] ]

        "link" ->
            [ Svg.path [ A.d "M6.5 9.5 L9.5 6.5 M5 11 L4 12 a2.1 2.1 0 0 1 -3 -3 L3.5 6.5 a2.1 2.1 0 0 1 3 0 M11 5 L12 4 a2.1 2.1 0 0 1 3 3 L12.5 9.5 a2.1 2.1 0 0 1 -3 0" ] [] ]

        "history" ->
            [ Svg.path [ A.d "M3 8 a5 5 0 1 0 1.5 -3.6 M3 3 V5.5 H5.5 M8 5.5 V8 L10 9.5" ] [] ]

        "flip-h" ->
            [ Svg.path [ A.d "M8 2 V14 M3 5 L6 8 L3 11 Z M13 5 L10 8 L13 11 Z" ] [] ]

        "flip-v" ->
            [ Svg.path [ A.d "M2 8 H14 M5 3 L8 6 L11 3 Z M5 13 L8 10 L11 13 Z" ] [] ]

        "move" ->
            [ Svg.path [ A.d "M8 2 V14 M2 8 H14 M6 4 L8 2 L10 4 M6 12 L8 14 L10 12 M4 6 L2 8 L4 10 M12 6 L14 8 L12 10" ] [] ]

        _ ->
            [ Svg.circle [ A.cx "8", A.cy "8", A.r "4" ] [] ]
