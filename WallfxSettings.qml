import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "wallfx"

    readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
    readonly property string wallfxBin: pluginDir + "/bin/wallfx"

    property string envSummary: "Checking AI cutout environment…"
    property string activePreset: ""

    readonly property var presets: ({
        "fast": {
            title: "Fast & Snappy",
            subtitle: "~1.0s • Crisp 6px arcade cells • Quick trace",
            values: {
                advancedTiming: true,
                msDraw: 380,
                msFill: 280,
                msBg: 550,
                stageOverlap: 25,
                msPerfil: 1100,
                msContagio: 1000,
                lineW: 14,
                outlineGlow: 20,
                glow: 85,
                cellSize: 6,
                parallax: 20,
                stageDim: 15
            }
        },
        "standard": {
            title: "Standard Balanced",
            subtitle: "~1.9s • Classic 4px cells • Balanced flow",
            values: {
                advancedTiming: true,
                msDraw: 650,
                msFill: 600,
                msBg: 1000,
                stageOverlap: 20,
                msPerfil: 2000,
                msContagio: 1800,
                lineW: 18,
                outlineGlow: 35,
                glow: 90,
                cellSize: 4,
                parallax: 30,
                stageDim: 22
            }
        },
        "cinematic": {
            title: "Slow Cinematic",
            subtitle: "~3.4s • Bold 3px neon trace • Punchy fill • 2px liquid wave",
            values: {
                advancedTiming: true,
                msDraw: 1500,
                msFill: 380,
                msBg: 1800,
                stageOverlap: 15,
                msPerfil: 3500,
                msContagio: 2400,
                lineW: 30,
                outlineGlow: 45,
                glow: 100,
                cellSize: 2,
                parallax: 50,
                stageDim: 30
            }
        }
    })

    function applyPreset(presetKey) {
        const entry = root.presets[presetKey]
        if (!entry) return
        const v = entry.values
        root.activePreset = presetKey

        advTimingToggle.value = v.advancedTiming
        root.saveValue("advancedTiming", v.advancedTiming)

        advDrawSlider.value = v.msDraw
        advFillSlider.value = v.msFill
        advBgSlider.value = v.msBg
        advOverlapSlider.value = v.stageOverlap
        simplePerfilSlider.value = v.msPerfil
        contagioSlider.value = v.msContagio
        lineWSlider.value = v.lineW
        outlineGlowSlider.value = v.outlineGlow
        glowSlider.value = v.glow
        cellSizeSlider.value = v.cellSize
        parallaxSlider.value = v.parallax
        stageDimSlider.value = v.stageDim

        for (const k in v) {
            root.saveValue(k, v[k])
        }
        ToastService.showInfo("WallFX Preset Applied", entry.title + " (" + entry.subtitle + ")")
    }

    // Compute live preview of total duration when Advanced Stage Timing is enabled
    readonly property real overlapRatio: Math.max(0.0, Math.min(0.6, Number(advOverlapSlider.value ?? 20) / 100.0))
    readonly property real s2Start: Number(advDrawSlider.value ?? 650) * (1.0 - overlapRatio)
    readonly property real s3Start: s2Start + Number(advFillSlider.value ?? 650) * (1.0 - overlapRatio)
    readonly property int computedTotalMs: Math.round(
        Math.max(
            Number(advDrawSlider.value ?? 650),
            s2Start + Number(advFillSlider.value ?? 650),
            s3Start + Number(advBgSlider.value ?? 1000)
        )
    )

    Process {
        id: statusCheckProc
        command: [root.wallfxBin, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const st = JSON.parse(text.trim())
                    root.envSummary = (st.venv ? "Venv: Ready" : "Venv: Not installed")
                        + "  •  BiRefNet Model: " + (st.model ? "Downloaded" : "Downloads on first warm (~210 MB)")
                        + "  •  Cached Outlines: " + st.outlines
                        + "  •  Contagion Pool: " + st.spreads
                } catch (e) {
                    root.envSummary = "Unable to query status"
                }
            }
        }
    }

    Component.onCompleted: statusCheckProc.running = true

    StyledText {
        text: "WallFX Transitions & Skewed Carousel"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        text: root.envSummary
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Row {
        spacing: Theme.spacingS

        Rectangle {
            height: 34
            width: openLabel.implicitWidth + 24
            radius: Theme.cornerRadius
            color: Theme.primary
            StyledText {
                id: openLabel
                anchors.centerIn: parent
                text: "Open Carousel"
                color: Theme.surface
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["dms", "ipc", "call", "wallfx", "open"])
            }
        }

        Rectangle {
            height: 34
            width: randLabel.implicitWidth + 24
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.outline
            StyledText {
                id: randLabel
                anchors.centerIn: parent
                text: "Test Random Wallpaper"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["dms", "ipc", "call", "wallfx", "random"])
            }
        }

        Rectangle {
            height: 34
            width: warmLabel.implicitWidth + 24
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.outline
            StyledText {
                id: warmLabel
                anchors.centerIn: parent
                text: "Pre-Warm Outlines"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["dms", "ipc", "call", "wallfx", "warm"])
                    ToastService.showInfo("WallFX", "Warming character outlines in the background…")
                }
            }
        }

        Rectangle {
            height: 34
            width: setupLabel.implicitWidth + 24
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.outline
            StyledText {
                id: setupLabel
                anchors.centerIn: parent
                text: "Repair / Install Venv"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["dms", "ipc", "call", "wallfx", "setup"])
            }
        }
    }

    // ─────────────────── Style Presets ───────────────────
    StyledText {
        text: "Transition Presets"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.primary
    }

    StyledText {
        text: "Click a preset to load its timing and shader parameters (you can fine-tune any slider afterwards):"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
    }

    Row {
        spacing: Theme.spacingS

        Repeater {
            model: [
                { key: "fast", title: "Fast", desc: "~1.0s • 6px cells" },
                { key: "standard", title: "Standard", desc: "~1.9s • 4px cells" },
                { key: "cinematic", title: "Cinematic", desc: "~3.4s • 2px wave" }
            ]

            Rectangle {
                required property var modelData
                width: 148
                height: 44
                radius: Theme.cornerRadius
                readonly property bool isCurrent: root.activePreset === modelData.key
                color: isCurrent
                    ? Theme.withAlpha(Theme.primary, 0.18)
                    : (presetMouse.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                border.width: isCurrent ? 2 : 1
                border.color: isCurrent ? Theme.primary : Theme.outline

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 1

                    StyledText {
                        text: parent.parent.modelData.title
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: parent.parent.isCurrent ? Theme.primary : Theme.surfaceText
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: parent.parent.modelData.desc
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        width: parent.width
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyPreset(parent.modelData.key)
                }
            }
        }
    }

    // ─────────────────── General Behavior ───────────────────
    StyledText {
        text: "General Behavior"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.primary
    }

    SelectionSetting {
        settingKey: "mode"
        label: "Transition Style"
        description: "Auto uses Character Outline when a subject is detected and Contagion for landscapes"
        options: [
            { label: "Auto (Outline + Contagion Fallback)", value: "auto" },
            { label: "Character Outline Only", value: "outline" },
            { label: "Contagion Only", value: "contagion" }
        ]
        defaultValue: "auto"
    }

    ToggleSetting {
        settingKey: "interceptAllChanges"
        label: "Animate All DMS Wallpaper Changes"
        description: "Also play WallFX transitions when changing wallpapers from DMS's built-in picker or CLI"
        defaultValue: true
    }

    StringSetting {
        settingKey: "wallsDir"
        label: "Wallpapers Directory"
        description: "Folder used by the skewed carousel and outline pre-warmer (leave empty to auto-detect ~/Pictures/Wallpapers)"
        placeholder: "~/Pictures/Wallpapers"
        defaultValue: ""
    }

    // ─────────────────── Performance & Resource Limits ───────────────────
    StyledText {
        text: "Performance & Resource Limits"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.primary
    }

    SelectionSetting {
        settingKey: "cutoutModel"
        label: "AI Subject Cutout Model"
        description: "IS-Net uses ~1 GB RAM (85% less RAM than BiRefNet's ~6.9 GB). U2-Net uses ~700 MB for low-RAM PCs."
        options: [
            { label: "IS-Net General (Recommended • ~1.0 GB RAM)", value: "isnet-general-use" },
            { label: "IS-Net Anime & Illustration (~1.1 GB RAM)", value: "isnet-anime" },
            { label: "U2-Net Standard (Low RAM • ~700 MB RAM)", value: "u2net" },
            { label: "U2-Net Lite (Ultra-Low RAM • ~500 MB RAM)", value: "u2netp" },
            { label: "BiRefNet Lite (High RAM • ~6.9 GB RAM)", value: "birefnet-general-lite" }
        ]
        defaultValue: "isnet-general-use"
    }

    SliderSetting {
        settingKey: "maxThreads"
        label: "Max CPU Threads for Cutouts"
        description: "Caps ONNX Runtime & OpenCV thread usage so background cutouts never spike CPU to 100%"
        minimum: 1
        maximum: 8
        defaultValue: 2
    }

    ToggleSetting {
        settingKey: "autoWarm"
        label: "Auto Pre-Warm Entire Folder in Background"
        description: "Off by default to prevent CPU/RAM usage on startup. Outlines are generated on-demand when you pick a wallpaper (or when clicking Pre-Warm Outlines)."
        defaultValue: false
    }

    // ─────────────────── Duration & Advanced Stage Timing ───────────────────
    StyledText {
        text: "Duration & Stage Timing"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.primary
    }

    ToggleSetting {
        id: advTimingToggle
        settingKey: "advancedTiming"
        label: "Advanced Duration Configuration"
        description: "Control the duration of Character Drawing, Character Inside Emerging, and Background Emerging separately"
        defaultValue: false
    }

    SliderSetting {
        id: simplePerfilSlider
        visible: !advTimingToggle.value
        settingKey: "msPerfil"
        label: "Total Character Outline Duration"
        description: "Overall duration of the character outline transition when Advanced Timing is off"
        minimum: 900
        maximum: 5000
        defaultValue: 2000
        unit: "ms"
    }

    StyledText {
        visible: advTimingToggle.value
        text: "Computed Total Outline Transition: " + root.computedTotalMs + " ms"
            + "  (1. Draw: 0 → " + advDrawSlider.value + " ms"
            + "  •  2. Inside Fill: " + Math.round(root.s2Start) + " → " + Math.round(root.s2Start + advFillSlider.value) + " ms"
            + "  •  3. Background: " + Math.round(root.s3Start) + " → " + root.computedTotalMs + " ms)"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.secondary
        wrapMode: Text.WordWrap
        width: parent.width
    }

    SliderSetting {
        id: advDrawSlider
        visible: advTimingToggle.value
        settingKey: "msDraw"
        label: "1. Drawing Character Outline Duration"
        description: "How long the two pen strokes take to trace the character's silhouette from top to bottom"
        minimum: 200
        maximum: 3000
        defaultValue: 650
        unit: "ms"
    }

    SliderSetting {
        id: advFillSlider
        visible: advTimingToggle.value
        settingKey: "msFill"
        label: "2. Inside of Character Emerging Duration"
        description: "How long the interior of the character takes to fill inward from its outline"
        minimum: 200
        maximum: 3000
        defaultValue: 650
        unit: "ms"
    }

    SliderSetting {
        id: advBgSlider
        visible: advTimingToggle.value
        settingKey: "msBg"
        label: "3. Background Emerging Duration"
        description: "How long the new background takes to spread outward from the character across the screen"
        minimum: 200
        maximum: 4000
        defaultValue: 1000
        unit: "ms"
    }

    SliderSetting {
        id: advOverlapSlider
        visible: advTimingToggle.value
        settingKey: "stageOverlap"
        label: "Stage Overlap / Blending"
        description: "0% = strictly sequential (wait for each stage to finish 100% before starting the next). 20% = smooth natural overlap."
        minimum: 0
        maximum: 60
        defaultValue: 20
        unit: "%"
    }

    SliderSetting {
        id: contagioSlider
        settingKey: "msContagio"
        label: "Contagion Fallback Duration"
        description: "Total duration when using the colony contagion transition (landscapes without a character)"
        minimum: 800
        maximum: 5000
        defaultValue: 1800
        unit: "ms"
    }

    // ─────────────────── Shader & Transition Visuals ───────────────────
    StyledText {
        text: "Shader & Transition Visuals"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.primary
    }

    SliderSetting {
        id: outlineGlowSlider
        settingKey: "outlineGlow"
        label: "Character Aura / Neon Glow"
        description: "Glowing aura around the character silhouette while tracing and along the emerging wave (0% = clean non-glowing pen)"
        minimum: 0
        maximum: 150
        defaultValue: 35
        unit: "%"
    }

    SliderSetting {
        id: glowSlider
        settingKey: "glow"
        label: "Contagion Burning Edge Glow"
        description: "Brightness of the burning ember edge and sparks during Contagion transitions"
        minimum: 0
        maximum: 150
        defaultValue: 90
        unit: "%"
    }

    SliderSetting {
        id: lineWSlider
        settingKey: "lineW"
        label: "Outline Pen Width"
        description: "Thickness of the pen line tracing the character silhouette (in tenths of a pixel: 15 = 1.5 px, 30 = 3.0 px)"
        minimum: 5
        maximum: 40
        defaultValue: 15
    }

    SliderSetting {
        id: cellSizeSlider
        settingKey: "cellSize"
        label: "Pixel Cell Size"
        description: "Size of the cells that fill the character and background (1 px = smooth liquid wave, 4 px = default, 8–12 px = retro pixel art)"
        minimum: 1
        maximum: 12
        defaultValue: 4
        unit: "px"
    }

    SliderSetting {
        id: parallaxSlider
        settingKey: "parallax"
        label: "3D Parallax Zoom Depth"
        description: "2.5D camera settle where the character zooms in slightly closer than the background (0 = flat, 30 = 3.0% depth, 80 = 8.0% depth)"
        minimum: 0
        maximum: 80
        defaultValue: 30
    }

    SliderSetting {
        id: stageDimSlider
        settingKey: "stageDim"
        label: "Old Wallpaper Stage Dimming"
        description: "How much the old wallpaper darkens and desaturates at the start so the character outline pops"
        minimum: 0
        maximum: 80
        defaultValue: 20
        unit: "%"
    }

    // ─────────────────── Outline & Glow Colors ───────────────────
    StyledText {
        text: "Outline & Glow Colors"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.primary
    }

    SelectionSetting {
        id: colorModeSelect
        settingKey: "colorMode"
        label: "Color Palette Source"
        description: "Choose how the outline pen color and glow/ember color are selected"
        options: [
            { label: "Auto (Lightest Theme Tone + Most Vivid Tone)", value: "auto" },
            { label: "Theme Primary & Secondary Accents", value: "accent" },
            { label: "Custom Colors", value: "custom" }
        ]
        defaultValue: "auto"
    }

    ColorSetting {
        visible: colorModeSelect.value === "custom"
        settingKey: "customInkColor"
        label: "Custom Outline Pen Color"
        description: "Color of the pen strokes that trace the character's silhouette"
        defaultValue: "#ffffff"
    }

    ColorSetting {
        visible: colorModeSelect.value === "custom"
        settingKey: "customEmberColor"
        label: "Custom Aura & Ember Glow Color"
        description: "Color of the character aura, shockwave rim, and contagion burning edge"
        defaultValue: "#ff9e64"
    }
}
