module Main exposing (main)

import App.Model
import App.Msg exposing (Msg(..))
import App.Update as Update
import App.View as View
import Browser
import Json.Decode as D


main : Program D.Value App.Model.Model Msg
main =
    Browser.application
        { init = Update.init
        , view = View.view
        , update = Update.update
        , subscriptions = Update.subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }
