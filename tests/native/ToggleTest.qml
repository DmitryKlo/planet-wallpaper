import QtQuick
import QtQuick.Window
import ".."

Window {
    id: win
    width: 2304
    height: 384
    visible: true
    property string output: "@TEST_OUTPUT@/toggle"
    property int stage: 0
    property int heldSteps: 0
    property real heldTime: 0
    property real heldEvolutionTime: 0

    function check(condition, message) {
        if (!condition) {
            console.error("WEATHER TOGGLE FAILED:", message, JSON.stringify(sim.diagnostics));
            Qt.exit(1);
        }
        return condition;
    }
    function capture(name, next) {
        view.grabToImage(result => {
            if (!check(result.saveToFile(output + "/" + name + ".png"), "save " + name))
                return;
            next();
        });
    }

    CloudSimulation {
        id: sim
        simulationEnabled: false
    }
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
        function onStepCompleted(stepNumber) {
            if (win.stage === 0 || win.stage === 3)
                progress.restart();
        }
    }
    Timer {
        id: progress
        interval: 250
        onTriggered: {
            if (win.stage === 0) {
                if (!win.check(sim.ready && !sim.stepPending && sim.stepCount === 1,
                               "disabled startup must seed exactly once")) return;
                win.heldSteps = sim.stepCount;
                win.heldTime = sim.simulatedTime;
                win.heldEvolutionTime = sim.evolutionTime;
                win.capture("disabled-initial", () => {
                    win.stage = 1;
                    sim.timeSeconds = 86400;
                    if (!win.check(!sim.advanceFixedStep(), "manual step must respect off")) return;
                    progress.restart();
                });
            } else if (win.stage === 1) {
                if (!win.check(!sim.stepPending && sim.stepCount === win.heldSteps
                               && sim.simulatedTime === win.heldTime
                               && sim.evolutionTime === win.heldEvolutionTime,
                               "disabled solver advanced after a day elapsed")) return;
                win.capture("disabled-after-day", () => {
                    win.stage = 2;
                    sim.simulationEnabled = true;
                    progress.restart();
                });
            } else if (win.stage === 2) {
                if (!win.check(!sim.stepPending && sim.stepCount === win.heldSteps
                               && sim.simulatedTime === 86400
                               && sim.evolutionTime === win.heldEvolutionTime,
                               "resume reset clouds or replayed missed time")) return;
                win.capture("enabled-before-step", () => {
                    win.stage = 3;
                    sim.timeSeconds += sim.fixedStep;
                });
            } else if (win.stage === 3) {
                if (!win.check(sim.ready && !sim.stepPending && sim.stepCount === win.heldSteps + 1,
                               "enabled solver did not resume")) return;
                win.capture("enabled-after-step", () => {
                    console.warn("WEATHER TOGGLE PASSED", JSON.stringify(sim.diagnostics));
                    Qt.quit();
                });
            }
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { console.error("WEATHER TOGGLE TIMEOUT", win.stage); Qt.exit(2); }
    }
}
