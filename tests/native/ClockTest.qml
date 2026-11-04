pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import ".."

Window {
    id: win
    width: 2304
    height: 384
    visible: true
    function argument(name, fallback) {
        const match=Qt.application.arguments.find(a => a.startsWith("--"+name+"="));
        return match ? match.substring(name.length+3) : fallback;
    }
    readonly property real speed: Number(argument("speed", "10"))
    readonly property string output: argument("output", "/tmp")
    property bool started: false
    property bool ending: false
    property double startedAt: 0
    property var checkpoints: [0,1,3,6,12]
    property int checkpoint: 0
    property int previousSteps: 0
    property var observations: []
    property real maximumLag: 0

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
        function onStepCompleted(stepNumber) {
            if(win.previousSteps >= stepNumber) { console.error("UNEXPECTED RESET"); Qt.exit(1); return; }
            win.previousSteps=stepNumber;
            if(!win.started) {
                win.started=true;
                win.startedAt=Date.now();
                captures.restart();
                clock.start();
            }
            if(win.ending) finish.restart();
        }
    }
    Timer {
        id: clock
        interval: 33
        repeat: true
        onTriggered: {
            const elapsed=(Date.now()-win.startedAt)/1000;
            sim.timeSeconds=Math.min(elapsed,12)*240*win.speed;
            win.maximumLag=Math.max(win.maximumLag,sim.timeSeconds-sim.simulatedTime);
            if(elapsed>=12) {
                clock.stop();
                captures.stop();
                win.ending=true;
                finish.restart();
            }
        }
    }
    Timer {
        id: captures
        interval: 50
        repeat: true
        onTriggered: {
            const elapsed=(Date.now()-win.startedAt)/1000;
            if(win.checkpoint >= win.checkpoints.length-1 || elapsed<win.checkpoints[win.checkpoint]) return;
            const stamp=win.checkpoints[win.checkpoint++];
            view.grabToImage(result => {
                if(!result.saveToFile(win.output+"/second-"+stamp+".png")) { Qt.exit(1); return; }
                win.observations.push({wallSecond:stamp,weather:sim.diagnostics});
            });
        }
    }
    Timer {
        id: finish
        interval: 100
        onTriggered: {
            if(sim.stepPending || sim.timeSeconds-sim.simulatedTime>=sim.fixedStep) { finish.restart(); return; }
            view.grabToImage(result => {
                if(!result.saveToFile(win.output+"/second-12.png")) { Qt.exit(1); return; }
                console.warn("CLOCK_RESULT",JSON.stringify({speed:win.speed,maximumLag:win.maximumLag,
                    requestedTime:sim.timeSeconds,final:sim.diagnostics,observations:win.observations}));
                Qt.quit();
            });
        }
    }
    Timer { interval: 30000; running: true; onTriggered: Qt.exit(2) }
}
