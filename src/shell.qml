pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property var options: ({})
    property var wallpaperMap: ({})
    property var desktopSettings: ({})
    property var panels: []
    property real phase: 0
    readonly property real cloudPhase: phase
    // Independent time keeps cloud evolution continuous across an Earth turn.
    property double cloudTime: 0
    property double modelTimeSeconds: 0
    readonly property bool weatherEnabled: options.weatherEnabled !== false
    readonly property real speed: Math.min(10, Math.max(0.1, Number(options.speed) || 1))
    property bool paused: false
    property double lastTick: Date.now()
    readonly property string imagePath: options.image || ""
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"
    readonly property real periodSeconds: Math.max(30, Number(options.periodSeconds) || 360)
    readonly property int framesPerSecond: Math.min(60, Math.max(1, Number(options.framesPerSecond) || 30))
    readonly property bool hasVisiblePanel: panels.some(panel => panel.visible)

    function readObject(file, previous) {
        try {
            return JSON.parse(file.text());
        } catch (error) {
            console.warn("Planet wallpaper: keeping previous settings:", error);
            return previous;
        }
    }

    function selectedOn(screenName) {
        if (options.enabled === false)
            return false;
        // Standalone primary wallpaper is the default. Noctalia integration
        // is optional and never requires shipping a user's desktop settings.
        if (options.followNoctaliaWallpaper !== true)
            return true;
        const settings = desktopSettings.wallpaper;
        if (!settings || !settings.enabled || settings.useSolidColor)
            return false;
        // The effect is calibrated for this artwork and crop mode only.
        if (settings.fillMode !== "crop")
            return false;
        const entries = wallpaperMap.wallpapers || {};
        const entry = entries[screenName] || entries[""] || {};
        const mode = desktopSettings.colorSchemes?.darkMode === false ? "light" : "dark";
        return entry[mode] === imagePath;
    }

    FileView {
        id: configFile
        path: Qt.resolvedUrl("settings.json").toString().replace("file://", "")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.options = root.readObject(configFile, root.options)
    }

    Loader {
        active: root.options.followNoctaliaWallpaper === true
        sourceComponent: Item {
            FileView {
                id: wallpapersFile
                path: root.cacheHome + "/noctalia/wallpapers.json"
                watchChanges: true
                onFileChanged: reload()
                onLoaded: root.wallpaperMap = root.readObject(wallpapersFile, root.wallpaperMap)
            }
            FileView {
                id: desktopFile
                path: root.configHome + "/noctalia/settings.json"
                watchChanges: true
                onFileChanged: reload()
                onLoaded: root.desktopSettings = root.readObject(desktopFile, root.desktopSettings)
            }
        }
    }

    Timer {
        interval: Math.round(1000 / root.framesPerSecond)
        running: root.hasVisiblePanel && !root.paused
        repeat: true
        onRunningChanged: root.lastTick = Date.now()
        onTriggered: {
            const now = Date.now();
            // Suspension or a compositor stall must not produce a huge jump.
            const elapsed = Math.min(0.25, (now - root.lastTick) / 1000);
            root.lastTick = now;
            root.phase = (root.phase + elapsed * root.speed / root.periodSeconds) % 1;
            root.cloudTime += elapsed * root.speed;
            root.modelTimeSeconds += elapsed * root.speed * 86400 / root.periodSeconds;
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property ShellScreen modelData
            // Both optional components provide the same small render interface.
            readonly property var currentScene: scene.item
            screen: modelData
            // Shader compilation needs the first visible frame.
            visible: root.selectedOn(modelData.name) && currentScene !== null
                     && currentScene.ready
            color: "transparent"
            anchors { top: true; right: true; bottom: true; left: true }
            exclusionMode: ExclusionMode.Ignore
            // Niri can place only Background surfaces in its stationary
            // backdrop. Bottom follows each workspace and exposes the static
            // fallback between workspaces during a switch.
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "noctalia-wallpaper-planet-" + modelData.name
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            Component.onCompleted: root.panels = root.panels.concat([panel])
            Component.onDestruction: root.panels = root.panels.filter(item => item !== panel)

            Loader {
                id: scene
                anchors.fill: parent
                sourceComponent: root.options.view === "venus" ? venusScene : earthScene
            }
            Component {
                id: earthScene
                Planet {
                    imagePath: root.imagePath ? "file://" + root.imagePath : ""
                    phase: root.phase
                    cloudPhase: root.cloudPhase
                    cloudTime: root.cloudTime
                    rotationPeriodSeconds: root.periodSeconds
                    modelTimeSeconds: root.modelTimeSeconds
                    weatherEnabled: root.weatherEnabled
                    planetVisualVersion: root.options.planetVisualVersion === 6 ? 6 : 8
                    fullGlobe: root.options.view === "globe" ? 1 : 0
                    cloudAmount: root.options.cloudAmount === undefined ? 0.90
                                 : Math.max(0, Math.min(1, Number(root.options.cloudAmount)))
                    surfaceSoftness: root.options.surfaceSoftness === undefined ? 0.85
                                     : Math.max(0, Math.min(2.5, Number(root.options.surfaceSoftness)))
                    cityGlow: root.options.cityGlow === undefined ? 0.50
                              : Math.max(0, Math.min(0.8, Number(root.options.cityGlow)))
                }
            }
            Component {
                id: venusScene
                Venus {
                    phase: root.phase
                    cloudTime: root.cloudTime
                }
            }

            function snapshot(path) {
                if (!currentScene)
                    return;
                currentScene.grabToImage(result => {
                    console.log("Planet snapshot", result.saveToFile(path), path);
                });
            }
            function diagnostics() { return currentScene ? currentScene.diagnostics : {ready: false}; }
        }
    }

    IpcHandler {
        target: "planet"
        function pause(): void { root.paused = true; }
        function resume(): void { root.paused = false; }
        function speed(value: string): string {
            const number = Number(value);
            if (!Number.isFinite(number) || number < 0.1 || number > 10)
                return "Speed must be between 0.1 and 10";
            root.options = Object.assign({}, root.options, {speed: number});
            configFile.setText(JSON.stringify(root.options, null, 2) + "\n");
            return "Speed: " + number;
        }
        function view(value: string): string {
            if (value !== "horizon" && value !== "globe" && value !== "venus")
                return "View must be horizon, globe or venus";
            root.options = Object.assign({}, root.options, {view: value});
            configFile.setText(JSON.stringify(root.options, null, 2) + "\n");
            return "View: " + value;
        }
        function weather(value: string): string {
            if (value === "status")
                return "Weather model: " + (root.weatherEnabled ? "on" : "off");
            if (value !== "on" && value !== "off" && value !== "toggle")
                return "Weather must be on, off, toggle or status";
            const enabled = value === "toggle" ? !root.weatherEnabled : value === "on";
            root.options = Object.assign({}, root.options, {weatherEnabled: enabled});
            configFile.setText(JSON.stringify(root.options, null, 2) + "\n");
            return "Weather model: " + (enabled ? "on" : "off");
        }
        function seek(value: string): string {
            const number = Number(value);
            if (!Number.isFinite(number))
                return "Phase must be a number";
            root.phase = ((number % 1) + 1) % 1;
            root.cloudTime = root.phase * root.periodSeconds;
            root.modelTimeSeconds = root.phase * 86400;
            root.panels.forEach(panel => {
                if (panel.currentScene && typeof panel.currentScene.resetWeather === "function")
                    panel.currentScene.resetWeather();
            });
            return "Phase: " + root.phase;
        }
        function snapshot(path: string): string {
            const panel = root.panels.find(item => item.visible);
            if (!panel || !path.startsWith("/"))
                return "No visible wallpaper or path is not absolute";
            panel.snapshot(path);
            return "Saving " + path;
        }
        function status(): string {
            return JSON.stringify({
                paused: root.paused, phase: root.phase, cloudPhase: root.cloudPhase,
                backgroundMode: root.options.followNoctaliaWallpaper === true ? "follow-noctalia" : "primary",
                cloudTime: root.cloudTime, modelTimeSeconds: root.modelTimeSeconds,
                weatherEnabled: root.weatherEnabled,
                planetVisualVersion: root.options.planetVisualVersion === 6 ? 6 : 8,
                modelDaySeconds: 86400, modelSecondsPerAnimationSecond: 86400 / root.periodSeconds,
                speed: root.speed,
                periodSeconds: root.periodSeconds, framesPerSecond: root.framesPerSecond,
                view: root.options.view || "horizon",
                renderer: root.options.view === "venus" ? "venus-prototype" : "weather-layers-v8",
                screens: root.panels.filter(item => item.visible).map(item => item.modelData.name),
                rendering: root.panels.map(item => item.diagnostics())
            });
        }
    }
}
