module Export.Static exposing (Options, defaultOptions, export)

{-| Static SVG export: the evaluated still state at one frame.
Raster assets are referenced as `fw-asset://<id>`; the packaging adapter
replaces each token with the asset's data URI.
-}

import Dict
import Domain.Document exposing (Document)
import Domain.Evaluate as Evaluate
import Domain.Scene exposing (Scene)
import Render.Scene as Render
import Render.SvgDoc as Svg


type alias Options =
    { frame : Float
    , includeBackground : Bool
    , includeIds : Bool
    , title : Maybe String
    , description : Maybe String
    }


defaultOptions : Options
defaultOptions =
    { frame = 0, includeBackground = True, includeIds = True, title = Nothing, description = Nothing }


export : Options -> Document -> Scene -> Maybe String
export options doc scene =
    Evaluate.evaluateScene doc scene.id options.frame
        |> Maybe.map
            (\resolved ->
                let
                    renderOptions =
                        { idPrefix = "fw-" ++ shortId scene.id
                        , assetUrls = Dict.map (\id _ -> "fw-asset://" ++ id) doc.assets
                        , includeBackground = options.includeBackground
                        , includeIds = options.includeIds
                        , title = options.title
                        , description = options.description
                        , standalone = True
                        }
                in
                xmlHeader ++ Svg.toString (Render.renderScene renderOptions resolved)
            )


xmlHeader : String
xmlHeader =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"


shortId : String -> String
shortId id =
    String.left 8 (String.filter Char.isAlphaNum id)
