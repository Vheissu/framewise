module Render.SvgDoc exposing
    ( Element(..)
    , el
    , escape
    , text
    , toHtml
    , toString
    )

{-| A tiny SVG document tree that renders both to the virtual DOM (for the
editor canvas and preview) and to a string (for exports). Using one tree
guarantees exports contain exactly what the editor renders.
-}

import Html exposing (Html)
import Html.Attributes
import Svg
import Svg.Attributes


type Element
    = Element String (List ( String, String )) (List Element)
    | TextNode String


el : String -> List ( String, String ) -> List Element -> Element
el =
    Element


text : String -> Element
text =
    TextNode


toHtml : Element -> Html msg
toHtml element =
    case element of
        TextNode s ->
            Svg.text s

        Element tag attrs children ->
            Svg.node tag (List.map toAttr attrs) (List.map toHtml children)


toAttr : ( String, String ) -> Svg.Attribute msg
toAttr ( name, value ) =
    case name of
        "href" ->
            Svg.Attributes.xlinkHref value

        "class" ->
            Svg.Attributes.class value

        _ ->
            Html.Attributes.attribute name value


toString : Element -> String
toString element =
    case element of
        TextNode s ->
            escape s

        Element tag attrs children ->
            let
                attrString =
                    attrs
                        |> List.map (\( k, v ) -> " " ++ k ++ "=\"" ++ escapeAttr v ++ "\"")
                        |> String.concat
            in
            if List.isEmpty children then
                "<" ++ tag ++ attrString ++ "/>"

            else
                "<" ++ tag ++ attrString ++ ">" ++ String.concat (List.map toString children) ++ "</" ++ tag ++ ">"


escape : String -> String
escape s =
    s
        |> String.replace "&" "&amp;"
        |> String.replace "<" "&lt;"
        |> String.replace ">" "&gt;"


escapeAttr : String -> String
escapeAttr s =
    escape s
        |> String.replace "\"" "&quot;"
