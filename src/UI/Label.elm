module UI.Label exposing (color, style)

{-| Layer label colours. Each layer gets a stable colour from its id, shown as
a swatch in the layer list and as the tint of its bar in the timeline, the way
desktop compositors colour-code layers.
-}

import Html
import Html.Attributes as A


palette : List String
palette =
    [ "#7f8fd6", "#c9b956", "#86b5b0", "#d39d74", "#9fb89f", "#cc94ad", "#a8977a", "#c98a8a" ]


color : String -> String
color id =
    let
        hash =
            String.foldl (\c acc -> modBy 1000003 (acc * 31 + Char.toCode c)) 7 id

        index =
            modBy (List.length palette) hash
    in
    palette |> List.drop index |> List.head |> Maybe.withDefault "#7f8fd6"


{-| Sets the label colour as the element's `color`, so CSS can use it through
`currentColor` (Elm's `style` cannot set custom properties).
-}
style : String -> Html.Attribute msg
style id =
    A.style "color" (color id)
