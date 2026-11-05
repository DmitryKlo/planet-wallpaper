pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import ".."

Window {
    id: win
    function argument(name, fallback) {
        const prefix = "--" + name + "=";
        const value = Qt.application.arguments.find(item => item.startsWith(prefix));
        return value ? value.substring(prefix.length) : fallback;
    }
    width: Number(argument("width", "1280"))
    height: Number(argument("height", "720"))
    visible: true
    property int frame: 0
    readonly property int count: Number(argument("frames", "91"))
    readonly property real speed: Number(argument("speed", "10"))
    readonly property real fps: 15
    readonly property bool rotate: argument("rotate", "no") === "yes"
    readonly property string planet: argument("planet", "venus")
    readonly property string output: argument("output", "/tmp")
    readonly property real modelDay: planet === "venus" ? 345600 : 38520
    readonly property real delta: modelDay * speed / (360 * fps)

    Loader {
        id: scene
        anchors.fill: parent
        source: win.planet === "venus" ? "../Venus.qml" : "../Saturn.qml"
        onLoaded: {
            item.modelTimeSeconds = 0;
        }
    }
    Connections {
        target: scene.item ? scene.item.weatherModel : null
        function onStepCompleted(stepNumber) { capture.restart(); }
    }
    Timer {
        id: capture
        interval: 30
        onTriggered: {
            const planet = scene.item;
            if (!planet || !planet.ready || !planet.shaderReady || !planet.weatherReady) {
                capture.restart();
                return;
            }
            planet.grabToImage(result => {
                const path = win.output + "/frame-" + String(win.frame).padStart(4, "0") + ".png";
                if (!result.saveToFile(path)) { console.error("Capture failed", path); Qt.exit(1); return; }
                win.frame++;
                if (win.frame === win.count) {
                    console.warn("ATMOSPHERE_MOTION_RESULT", JSON.stringify({
                        planet: win.planet, frames: win.count, speed: win.speed,
                        fixedPhase: !win.rotate, physicalSecondsPerFrame: win.delta,
                        weather: planet.weatherModel.diagnostics
                    }));
                    Qt.quit();
                    return;
                }
                if (win.rotate) planet.phase = win.frame * win.speed / (360 * win.fps);
                planet.modelTimeSeconds = win.frame * win.delta;
                // Match the normal minimum step and clock synchronizer. A
                // display frame may reuse a retained field without forcing
                // the solver into a smaller, precision-losing time step.
                capture.restart();
            });
        }
    }
    Timer { interval: 90000; running: true; onTriggered: { console.error("Atmosphere render timeout"); Qt.exit(2); } }
}
