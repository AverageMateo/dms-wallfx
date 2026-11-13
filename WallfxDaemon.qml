import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    pluginId: "wallfx"
    pluginService: PluginService

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
    readonly property string wallfxBin: pluginDir + "/bin/wallfx"
    readonly property string thumbsDir: homeDir + "/.cache/wallfx/thumbs"

    // General Settings
    readonly property string configuredWallsDir: String(root.pluginData?.wallsDir ?? "").trim()
    property string detectedWallsDir: homeDir + "/Pictures/Wallpapers"
    readonly property string wallsDir: {
        if (configuredWallsDir.length > 0) {
            return configuredWallsDir.replace(/^~/, homeDir)
        }
        return detectedWallsDir
    }
    readonly property string transitionMode: root.pluginData?.mode ?? "auto"
    readonly property bool interceptAllChanges: root.pluginData?.interceptAllChanges ?? true

    // Duration & Advanced Stage Timing Settings
    readonly property bool advancedTiming: root.pluginData?.advancedTiming ?? false
    readonly property int msPerfilSimple: Number(root.pluginData?.msPerfil ?? 2000)
    readonly property int msContagio: Number(root.pluginData?.msContagio ?? 1800)
    readonly property int msDraw: Number(root.pluginData?.msDraw ?? 650)
    readonly property int msFill: Number(root.pluginData?.msFill ?? 650)
    readonly property int msBg: Number(root.pluginData?.msBg ?? 1000)
    readonly property real stageOverlap: Math.max(0.0, Math.min(0.6, Number(root.pluginData?.stageOverlap ?? 20) / 100.0))

    // Computed stage start & duration in ms when advancedTiming is enabled
    readonly property real _advStart1: 0
    readonly property real _advEnd1: msDraw
    readonly property real _advStart2: msDraw * (1.0 - stageOverlap)
    readonly property real _advEnd2: _advStart2 + msFill
    readonly property real _advStart3: _advStart2 + msFill * (1.0 - stageOverlap)
    readonly property real _advEnd3: _advStart3 + msBg
    readonly property int msPerfilTotal: advancedTiming
        ? Math.max(400, Math.round(Math.max(_advEnd1, _advEnd2, _advEnd3)))
        : msPerfilSimple

    readonly property real tDrawStart: advancedTiming ? (_advStart1 / msPerfilTotal) : 0.02
    readonly property real tDrawDur: advancedTiming ? (msDraw / msPerfilTotal) : 0.33
    readonly property real tFillStart: advancedTiming ? (_advStart2 / msPerfilTotal) : 0.32
    readonly property real tFillDur: advancedTiming ? (msFill / msPerfilTotal) : 0.32
    readonly property real tBgStart: advancedTiming ? (_advStart3 / msPerfilTotal) : 0.45
    readonly property real tBgDur: advancedTiming ? (msBg / msPerfilTotal) : 0.50

    readonly property int msFade: 140

    // Shader Visual Settings
    readonly property real glow: Number(root.pluginData?.glow ?? 90) / 100.0
    readonly property real outlineGlow: Number(root.pluginData?.outlineGlow ?? 35) / 100.0
    readonly property real lineW: Number(root.pluginData?.lineW ?? 15) / 10.0
    readonly property real cellSize: Math.max(1.0, Number(root.pluginData?.cellSize ?? 4))
    readonly property real parallax: Number(root.pluginData?.parallax ?? 30) / 1000.0
    readonly property real stageDim: Number(root.pluginData?.stageDim ?? 20) / 100.0

    // Color Settings
    readonly property string colorMode: root.pluginData?.colorMode ?? "auto"
    readonly property color customInkColor: root.pluginData?.customInkColor ?? "#ffffff"
    readonly property color customEmberColor: root.pluginData?.customEmberColor ?? "#ff9e64"

    // Carousel state
    property bool carouselOpen: false

    // Shader transition state
    property string currentWallpaper: SessionData.wallpaperPath || ""
    property string oldPath: ""
    property string newPath: ""
    property string kind: "contagio"
    property string fieldPath: ""
    property string linePath: ""
    property string phase: "idle"
    property real t: 0
    property real fade: 0
    property bool swapped: false
    property bool externalSwap: false
    property bool _internalSwap: false
    property int gen: 0
    property int readyCount: 0
    readonly property int screenCount: Math.max(fxScreens.instances.length, 1)
    readonly property bool active: phase !== "idle"

    property color ember: "#ff9e64"
    property color ink: "#ffffff"
    property real seed: 0

    property int statFrames: 0
    property real statWorst: 0
    property string lastStats: "No transitions recorded yet"

    IpcHandler {
        target: "wallfx"

        function toggle(): string {
            root.carouselOpen = !root.carouselOpen
            return root.carouselOpen ? "CAROUSEL_OPEN" : "CAROUSEL_CLOSED"
        }

        function open(): string {
            root.carouselOpen = true
            return "CAROUSEL_OPEN"
        }

        function close(): string {
            root.carouselOpen = false
            return "CAROUSEL_CLOSED"
        }

        function apply(path: string): string {
            if (!path) return "ERROR: Missing wallpaper path"
            const resolved = path.replace(/^~/, root.homeDir)
            root.triggerTransition(resolved, false)
            return "TRANSITION_STARTED: " + resolved
        }

        function random(): string {
            if (wallModel.count <= 0) return "ERROR: No wallpapers in " + root.wallsDir
            let idx = Math.floor(Math.random() * wallModel.count)
            if (wallModel.count > 1) {
                const candidate = root.originalOf(wallModel.get(idx, "fileName"))
                if (candidate === SessionData.wallpaperPath) {
                    idx = (idx + 1) % wallModel.count
                }
            }
            const chosen = root.originalOf(wallModel.get(idx, "fileName"))
            root.triggerTransition(chosen, false)
            return "RANDOM_WALLPAPER: " + chosen
        }

        function warm(): string {
            root.warmTransitions()
            return "WARMING: " + root.wallsDir
        }

        function setup(): string {
            root.ensureVenv(true)
            return "INSTALLING_VENV"
        }

        function stats(): string {
            return root.lastStats
        }

        function preset(name: string): string {
            const presets = {
                "fast": {
                    advancedTiming: true, msDraw: 380, msFill: 280, msBg: 550, stageOverlap: 25,
                    msPerfil: 1100, msContagio: 1000, lineW: 14, outlineGlow: 20, glow: 85,
                    cellSize: 6, parallax: 20, stageDim: 15
                },
                "standard": {
                    advancedTiming: true, msDraw: 650, msFill: 600, msBg: 1000, stageOverlap: 20,
                    msPerfil: 2000, msContagio: 1800, lineW: 18, outlineGlow: 35, glow: 90,
                    cellSize: 4, parallax: 30, stageDim: 22
                },
                "cinematic": {
                    advancedTiming: true, msDraw: 1500, msFill: 380, msBg: 1800, stageOverlap: 15,
                    msPerfil: 3500, msContagio: 2400, lineW: 30, outlineGlow: 45, glow: 100,
                    cellSize: 2, parallax: 50, stageDim: 30
                }
            }
            const key = String(name || "").toLowerCase()
            const p = presets[key]
            if (!p) return "ERROR: Unknown preset '" + name + "' (use fast, standard, or cinematic)"
            if (root.pluginService) {
                for (const k in p) {
                    root.pluginService.savePluginData(root.pluginId, k, p[k])
                }
            }
            return "PRESET_APPLIED: " + key
        }
    }

    function lifted(c) {
        return Qt.hsla(
            c.hslHue,
            Math.max(c.hslSaturation, 0.55),
            Math.min(Math.max(c.hslLightness, 0.62), 0.82),
            1.0
        )
    }

    function pickColors() {
        if (root.colorMode === "custom") {
            root.ink = root.customInkColor
            root.ember = root.customEmberColor
            return
        }
        if (root.colorMode === "accent") {
            root.ink = root.lifted(Theme.primary)
            root.ember = root.lifted(Theme.secondary)
            return
        }
        const pal = [
            Theme.primary,
            Theme.secondary,
            Theme.surfaceText,
            Theme.surfaceContainerHigh
        ]
        const chroma = c => c.hslSaturation * (1 - Math.abs(2 * c.hslLightness - 1))
        const light = c => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        root.ember = root.lifted(pal.reduce((a, b) => chroma(b) > chroma(a) ? b : a))
        root.ink = pal.reduce((a, b) => light(b) > light(a) ? b : a)
    }

    function originalOf(thumbName) {
        return root.wallsDir + "/" + String(thumbName).replace(/\.jpg$/, "")
    }

    function refreshThumbs() {
        thumbsProc.command = [root.wallfxBin, "thumbs", root.wallsDir, root.thumbsDir]
        thumbsProc.running = false
        thumbsProc.running = true
    }

    function warmTransitions() {
        if (!warmProc.running) {
            warmProc.command = [root.wallfxBin, "warm", root.wallsDir]
            warmProc.running = true
        }
    }

    function ensureVenv(notifyStart) {
        if (installProc.running) return
        if (notifyStart) {
            ToastService.showInfo("WallFX", "Setting up BiRefNet cutout environment in ~/.local/share/wallfx…")
        }
        installProc.command = [root.wallfxBin, "install"]
        installProc.running = true
    }

    function triggerTransition(targetNewPath, isExternal) {
        if (!targetNewPath || String(targetNewPath).startsWith("#")) {
            root.currentWallpaper = targetNewPath
            return
        }
        const prev = root.currentWallpaper || SessionData.wallpaperPath
        if (!prev || String(prev).startsWith("#") || prev === targetNewPath) {
            if (!isExternal) {
                root._internalSwap = true
                SessionData.setWallpaper(targetNewPath)
            }
            root.currentWallpaper = targetNewPath
            return
        }

        if (root.active) {
            root.finish()
        }

        root.oldPath = prev
        root.newPath = targetNewPath
        root.externalSwap = isExternal
        root.swapped = isExternal
        root.t = 0
        root.fade = isExternal ? 1 : 0
        root.readyCount = 0
        root.gen++
        root.phase = "choosing"
        watchdog.restart()

        eligeProc.targetGen = root.gen
        eligeProc.command = [root.wallfxBin, "elige", "--mode", root.transitionMode, targetNewPath]
        eligeProc.running = false
        eligeProc.running = true
    }

    function prepareMaps(k, f, l) {
        root.kind = k === "perfil" ? "perfil" : "contagio"
        root.readyCount = 0
        root.phase = "loading"
        root.fieldPath = f
        root.linePath = l || f
    }

    function screenReady() {
        if (root.phase !== "loading") return
        root.readyCount++
        if (root.readyCount < root.screenCount) return
        watchdog.stop()
        root.go()
    }

    function go() {
        if (root.phase !== "loading" && root.phase !== "ready") return
        root.pickColors()
        root.seed = Math.random() * 100
        root.phase = "run"
        runAnim.duration = root.kind === "perfil" ? root.msPerfilTotal : root.msContagio
        runAnim.restart()
        if (root.externalSwap) {
            root.fade = 1
        } else {
            fadeInAnim.restart()
        }
    }

    function performDmsSwap() {
        if (root.externalSwap || root.swapped) return
        root._internalSwap = true
        root.currentWallpaper = root.newPath
        SessionData.setWallpaper(root.newPath)
        settleTimer.restart()
    }

    function maybeFinish() {
        if (runAnim.running) return
        if (!root.swapped) {
            root.phase = "held"
            watchdog.restart()
            return
        }
        root.phase = "fadeout"
        fadeOutAnim.restart()
    }

    function finish() {
        fadeInAnim.stop()
        runAnim.stop()
        fadeOutAnim.stop()
        watchdog.stop()
        settleTimer.stop()
        if (!root.externalSwap && !root.swapped && root.newPath) {
            root._internalSwap = true
            SessionData.setWallpaper(root.newPath)
        }
        if (root.newPath) {
            root.currentWallpaper = root.newPath
        }
        root.phase = "idle"
        root.fade = 0
        root.t = 0
        root.oldPath = ""
        root.newPath = ""
        root.fieldPath = ""
        root.linePath = ""
        root.warmTransitions()
    }

    // Intercept wallpaper changes made outside the carousel (e.g. DMS Settings / CLI)
    Connections {
        target: SessionData
        function onWallpaperPathChanged() {
            const next = SessionData.wallpaperPath
            if (root._internalSwap) {
                root._internalSwap = false
                root.currentWallpaper = next
                return
            }
            if (!root.interceptAllChanges || !next || next === root.currentWallpaper) {
                root.currentWallpaper = next
                return
            }
            root.triggerTransition(next, true)
        }
    }

    NumberAnimation {
        id: fadeInAnim
        target: root
        property: "fade"
        from: 0
        to: 1
        duration: root.msFade
        easing.type: Easing.OutQuad
        onFinished: root.performDmsSwap()
    }

    NumberAnimation {
        id: runAnim
        target: root
        property: "t"
        from: 0
        to: 1
        easing.type: Easing.Linear
        onFinished: root.maybeFinish()
    }

    NumberAnimation {
        id: fadeOutAnim
        target: root
        property: "fade"
        from: 1
        to: 0
        duration: root.msFade
        easing.type: Easing.OutQuad
        onFinished: root.finish()
    }

    Timer {
        id: settleTimer
        interval: 60
        onTriggered: {
            root.swapped = true
            root.maybeFinish()
        }
    }

    Timer {
        id: watchdog
        interval: 28000
        onTriggered: root.finish()
    }

    FrameAnimation {
        running: root.phase === "run"
        onRunningChanged: {
            if (running) {
                root.statFrames = 0
                root.statWorst = 0
            } else if (root.statFrames > 0) {
                root.lastStats = root.kind + ": " + root.statFrames + " frames in "
                    + runAnim.duration + " ms (" + Math.round(root.statFrames * 1000 / runAnim.duration)
                    + " fps), worst frame " + Math.round(root.statWorst * 1000) + " ms"
            }
        }
        onTriggered: {
            root.statFrames++
            if (root.statFrames > 2) {
                root.statWorst = Math.max(root.statWorst, frameTime)
            }
        }
    }

    Process {
        id: eligeProc
        property int targetGen: -1
        property string outLine: ""
        stdout: StdioCollector {
            onStreamFinished: eligeProc.outLine = text.trim()
        }
        onExited: (code) => {
            if (eligeProc.targetGen !== root.gen) return
            if (code === 0 && eligeProc.outLine) {
                const parts = eligeProc.outLine.split(/\s+/)
                if (parts.length >= 3) {
                    root.prepareMaps(parts[0], parts[1], parts[2])
                    return
                }
            }
            root.finish()
        }
    }

    Process {
        id: statusProc
        command: [root.wallfxBin, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const st = JSON.parse(text.trim())
                    if (st.wallsDir) {
                        root.detectedWallsDir = st.wallsDir
                    }
                    if (!st.venv) {
                        root.ensureVenv(true)
                    } else {
                        root.refreshThumbs()
                        root.warmTransitions()
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: installProc
        onExited: (code) => {
            if (code === 0) {
                ToastService.showInfo("WallFX", "Cutout environment ready! Warming wallpaper outlines in background.")
                root.refreshThumbs()
                root.warmTransitions()
            } else {
                ToastService.showError("WallFX", "Failed to set up Python environment (exit " + code + ")")
            }
        }
    }

    Process {
        id: thumbsProc
        onExited: {
            if (wallModel.count === 0) {
                wallModel.folder = ""
                wallModel.folder = "file://" + root.thumbsDir
            }
        }
    }

    Process {
        id: warmProc
    }

    Component.onCompleted: {
        root.currentWallpaper = SessionData.wallpaperPath || ""
        statusProc.running = true
    }

    // ─────────────────── 1. Shader Transition Overlay (WlrLayer.Bottom) ───────────────────
    Variants {
        id: fxScreens
        model: Quickshell.screens

        PanelWindow {
            id: fxWin
            required property var modelData
            screen: modelData
            visible: root.active
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "dms:wallfx"

            readonly property bool loaded: oldImg.status === Image.Ready
                && newImg.status === Image.Ready
                && fieldImg.status === Image.Ready
                && lineImg.status === Image.Ready

            onLoadedChanged: {
                if (loaded) root.screenReady()
            }

            // Keep current wallpaper preloaded so external changes hold the old frame in 0 ms
            Image {
                id: preloadOldImg
                anchors.fill: parent
                visible: root.active && root.externalSwap && !fxWin.loaded
                asynchronous: true
                cache: true
                source: (root.oldPath || root.currentWallpaper) ? "file://" + (root.oldPath || root.currentWallpaper) : ""
                sourceSize: Qt.size(fxWin.width, fxWin.height)
                fillMode: Image.PreserveAspectCrop
            }

            Image {
                id: oldImg
                visible: false
                asynchronous: true
                cache: false
                source: root.oldPath ? "file://" + root.oldPath : ""
                sourceSize: Qt.size(fxWin.width, fxWin.height)
                fillMode: Image.PreserveAspectCrop
            }

            Image {
                id: newImg
                visible: false
                asynchronous: true
                cache: false
                source: root.newPath ? "file://" + root.newPath : ""
                sourceSize: Qt.size(fxWin.width, fxWin.height)
                fillMode: Image.PreserveAspectCrop
            }

            Image {
                id: fieldImg
                visible: false
                asynchronous: true
                cache: false
                smooth: root.kind === "perfil"
                source: root.fieldPath ? "file://" + root.fieldPath : ""
            }

            Image {
                id: lineImg
                visible: false
                asynchronous: true
                cache: false
                source: root.linePath ? "file://" + root.linePath : ""
            }

            function crop(img) {
                const iw = Math.max(img.implicitWidth, 1)
                const ih = Math.max(img.implicitHeight, 1)
                const s = Math.max(fxWin.width / iw, fxWin.height / ih)
                const w = fxWin.width / (iw * s)
                const h = fxWin.height / (ih * s)
                return Qt.vector4d((1 - w) / 2, (1 - h) / 2, w, h)
            }

            ShaderEffect {
                anchors.fill: parent
                visible: fxWin.loaded
                opacity: root.fade
                property var oldTex: oldImg
                property var newTex: newImg
                property var fieldTex: fieldImg
                property var lineTex: lineImg
                property real t: root.t
                property real mode: root.kind === "perfil" ? 1 : 0
                property real sw: fxWin.width
                property real sh: fxWin.height
                property real fw: Math.max(fieldImg.implicitWidth, 1)
                property real fh: Math.max(fieldImg.implicitHeight, 1)
                property real lw: Math.max(lineImg.implicitWidth, 1)
                property real lh: Math.max(lineImg.implicitHeight, 1)
                property real glow: root.glow
                property real outlineGlow: root.outlineGlow
                property real lineW: root.lineW
                property real cellSize: root.cellSize
                property real parallax: root.parallax
                property real stageDim: root.stageDim
                property real tDrawStart: root.tDrawStart
                property real tDrawDur: root.tDrawDur
                property real tFillStart: root.tFillStart
                property real tFillDur: root.tFillDur
                property real tBgStart: root.tBgStart
                property real tBgDur: root.tBgDur
                property real sdRange: 16
                property real seed: root.seed
                property vector4d cropOld: fxWin.crop(oldImg)
                property vector4d cropNew: fxWin.crop(newImg)
                property color ember: root.ember
                property color ink: root.ink
                fragmentShader: Qt.resolvedUrl("shaders/wallfx.v16.frag.qsb")
            }
        }
    }

    // ─────────────────── 2. Skewed Coverflow Wallpaper Carousel (WlrLayer.Overlay) ───────────────────
    FolderListModel {
        id: wallModel
        folder: "file://" + root.thumbsDir
        nameFilters: ["*.jpg"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    PanelWindow {
        id: carouselWin
        visible: root.carouselOpen || stage.opacity > 0
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.carouselOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "dms:wallfx-carousel"

        Item {
            id: stage
            anchors.fill: parent
            focus: true
            opacity: root.carouselOpen ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: root.carouselOpen ? 210 : 120
                    easing.type: root.carouselOpen ? Easing.OutCubic : Easing.InCubic
                }
            }

            Connections {
                target: root
                function onCarouselOpenChanged() {
                    if (!root.carouselOpen) return
                    stage.forceActiveFocus()
                    root.refreshThumbs()
                    root.warmTransitions()
                }
            }

            Keys.onEscapePressed: root.carouselOpen = false
            Keys.onLeftPressed: carousel.decrementCurrentIndex()
            Keys.onRightPressed: carousel.incrementCurrentIndex()
            Keys.onReturnPressed: carousel.applyCurrent()
            Keys.onEnterPressed: carousel.applyCurrent()
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_H || event.key === Qt.Key_A) {
                    carousel.decrementCurrentIndex()
                    event.accepted = true
                } else if (event.key === Qt.Key_L || event.key === Qt.Key_D) {
                    carousel.incrementCurrentIndex()
                    event.accepted = true
                } else if (event.key === Qt.Key_R) {
                    if (wallModel.count > 0) {
                        carousel.currentIndex = Math.floor(Math.random() * wallModel.count)
                    }
                    event.accepted = true
                }
            }

            WheelHandler {
                onWheel: (e) => {
                    if (e.angleDelta.y > 0 || e.angleDelta.x > 0) carousel.decrementCurrentIndex()
                    else carousel.incrementCurrentIndex()
                }
            }

            // Subtle dark backdrop so skewed cards pop over any window
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.42)
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: root.carouselOpen = false
            }

            ListView {
                id: carousel
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: -10
                }
                height: 560
                orientation: ListView.Horizontal
                model: wallModel
                property real iw: 720
                property real ih: 406
                property real skew: -0.35
                property real bw: 3
                property real slotW: 360
                property real sideBase: 0.56
                readonly property real imgW: iw + ih * Math.abs(skew) + 12
                spacing: 0
                clip: false
                cacheBuffer: 2500
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - slotW) / 2
                preferredHighlightEnd: (width + slotW) / 2
                highlightMoveDuration: 420
                highlightMoveVelocity: 3000
                snapMode: ListView.SnapToItem
                boundsBehavior: Flickable.StopAtBounds
                maximumFlickVelocity: 6000

                function applyCurrent() {
                    if (currentIndex < 0 || wallModel.count <= currentIndex) return
                    const targetPath = root.originalOf(wallModel.get(currentIndex, "fileName"))
                    root.carouselOpen = false
                    root.triggerTransition(targetPath, false)
                }

                delegate: Item {
                    id: slot
                    width: carousel.slotW
                    height: carousel.height
                    readonly property real d: (x + width / 2 - (carousel.contentX + carousel.width / 2)) / carousel.slotW
                    readonly property real ad: Math.abs(d)
                    readonly property real sc: ad <= 1
                        ? carousel.sideBase + (1 - carousel.sideBase) * Math.pow(1 - ad, 1.35)
                        : carousel.sideBase * Math.pow(0.86, ad - 1)
                    z: Math.round(100 - ad * 10)
                    opacity: Math.max(0, Math.min(1, 1.15 - 0.34 * ad))

                    Item {
                        id: card
                        anchors.centerIn: parent
                        width: carousel.iw
                        height: carousel.ih
                        scale: slot.sc
                        transformOrigin: Item.Center
                        transform: Matrix4x4 {
                            matrix: Qt.matrix4x4(
                                1, carousel.skew, 0, -carousel.skew * carousel.ih / 2,
                                0, 1, 0, 0,
                                0, 0, 1, 0,
                                0, 0, 0, 1
                            )
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.surfaceContainer
                            border.width: slot.ad < 0.4 ? 2 : 1
                            border.color: slot.ad < 0.4 ? Theme.primary : Theme.outline
                        }

                        Item {
                            anchors.fill: parent
                            anchors.margins: carousel.bw
                            clip: true
                            Image {
                                anchors.centerIn: parent
                                width: carousel.imgW
                                height: carousel.ih
                                fillMode: Image.PreserveAspectCrop
                                source: model.fileUrl
                                asynchronous: true
                                cache: true
                                mipmap: true
                                sourceSize: Qt.size(carousel.imgW, carousel.ih)
                                transform: Matrix4x4 {
                                    matrix: Qt.matrix4x4(
                                        1, -carousel.skew, 0, carousel.skew * carousel.ih / 2,
                                        0, 1, 0, 0,
                                        0, 0, 1, 0,
                                        0, 0, 0, 1
                                    )
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: slot.ad < 0.5 ? carousel.applyCurrent() : (carousel.currentIndex = index)
                        }
                    }
                }
            }

            // Bottom HUD Pill showing current wallpaper filename, index, and keybind hints
            Rectangle {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 44
                }
                visible: wallModel.count > 0
                height: 42
                width: hudRow.implicitWidth + 36
                radius: 21
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.92)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.4)

                Row {
                    id: hudRow
                    anchors.centerIn: parent
                    spacing: 14

                    StyledText {
                        text: {
                            if (carousel.currentIndex < 0 || wallModel.count <= carousel.currentIndex) return ""
                            return String(wallModel.get(carousel.currentIndex, "fileName")).replace(/\.jpg$/, "")
                        }
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                    }

                    StyledText {
                        text: (carousel.currentIndex + 1) + " / " + wallModel.count
                        color: Theme.primary
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                    }

                    StyledText {
                        text: "←/→ browse  •  ↵ apply  •  R random  •  Esc close"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // Empty state
            StyledText {
                anchors.centerIn: parent
                visible: wallModel.count === 0
                text: thumbsProc.running
                    ? "Generating carousel thumbnails for " + root.wallsDir + "…"
                    : "No wallpapers found in " + root.wallsDir
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeLarge
            }
        }
    }
}
