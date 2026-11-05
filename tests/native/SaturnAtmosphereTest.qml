import QtQuick
import QtQuick.Window
import ".."

Window {
    id: win
    width: 768
    height: 384
    visible: true
    property string output: "@TEST_OUTPUT@/saturn"
    property int stage: 0
    property int evolvedSteps: 0
    property real heldEvolution: 0
    property real heldSimulated: 0
    property real heldClock: 0

    function check(condition, message) {
        if (!condition) {
            console.error("SATURN ATMOSPHERE FAILED:", message, JSON.stringify(sim.diagnostics));
            Qt.exit(1);
            return false;
        }
        return true;
    }
    function capture(name, next) {
        view.grabToImage(result => {
            if (!win.check(result.saveToFile(output + "/" + name + ".png"), "save " + name))
                return;
            next();
        });
    }
    function advance() {
        if (evolvedSteps >= 12) {
            if (!check(sim.evolutionTime >= 6 * 3600,
                       "field should have evolved for multiple hours")) return;
            stage = 3;
            heldEvolution = sim.evolutionTime;
            heldSimulated = sim.simulatedTime;
            sim.simulationEnabled = false;
            sim.timeSeconds = 86400;
            pauseCheck.restart();
            return;
        }
        if (!check(sim.advanceFixedStep(), "explicit atmosphere step rejected")) return;
    }

    SaturnAtmosphere {
        id: sim
        simulationEnabled: false
        automatic: false
        // A 38520-second fixed step bounds the long-run state check to 12 draws.
        rotationPeriodSeconds: 1
    }
    ShaderEffect {
        id: view
        anchors.fill: parent
        property variant stateTexture: sim.stateTexture
        fragmentShader: Qt.resolvedUrl("saturn-state-display.frag.qsb")
    }
    Connections {
        target: sim
        function onStepCompleted(stepNumber) {
            if (win.stage === 0) {
                if (!win.check(sim.ready && stepNumber === 1,
                               "disabled startup must seed the retained state once")) return;
                win.capture("seed", () => {
                    win.stage = 1;
                    if (!win.check(sim.reset(0), "deterministic reset rejected")) return;
                });
            } else if (win.stage === 1) {
                if (!win.check(stepNumber === 1 && sim.evolutionTime === 0,
                               "reset must produce a fresh deterministic seed")) return;
                win.capture("reset-seed", () => {
                    win.stage = 2;
                    sim.simulationEnabled = true;
                    win.advance();
                });
            } else if (win.stage === 2) {
                win.evolvedSteps++;
                if (win.evolvedSteps === 12)
                    win.capture("evolved", () => win.advance());
                else win.advance();
            } else if (win.stage === 4) {
                if (!win.check(sim.evolutionTime === win.heldEvolution
                               && sim.simulatedTime === win.heldSimulated,
                               "resume must rebase clock without changing retained state time")) return;
                win.capture("resumed", () => {
                    win.stage = 5;
                    sim.automatic = true;
                    win.heldClock = sim.timeSeconds;
                    sim.timeSeconds += sim.fixedStep * 10;
                    x10Check.restart();
                });
            }
        }
    }
    Timer {
        id: pauseCheck
        interval: 50
        onTriggered: {
            if (sim.stepPending) { pauseCheck.restart(); return; }
            if (!win.check(sim.evolutionTime === win.heldEvolution
                           && sim.simulatedTime === win.heldSimulated
                           && sim.stepCount === 13,
                           "disabled clock advance must freeze texture and evolution")) return;
            win.capture("paused", () => {
                win.stage = 4;
                sim.automatic = true;
                sim.simulationEnabled = true;
                if (!win.check(sim.simulatedTime === 86400
                               && sim.evolutionTime === win.heldEvolution,
                               "resume must rebase without catch-up or reset")) return;
                win.capture("resumed", () => {
                    win.stage = 5;
                    win.heldClock = sim.timeSeconds;
                    sim.timeSeconds += sim.fixedStep * 10;
                    x10Check.restart();
                });
            });
        }
    }
    Timer {
        id: x10Check
        interval: 50
        onTriggered: {
            if (sim.stepPending || sim.timeSeconds - sim.simulatedTime >= sim.fixedStep) {
                x10Check.restart();
                return;
            }
            if (!win.check(Math.abs(sim.timeSeconds - (win.heldClock + sim.fixedStep * 10)) < 0.01
                           && sim.evolutionTime > win.heldEvolution,
                           "x10 clock target should advance the retained atmosphere over time")) return;
            view.grabToImage(result => {
                if (!result.saveToFile(win.output + "/x10.png")) { Qt.exit(1); return; }
                console.warn("SATURN ATMOSPHERE PASSED", JSON.stringify({
                    diagnostics: sim.diagnostics, evolutionHours: sim.evolutionTime / 3600,
                    x10ClockAdvance: sim.timeSeconds - win.heldClock
                }));
                Qt.quit();
            });
        }
    }
    Timer {
        interval: 30000
        running: true
        onTriggered: { console.error("SATURN ATMOSPHERE TIMEOUT", win.stage); Qt.exit(2); }
    }
}
