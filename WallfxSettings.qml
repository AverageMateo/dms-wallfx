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
        visible: !advTimingToggle.value
        settingKey: "msPerfil"
        label: "Total Character Outline Duration"
        description: "Overall duration of the character outline transition when Advanced Timing is off"
        minimum: 900
        maximum: 5000
        defaultValue: 2000
        unit: "ms"
    }

    Column {
        visible: advTimingToggle.value
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
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
            settingKey: "stageOverlap"
            label: "Stage Overlap / Blending"
            description: "0% = strictly sequential (wait for each stage to finish 100% before starting the next). 20% = smooth natural overlap."
            minimum: 0
            maximum: 60
            defaultValue: 20
            unit: "%"
        }
    }

    SliderSetting {
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
        settingKey: "outlineGlow"
        label: "Character Aura / Neon Glow"
        description: "Glowing aura around the character silhouette while tracing and along the emerging wave (0% = clean non-glowing pen)"
        minimum: 0
        maximum: 150
        defaultValue: 35
        unit: "%"
    }

    SliderSetting {
        settingKey: "glow"
        label: "Contagion Burning Edge Glow"
        description: "Brightness of the burning ember edge and sparks during Contagion transitions"
        minimum: 0
        maximum: 150
        defaultValue: 90
        unit: "%"
    }

    SliderSetting {
        settingKey: "lineW"
        label: "Outline Pen Width"
        description: "Thickness of the pen line tracing the character silhouette (in tenths of a pixel: 15 = 1.5 px, 25 = 2.5 px)"
        minimum: 5
        maximum: 40
        defaultValue: 15
    }

    SliderSetting {
        settingKey: "cellSize"
        label: "Pixel Cell Size"
        description: "Size of the cells that fill the character and background (1 px = smooth liquid wave, 4 px = default, 8–12 px = retro pixel art)"
        minimum: 1
        maximum: 12
        defaultValue: 4
        unit: "px"
    }

    SliderSetting {
        settingKey: "parallax"
        label: "3D Parallax Zoom Depth"
        description: "2.5D camera settle where the character zooms in slightly closer than the background (0 = flat, 30 = 3.0% depth, 80 = 8.0% depth)"
        minimum: 0
        maximum: 80
        defaultValue: 30
    }

    SliderSetting {
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

    Column {
        visible: colorModeSelect.value === "custom"
        width: parent.width
        spacing: Theme.spacingM

        ColorSetting {
            settingKey: "customInkColor"
            label: "Custom Outline Pen Color"
            description: "Color of the pen strokes that trace the character's silhouette"
            defaultValue: "#ffffff"
        }

        ColorSetting {
            settingKey: "customEmberColor"
            label: "Custom Aura & Ember Glow Color"
            description: "Color of the character aura, shockwave rim, and contagion burning edge"
            defaultValue: "#ff9e64"
        }
    }
}
