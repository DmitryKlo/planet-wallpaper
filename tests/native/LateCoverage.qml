pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import ".."

Window {
    id: win
    width: 960
    height: 540
    visible: true
    property bool sampling: false
    property int frame: 0
    property int checkpoint: 0
    readonly property var checkpoints: [1, 361, 2161]
    readonly property string output: "@TEST_OUTPUT@/late-coverage/"

    Planet {
        id: planet
        anchors.fill: parent
        phase: win.frame >= 48 ? 0.614025 : (win.frame % 24) / 24
        fullGlobe: win.frame < 24 || win.frame === 48 ? 1 : 0
        diagnosticMode: win.frame >= 48 ? 0 : 1
        cityGlow: 0.28
        modelTimeSeconds: 0
    }
    Connections {
        target: planet.weatherModel
        function onStepCompleted(stepNumber) { progress.restart(); }
    }
    Timer {
        id: progress
        interval: 1
        onTriggered: {
            if (planet.weatherModel.stepCount < win.checkpoints[win.checkpoint])
                planet.weatherModel.advanceFixedStep();
            else
                win.sampling = true;
        }
    }
    Timer {
        id: capture
        interval: 70
        running: win.sampling && planet.ready && planet.shaderReady && planet.weatherReady
        onTriggered: planet.grabToImage(result => {
            const prefix = "step-" + win.checkpoints[win.checkpoint] + "-";
            const name = prefix + (win.frame >= 48
                ? (win.frame === 48 ? "preview-globe.png" : "preview-horizon.png")
                : (win.frame < 24 ? "globe-" : "horizon-") + String(win.frame % 24).padStart(2,"0") + ".png");
            if (!result.saveToFile(win.output + name)) { Qt.exit(1); return; }
            if (win.frame === 49) {
                win.sampling = false;
                win.checkpoint++;
                if (win.checkpoint === win.checkpoints.length) { Qt.quit(); return; }
                win.frame = 0;
                planet.weatherModel.advanceFixedStep();
                return;
            }
            win.frame++;
            capture.restart();
        })
    }
    Timer { interval: 150000; running: true; onTriggered: Qt.exit(2) }
}
