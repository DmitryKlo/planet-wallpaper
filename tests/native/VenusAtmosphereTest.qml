pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import ".."

Window {
    id: win
    width: 768
    height: 384
    visible: true
    property string output: "@TEST_OUTPUT@/venus"
    property int stage: 0
    property int advances: 0
    property real frozenEvolution: 0
    property real frozenSimulated: 0
    property int frozenSteps: 0

    function check(condition, message) {
        if (!condition) {
            console.error("VENUS ATMOSPHERE FAILED:", message, JSON.stringify(atmosphere.diagnostics));
            Qt.exit(1);
            return false;
        }
        return true;
    }
    function capture(name, next) {
        view.grabToImage(result => {
            if (!win.check(result.saveToFile(output + "/" + name + ".png"), "save " + name)) return;
            next();
        });
    }

    VenusAtmosphere {
        id: atmosphere
        automatic: false
        simulationEnabled: false
        // 32 fixed steps make four simulated hours while keeping the test short.
        rotationPeriodSeconds: 96
    }
    ShaderEffect {
        id: view
        anchors.fill: parent
        property variant field: atmosphere.stateTexture
        fragmentShader: Qt.resolvedUrl("venus-state-display.frag.qsb")
    }
    Connections {
        target: atmosphere
        function onStepCompleted(stepNumber) {
            if (win.stage === 0) progress.restart();
            else if (win.stage === 2) {
                win.advances++;
                if (win.advances < 32) atmosphere.advanceFixedStep();
                else progress.restart();
            }
        }
    }
    Timer {
        id: progress
        interval: 30
        onTriggered: {
            if (win.stage === 0) {
                if (!win.check(atmosphere.ready && atmosphere.seedReady && !atmosphere.stepPending
                               && atmosphere.stepCount === 1 && atmosphere.evolutionTime === 0,
                               "disabled instance must create its deterministic seed")) return;
                win.capture("seed-a", () => {
                    win.stage = 1;
                    atmosphere.requestReset(0);
                    resetWait.restart();
                });
            } else if (win.stage === 1) {
                // resetWait owns the asynchronous reset completion.
            } else if (win.stage === 2) {
                if (!win.check(atmosphere.evolutionTime >= 4 * 3600
                               && atmosphere.simulatedTime >= 4 * 3600,
                               "four hours of visible cloud evolution did not accrue")) return;
                win.capture("after-four-hours", () => {
                    win.stage = 3;
                    win.frozenEvolution = atmosphere.evolutionTime;
                    win.frozenSimulated = atmosphere.simulatedTime;
                    win.frozenSteps = atmosphere.stepCount;
                    atmosphere.simulationEnabled = false;
                    atmosphere.timeSeconds += 86400;
                    progress.restart();
                });
            } else if (win.stage === 3) {
                if (!win.check(atmosphere.stepCount === win.frozenSteps
                               && atmosphere.simulatedTime === win.frozenSimulated
                               && atmosphere.evolutionTime === win.frozenEvolution
                               && !atmosphere.advanceFixedStep(),
                               "weather-off must freeze state and reject manual steps")) return;
                win.capture("weather-off", () => {
                    win.stage = 4;
                    atmosphere.automatic = true;
                    atmosphere.simulationEnabled = true;
                    progress.restart();
                });
            } else if (win.stage === 4) {
                if (!win.check(atmosphere.stepCount === win.frozenSteps
                               && atmosphere.evolutionTime === win.frozenEvolution
                               && atmosphere.simulatedTime === atmosphere.timeSeconds,
                               "resume must preserve the field without replaying disabled time")) return;
                win.capture("resumed-no-jump", () => {
                    win.stage = 5;
                    atmosphere.automatic = true;
                    atmosphere.timeSeconds += 10 * 3600;
                    speedWait.restart();
                });
            }
        }
    }
    Timer {
        id: resetWait
        interval: 30
        onTriggered: {
            if (atmosphere.stepPending || atmosphere.stepCount !== 1) { restart(); return; }
            win.capture("seed-b", () => {
                win.stage = 2;
                atmosphere.simulationEnabled = true;
                if (!win.check(atmosphere.advanceFixedStep(), "enabled solver rejected first step")) return;
            });
        }
    }
    Timer {
        id: speedWait
        interval: 30
        repeat: true
        onTriggered: {
            if (atmosphere.stepPending || atmosphere.simulatedTime < atmosphere.timeSeconds - 0.01) return;
            if (!win.check(atmosphere.evolutionTime >= win.frozenEvolution + 10 * 3600,
                           "10x requested time did not advance cloud evolution")) return;
            win.capture("ten-times-time", () => {
                console.warn("VENUS ATMOSPHERE PASSED", JSON.stringify({
                    fourHourEvolution: win.frozenEvolution,
                    tenXEvolution: atmosphere.evolutionTime,
                    diagnostics: atmosphere.diagnostics
                }));
                Qt.quit();
            });
        }
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: {
            console.error("VENUS ATMOSPHERE TIMEOUT", win.stage,
                          JSON.stringify(atmosphere.diagnostics));
            Qt.exit(2);
        }
    }
}
