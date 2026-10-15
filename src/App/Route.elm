module App.Route exposing (fromUrl, toPath)

import App.Model exposing (Route(..))
import Url exposing (Url)


fromUrl : String -> Url -> Route
fromUrl basePath url =
    let
        base =
            if String.endsWith "/" basePath then
                basePath

            else
                basePath ++ "/"

        path =
            if String.startsWith base url.path then
                String.dropLeft (String.length base) url.path

            else
                String.dropLeft 1 url.path

        segments =
            String.split "/" path |> List.filter (not << String.isEmpty)
    in
    case segments of
        [] ->
            Welcome

        [ "editor", id ] ->
            EditorRoute id

        [ "preview", id, sceneId ] ->
            PreviewRoute id sceneId

        _ ->
            NotFound


toPath : String -> Route -> String
toPath basePath route =
    let
        base =
            if String.endsWith "/" basePath then
                basePath

            else
                basePath ++ "/"
    in
    case route of
        Welcome ->
            base

        EditorRoute id ->
            base ++ "editor/" ++ id

        PreviewRoute id sceneId ->
            base ++ "preview/" ++ id ++ "/" ++ sceneId

        NotFound ->
            base
