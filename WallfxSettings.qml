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
                text: "Random Wallpaper"
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

    SliderSetting {
        settingKey: "msPerfil"
        label: "Character Outline Duration"
        description: "Total duration of the 4-stage outline trace, character fill, and background eruption"
        minimum: 900
        maximum: 4000
        defaultValue: 2000
        unit: "ms"
    }

    SliderSetting {
        settingKey: "msContagio"
        label: "Contagion Duration"
        description: "Total duration of the colony spread transition"
        minimum: 800
        maximum: 4000
        defaultValue: 1800
        unit: "ms"
    }

    SliderSetting {
        settingKey: "glow"
        label: "Edge Glow Intensity"
        description: "Brightness of the ember and silhouette glow (percentage)"
        minimum: 0
        maximum: 150
        defaultValue: 90
        unit: "%"
    }

    SliderSetting {
        settingKey: "lineW"
        label: "Outline Pen Width"
        description: "Thickness of the character silhouette pen stroke (in tenths of a pixel, 15 = 1.5 px)"
        minimum: 8
        maximum: 35
        defaultValue: 15
    }
}
