module Export.Format exposing
    ( Availability(..)
    , Format(..)
    , all
    , availability
    , code
    , description
    , extension
    , fromCode
    , isAnimated
    , isRaster
    , label
    )

{-| Export targets. A format is only `Available` when a tested adapter exists
in this build; everything else reports why it is unavailable instead of
offering a button that produces an unverified file.
-}


type Format
    = StaticSvg
    | AnimatedSvg
    | SvgCss
    | HtmlPlayer
    | PngStill
    | PngSequence
    | Gif
    | Apng
    | WebM
    | Mp4
    | Lottie


type Availability
    = Available
    | Unavailable String


all : List Format
all =
    [ StaticSvg, AnimatedSvg, SvgCss, HtmlPlayer, PngStill, PngSequence, Gif, Apng, WebM, Mp4, Lottie ]


code : Format -> String
code f =
    case f of
        StaticSvg ->
            "svg"

        AnimatedSvg ->
            "smil"

        SvgCss ->
            "svg-css"

        HtmlPlayer ->
            "html"

        PngStill ->
            "png"

        PngSequence ->
            "png-sequence"

        Gif ->
            "gif"

        Apng ->
            "apng"

        WebM ->
            "webm"

        Mp4 ->
            "mp4"

        Lottie ->
            "lottie"


fromCode : String -> Maybe Format
fromCode s =
    List.filter (\f -> code f == s) all |> List.head


label : Format -> String
label f =
    case f of
        StaticSvg ->
            "Static SVG"

        AnimatedSvg ->
            "Animated SVG (SMIL)"

        SvgCss ->
            "SVG + CSS"

        HtmlPlayer ->
            "HTML + Framewise Player"

        PngStill ->
            "PNG still"

        PngSequence ->
            "PNG sequence (ZIP)"

        Gif ->
            "GIF"

        Apng ->
            "APNG"

        WebM ->
            "WebM video"

        Mp4 ->
            "MP4 video"

        Lottie ->
            "Lottie JSON"


description : Format -> String
description f =
    case f of
        StaticSvg ->
            "The evaluated still state at one frame as a self-contained SVG file."

        AnimatedSvg ->
            "A single SVG file animated with native SMIL elements. Works in current Chrome, Firefox and Safari without JavaScript."

        SvgCss ->
            "An SVG file with an embedded stylesheet using CSS @keyframes. Transform, opacity and paint animation only."

        HtmlPlayer ->
            "A standalone HTML page with the Framewise player runtime. Supports every animatable property, including path morphs and text."

        PngStill ->
            "One rasterised frame at 1x, 2x or 3x."

        PngSequence ->
            "Every frame in the range rendered to PNG and packaged as a ZIP with a manifest."

        Gif ->
            "Animated GIF."

        Apng ->
            "Animated PNG."

        WebM ->
            "WebM video."

        Mp4 ->
            "MP4 (H.264) video."

        Lottie ->
            "Lottie JSON interchange."


extension : Format -> String
extension f =
    case f of
        StaticSvg ->
            "svg"

        AnimatedSvg ->
            "svg"

        SvgCss ->
            "svg"

        HtmlPlayer ->
            "zip"

        PngStill ->
            "png"

        PngSequence ->
            "zip"

        Gif ->
            "gif"

        Apng ->
            "png"

        WebM ->
            "webm"

        Mp4 ->
            "mp4"

        Lottie ->
            "json"


isAnimated : Format -> Bool
isAnimated f =
    case f of
        StaticSvg ->
            False

        PngStill ->
            False

        _ ->
            True


isRaster : Format -> Bool
isRaster f =
    case f of
        PngStill ->
            True

        PngSequence ->
            True

        Gif ->
            True

        Apng ->
            True

        WebM ->
            True

        Mp4 ->
            True

        _ ->
            False


availability : Format -> Availability
availability f =
    case f of
        Gif ->
            Unavailable "No verified GIF encoder is bundled in this build. Export a PNG sequence and encode it with an external tool."

        Apng ->
            Unavailable "No verified APNG encoder is bundled in this build. Export a PNG sequence instead."

        WebM ->
            Unavailable "Video encoding is not available in this build. Export a PNG sequence and encode it with ffmpeg."

        Mp4 ->
            Unavailable "Video encoding is not available in this build. Export a PNG sequence and encode it with ffmpeg."

        Lottie ->
            Unavailable "Lottie interchange has not been verified against an independent player in this build."

        _ ->
            Available
