pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

Window {
    id: window
    function argument(name, fallback) {
        const prefix = "--" + name + "=";
        const match = Qt.application.arguments.find(arg => arg.startsWith(prefix));
        return match ? match.substring(prefix.length) : fallback;
    }
    width: Number(argument("width", "1920"))
    height: Number(argument("height", "1080"))
    visible: true
    color: "black"
    title: "Earth rotation renderer"
    property int frame: 0
    readonly property int count: Number(argument("frames", "1"))
    readonly property real span: Number(argument("span", "1"))
    readonly property real start: Number(argument("start", "0"))
    readonly property string output: argument("output", "/tmp")

    Planet {
        id: planet
        anchors.fill: parent
        phase: window.start + window.span * window.frame / window.count
        fullGlobe: Number(window.argument("globe", "0"))
        cloudAmount: Number(window.argument("clouds", "0.90"))
        cloudPhase: phase
        cloudType: Number(window.argument("cloud-type", "0"))
        weatherEnabled: window.argument("weather", "on") !== "off"
        planetVisualVersion: Number(window.argument("visual-version", "6"))
        cloudTime: Number(window.argument("cloud-time", "0")) + Number(window.argument("cloud-span", String(window.span * 360))) * window.frame / window.count
        diagnosticMode: Number(window.argument("diagnostic", "0"))
        surfaceSoftness: Number(window.argument("softness", "0.85"))
        cityGlow: Number(window.argument("glow", "0.28"))
        sunTipBoost: Number(window.argument("sun-tip-boost", "0.16"))
    }
    Timer {
        id: capture
        interval: 60
        running: planet.ready && planet.shaderReady && planet.weatherReady
        repeat: false
        onTriggered: {
            const path = window.output + "/frame-" + String(window.frame).padStart(4, "0") + ".png";
            planet.grabToImage(result => {
                if (!result.saveToFile(path)) {
                    console.error("Could not write", path);
                    Qt.exit(1);
                    return;
                }
                if (window.frame % 30 === 0)
                    console.log("Rendered", window.frame + 1, "of", window.count);
                window.frame++;
                if (window.frame >= window.count) {
                    console.log("Finished", window.count, "frames");
                    Qt.quit();
                } else {
                    capture.restart();
                }
            });
        }
    }
    Timer {
        interval: 60000
        running: !planet.ready || !planet.shaderReady
        onTriggered: { console.error("Texture loading timeout"); Qt.exit(2); }
    }
}
