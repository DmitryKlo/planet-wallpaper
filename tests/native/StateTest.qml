import QtQuick
import QtQuick.Window
import ".."

Window {
    id: win
    width: 2304
    height: 384
    visible: true
    property string output: "@TEST_OUTPUT@/model"
    property var checkpoints: [1, 2, 3, 11, 121, 361]
    property int checkpoint: 0
    property bool resetDone: false
    CloudSimulation { id: sim }
    ShaderEffect {
        id: view
        anchors.fill: parent
        property variant low: sim.textureLow
        property variant high: sim.textureHigh
        property variant climate: sim.climateTexture
        fragmentShader: Qt.resolvedUrl("state-display.frag.qsb")
    }
    Connections {
        target: sim
        function onStepCompleted(stepNumber) { progress.restart(); }
    }
    Timer {
        id: progress
        interval: 20
        onTriggered: {
            if (win.resetDone) {
                view.grabToImage(result => {
                    if (!result.saveToFile(win.output + "/reset.png")) { Qt.exit(1); return; }
                    console.log("MODEL", JSON.stringify(sim.diagnostics));
                    Qt.quit();
                });
                return;
            }
            if (sim.stepCount === win.checkpoints[win.checkpoint]) {
                const path = win.output + "/step-" + sim.stepCount + ".png";
                view.grabToImage(result => {
                    if (!result.saveToFile(path)) { Qt.exit(1); return; }
                    win.checkpoint++;
                    if (win.checkpoint === win.checkpoints.length) {
                        win.resetDone = true;
                        sim.reset(0);
                    } else sim.advanceFixedStep();
                });
            } else sim.advanceFixedStep();
        }
    }
    Timer {
        interval: 120000
        running: true
        onTriggered: { console.error("TIMEOUT", JSON.stringify(sim.diagnostics)); Qt.exit(2); }
    }
}
