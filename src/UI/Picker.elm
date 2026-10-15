module UI.Picker exposing (swatchButton, view)

{-| The Framewise colour picker: a popover with hue/saturation/lightness
sliders, alpha, hex entry and recent swatches. Confirm keeps the colour,
Cancel/Escape restores the initial one.
-}

import App.Model exposing (ColorTarget, Model, PickerState)
import App.Msg exposing (Msg(..))
import Domain.Color as Color exposing (Rgba)
import Html exposing (Html, button, div, input, label, span, text)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D


swatchButton : String -> ColorTarget -> Maybe Rgba -> Html Msg
swatchButton labelText target color =
    let
        css =
            Maybe.map Color.toCss color |> Maybe.withDefault "transparent"
    in
    button
        [ A.class "swatch"
        , A.classList [ ( "swatch-none", color == Nothing ) ]
        , A.title labelText
        , A.attribute "aria-label" labelText
        , E.on "click"
            (D.map2 (\x y -> OpenPicker target (Maybe.withDefault Color.black color) x y)
                (D.field "clientX" D.float)
                (D.field "clientY" D.float)
            )
        ]
        [ span [ A.class "swatch-fill", A.style "background" css ] [] ]


view : Model -> PickerState -> Html Msg
view model state =
    let
        c =
            state.current

        hsl =
            Color.toHsl c

        left =
            min (state.anchor.x - 120) (model.editor.canvasRect.left + model.editor.canvasRect.width + model.editor.rightWidth - 280)

        top =
            min (state.anchor.y + 12) 480

        slider labelText minV maxV stepV value toColor =
            label [ A.class "picker-slider" ]
                [ span [] [ text labelText ]
                , input
                    [ A.type_ "range"
                    , A.min (String.fromFloat minV)
                    , A.max (String.fromFloat maxV)
                    , A.step (String.fromFloat stepV)
                    , A.value (String.fromFloat value)
                    , E.onInput (\s -> PickerChange (toColor (String.toFloat s |> Maybe.withDefault value)))
                    ]
                    []
                , span [ A.class "picker-value" ] [ text (String.fromInt (round value)) ]
                ]
    in
    div
        [ A.class "picker"
        , A.style "left" (String.fromFloat (max 8 left) ++ "px")
        , A.style "top" (String.fromFloat top ++ "px")
        , A.attribute "role" "dialog"
        , A.attribute "aria-label" "Colour picker"
        ]
        [ div [ A.class "picker-preview" ]
            [ div [ A.class "picker-checker" ] [ div [ A.class "picker-current", A.style "background" (Color.toCss c) ] [] ]
            , div [ A.class "picker-hex" ]
                [ input
                    [ A.type_ "text"
                    , A.value state.hexDraft
                    , A.attribute "aria-label" "Hex colour"
                    , A.spellcheck False
                    , E.onInput PickerHex
                    ]
                    []
                , span [ A.class "picker-hint" ]
                    [ text
                        (if c.a < 1 then
                            "#rrggbbaa"

                         else
                            "#rrggbb"
                        )
                    ]
                ]
            ]
        , slider "H" 0 360 1 hsl.h (\v -> Color.fromHsl { hsl | h = v } c.a)
        , slider "S" 0 100 1 (hsl.s * 100) (\v -> Color.fromHsl { hsl | s = v / 100 } c.a)
        , slider "L" 0 100 1 (hsl.l * 100) (\v -> Color.fromHsl { hsl | l = v / 100 } c.a)
        , slider "A" 0 100 1 (c.a * 100) (\v -> { c | a = v / 100 })
        , div [ A.class "picker-rgb" ]
            [ rgbField "R" c.r (\v -> { c | r = v })
            , rgbField "G" c.g (\v -> { c | g = v })
            , rgbField "B" c.b (\v -> { c | b = v })
            ]
        , div [ A.class "picker-swatches" ]
            (List.map
                (\hex ->
                    button
                        [ A.class "picker-swatch"
                        , A.style "background" hex
                        , A.attribute "aria-label" hex
                        , E.onClick (PickerChange (Color.fromHex hex |> Maybe.withDefault c))
                        ]
                        []
                )
                palette
            )
        , div [ A.class "picker-actions" ]
            [ button [ A.class "btn", E.onClick PickerCancel ] [ text "Cancel" ]
            , button [ A.class "btn primary", E.onClick PickerConfirm ] [ text "Done" ]
            ]
        ]


rgbField : String -> Float -> (Float -> Rgba) -> Html Msg
rgbField labelText value toColor =
    label [ A.class "picker-rgb-field" ]
        [ span [] [ text labelText ]
        , input
            [ A.type_ "number"
            , A.min "0"
            , A.max "255"
            , A.value (String.fromInt (round (value * 255)))
            , E.onInput (\s -> PickerChange (toColor (toFloat (clamp 0 255 (String.toInt s |> Maybe.withDefault 0)) / 255)))
            ]
            []
        ]


palette : List String
palette =
    [ "#1f1f23", "#5c5c66", "#a8a8b3", "#f4f1ea", "#e8862d", "#d84a3a", "#c7357a", "#6b4bb8", "#2f6fd6", "#1fa0a8", "#2f9e5b", "#b9b41f" ]
