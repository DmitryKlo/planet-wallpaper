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
    readonly property real modelDaySeconds: options.view === "venus" ? 345600
                                           : options.view === "saturn" ? 38520 : 86400
    readonly property double activeModelTimeSeconds: options.view === "venus" || options.view === "saturn"
        ? cloudTime * modelDaySeconds / periodSeconds : modelTimeSeconds
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
            // Every planet provides the same small render interface.
            readonly property string selectedScene: root.options.view === "venus" ? "venus"
                                                   : root.options.view === "saturn" ? "saturn" : "earth"
            readonly property var currentScene: selectedScene === "venus" ? venusLoader.item
                                               : selectedScene === "saturn" ? saturnLoader.item : earthLoader.item
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
                id: earthLoader
                anchors.fill: parent
                property bool retained: false
                readonly property bool selected: panel.selectedScene === "earth"
                // Keep texture providers alive after a visit. Destroying a
                // recursive feedback source during a view switch can race
                // Qt's render thread. Hidden solvers retain their last fields.
                active: selected || retained
                visible: selected
                onSelectedChanged: if (selected) retained = true
                Component.onCompleted: if (selected) retained = true
                sourceComponent: earthScene
            }
            Loader {
                id: venusLoader
                anchors.fill: parent
                property bool retained: false
                readonly property bool selected: panel.selectedScene === "venus"
                active: selected || retained
                visible: selected
                onSelectedChanged: if (selected) retained = true
                Component.onCompleted: if (selected) retained = true
                sourceComponent: venusScene
            }
            Loader {
                id: saturnLoader
                anchors.fill: parent
                property bool retained: false
                readonly property bool selected: panel.selectedScene === "saturn"
                active: selected || retained
                visible: selected
                onSelectedChanged: if (selected) retained = true
                Component.onCompleted: if (selected) retained = true
                sourceComponent: saturnScene
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
                    weatherEnabled: root.weatherEnabled && panel.selectedScene === "earth"
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
                    rotationPeriodSeconds: root.periodSeconds
                    modelTimeSeconds: root.cloudTime * 345600 / root.periodSeconds
                    weatherEnabled: root.weatherEnabled && panel.selectedScene === "venus"
                }
            }
            Component {
                id: saturnScene
                Saturn {
                    phase: root.phase
                    cloudTime: root.cloudTime
                    rotationPeriodSeconds: root.periodSeconds
                    modelTimeSeconds: root.cloudTime * 38520 / root.periodSeconds
                    weatherEnabled: root.weatherEnabled && panel.selectedScene === "saturn"
                }
            }

            function snapshot(path) {
                if (!currentScene)
                    return;
                currentScene.grabToImage(result => {
                    console.log("Planet snapshot", result.saveToFile(path), path);
                });
            }
            function cachedScenes() {
                return [earthLoader.item, venusLoader.item, saturnLoader.item].filter(item => item !== null);
            }
            function resetAllWeather() {
                cachedScenes().forEach(item => item.resetWeather());
            }
            function diagnostics() {
                if (!currentScene) return {ready: false};
                return Object.assign({}, currentScene.diagnostics, {
                    cachedWeather: cachedScenes().map(item => ({
                        renderer: item.diagnostics.renderer,
                        enabled: item.diagnostics.weather.enabled,
                        stepPending: item.diagnostics.weather.stepPending,
                        stepCount: item.diagnostics.weather.stepCount,
                        evolutionTime: item.diagnostics.weather.evolutionTime
                    }))
                });
            }
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
            if (value !== "horizon" && value !== "globe" && value !== "venus" && value !== "saturn")
                return "View must be horizon, globe, venus or saturn";
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
                panel.resetAllWeather();
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
                cloudTime: root.cloudTime, modelTimeSeconds: root.activeModelTimeSeconds,
                weatherEnabled: root.weatherEnabled,
                planetVisualVersion: root.options.planetVisualVersion === 6 ? 6 : 8,
                modelDaySeconds: root.modelDaySeconds,
                modelSecondsPerAnimationSecond: root.modelDaySeconds / root.periodSeconds,
                speed: root.speed,
                periodSeconds: root.periodSeconds, framesPerSecond: root.framesPerSecond,
                view: root.options.view || "horizon",
                renderer: root.options.view === "venus" ? "venus-retained-atmosphere-v1"
                          : root.options.view === "saturn" ? "saturn-rings-atmosphere" : "weather-layers-v8",
                screens: root.panels.filter(item => item.visible).map(item => item.modelData.name),
                rendering: root.panels.map(item => item.diagnostics())
            });
        }
    }
}
