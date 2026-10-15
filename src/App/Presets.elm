module App.Presets exposing (Preset, all, categories, find)

{-| New-document presets shown on the welcome screen.
-}


type alias Preset =
    { id : String
    , label : String
    , category : String
    , width : Float
    , height : Float
    , fps : Int
    , duration : Int
    , transparent : Bool
    }


all : List Preset
all =
    [ Preset "icon-24" "Icon 24" "Icon" 24 24 30 30 True
    , Preset "icon-32" "Icon 32" "Icon" 32 32 30 30 True
    , Preset "icon-48" "Icon 48" "Icon" 48 48 30 30 True
    , Preset "icon-64" "Icon 64" "Icon" 64 64 30 30 True
    , Preset "icon-128" "Icon 128" "Icon" 128 128 30 60 True
    , Preset "logo-square" "Logo square 512" "Logo" 512 512 30 90 True
    , Preset "illustration" "Illustration 1080" "Illustration" 1080 1080 30 120 False
    , Preset "banner" "Banner 1920×1080" "Banner" 1920 1080 30 150 False
    , Preset "custom" "Custom" "Custom" 400 400 30 60 True
    ]


categories : List String
categories =
    [ "Icon", "Logo", "Illustration", "Banner", "Custom" ]


find : String -> Maybe Preset
find id =
    List.filter (\p -> p.id == id) all |> List.head
