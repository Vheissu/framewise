module UI.Fields exposing
    ( checkbox
    , iconButton
    , numberField
    , onEnter
    , row
    , section
    , select
    , stopPropagation
    , textField
    )

{-| Shared form controls. Numeric fields are controlled through
`model.fieldDrafts`: while focused the draft text is shown, otherwise the
formatted value. Enter commits, Escape reverts, arrows step.
-}

import App.Model exposing (Model)
import App.Msg exposing (Msg(..))
import Dict
import Html exposing (Html, button, div, input, label, option, span, text)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import Set
import UI.Icons as Icons


row : String -> List (Html Msg) -> Html Msg
row labelText children =
    div [ A.class "field-row" ]
        [ span [ A.class "field-label" ] [ text labelText ]
        , div [ A.class "field-controls" ] children
        ]


section : Model -> String -> String -> List (Html Msg) -> Html Msg
section model id title children =
    let
        collapsed =
            Set.member id model.editor.collapsedSections
    in
    div [ A.class "section", A.classList [ ( "collapsed", collapsed ) ] ]
        [ button
            [ A.class "section-header"
            , E.onClick (ToggleSection id)
            , A.attribute "aria-expanded"
                (if collapsed then
                    "false"

                 else
                    "true"
                )
            ]
            [ Icons.icon
                (if collapsed then
                    "chevron-right"

                 else
                    "chevron-down"
                )
            , span [] [ text title ]
            ]
        , if collapsed then
            text ""

          else
            div [ A.class "section-body" ] children
        ]


{-| A numeric field bound to a field id. `shown` is the value to display when
no draft is active; `step` is the arrow increment.
-}
numberField :
    Model
    -> { id : String, label : String, value : Maybe Float, step : Float, unit : String, animated : Maybe (Html Msg) }
    -> Html Msg
numberField model cfg =
    let
        draft =
            Dict.get cfg.id model.fieldDrafts

        shown =
            case draft of
                Just d ->
                    d

                Nothing ->
                    case cfg.value of
                        Just v ->
                            formatNumber v

                        Nothing ->
                            "—"

        keyHandler =
            E.custom "keydown"
                (D.field "key" D.string
                    |> D.andThen
                        (\key ->
                            case key of
                                "Enter" ->
                                    D.succeed { message = FieldCommit cfg.id, stopPropagation = True, preventDefault = True }

                                "Escape" ->
                                    D.succeed { message = FieldCancel cfg.id, stopPropagation = True, preventDefault = True }

                                "ArrowUp" ->
                                    D.field "shiftKey" D.bool
                                        |> D.map
                                            (\shift ->
                                                { message =
                                                    FieldStep cfg.id
                                                        (if shift then
                                                            cfg.step * 10

                                                         else
                                                            cfg.step
                                                        )
                                                , stopPropagation = True
                                                , preventDefault = True
                                                }
                                            )

                                "ArrowDown" ->
                                    D.field "shiftKey" D.bool
                                        |> D.map
                                            (\shift ->
                                                { message =
                                                    FieldStep cfg.id
                                                        (if shift then
                                                            -cfg.step * 10

                                                         else
                                                            -cfg.step
                                                        )
                                                , stopPropagation = True
                                                , preventDefault = True
                                                }
                                            )

                                _ ->
                                    D.fail "ignore"
                        )
                )
    in
    label [ A.class "num-field", A.classList [ ( "editing", draft /= Nothing ) ] ]
        [ span [ A.class "num-label", A.title cfg.label ] [ text cfg.label ]
        , input
            [ A.type_ "text"
            , A.class "num-input"
            , A.value shown
            , A.attribute "inputmode" "decimal"
            , A.attribute "aria-label" cfg.label
            , A.disabled (cfg.value == Nothing && draft == Nothing)
            , E.onInput (FieldInput cfg.id)
            , E.onBlur (FieldCommit cfg.id)
            , E.onFocus (FieldInput cfg.id shown)
            , keyHandler
            ]
            []
        , if String.isEmpty cfg.unit then
            text ""

          else
            span [ A.class "num-unit" ] [ text cfg.unit ]
        , Maybe.withDefault (text "") cfg.animated
        ]


formatNumber : Float -> String
formatNumber v =
    let
        r =
            toFloat (round (v * 100)) / 100
    in
    if r == toFloat (round r) then
        String.fromInt (round r)

    else
        String.fromFloat r


textField : Model -> { id : String, label : String, value : String, placeholder : String } -> Html Msg
textField model cfg =
    let
        draft =
            Dict.get cfg.id model.fieldDrafts
    in
    label [ A.class "text-field" ]
        [ span [ A.class "sr-only" ] [ text cfg.label ]
        , input
            [ A.type_ "text"
            , A.value (Maybe.withDefault cfg.value draft)
            , A.placeholder cfg.placeholder
            , A.attribute "aria-label" cfg.label
            , E.onInput (FieldInput cfg.id)
            , E.onBlur (FieldCommit cfg.id)
            , onEnterOrEscape (FieldCommit cfg.id) (FieldCancel cfg.id)
            ]
            []
        ]


onEnterOrEscape : Msg -> Msg -> Html.Attribute Msg
onEnterOrEscape enter escape =
    E.custom "keydown"
        (D.field "key" D.string
            |> D.andThen
                (\key ->
                    case key of
                        "Enter" ->
                            D.succeed { message = enter, stopPropagation = True, preventDefault = True }

                        "Escape" ->
                            D.succeed { message = escape, stopPropagation = True, preventDefault = True }

                        _ ->
                            D.fail "ignore"
                )
        )


onEnter : Msg -> Html.Attribute Msg
onEnter msg =
    E.on "keydown"
        (D.field "key" D.string
            |> D.andThen
                (\key ->
                    if key == "Enter" then
                        D.succeed msg

                    else
                        D.fail "ignore"
                )
        )


checkbox : String -> Bool -> (Bool -> Msg) -> Html Msg
checkbox labelText checked toMsg =
    label [ A.class "checkbox" ]
        [ input [ A.type_ "checkbox", A.checked checked, E.onCheck toMsg ] []
        , span [] [ text labelText ]
        ]


select : String -> String -> List ( String, String ) -> (String -> Msg) -> Html Msg
select labelText current options toMsg =
    label [ A.class "select-field" ]
        [ span [ A.class "sr-only" ] [ text labelText ]
        , Html.select [ E.onInput toMsg, A.attribute "aria-label" labelText ]
            (List.map (\( v, l ) -> option [ A.value v, A.selected (v == current) ] [ text l ]) options)
        ]


iconButton : { icon : String, label : String, active : Bool, onClick : Msg, disabled : Bool } -> Html Msg
iconButton cfg =
    button
        [ A.class "icon-button"
        , A.classList [ ( "active", cfg.active ) ]
        , A.title cfg.label
        , A.attribute "aria-label" cfg.label
        , A.attribute "aria-pressed"
            (if cfg.active then
                "true"

             else
                "false"
            )
        , A.disabled cfg.disabled
        , E.onClick cfg.onClick
        ]
        [ Icons.icon cfg.icon ]


stopPropagation : String -> Msg -> Html.Attribute Msg
stopPropagation event msg =
    E.stopPropagationOn event (D.succeed ( msg, True ))
