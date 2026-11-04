pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import ".."

Window {
    id: win
    function argument(name, fallback) {
        const match=Qt.application.arguments.find(a => a.startsWith("--"+name+"="));
        return match ? match.substring(name.length+3) : fallback;
    }
    width: 1920
    height: 1080
    visible: true
    property int frame: 0
    readonly property int count: Number(argument("frames", "181"))
    readonly property real modelStep: Number(argument("step", "160"))
    readonly property bool rotate: argument("rotate", "no") === "yes"
    readonly property string output: argument("output", "/tmp")

    Planet {
        id: planet
        anchors.fill: parent
        phase: win.rotate ? win.frame*win.modelStep/86400 : 0
        fullGlobe: 1
        cityGlow: .28
        modelTimeSeconds: 0
    }
    Connections {
        target: planet.weatherModel
        function onStepCompleted(stepNumber) {
            planet.weatherModel.automatic=false;
            capture.restart();
        }
    }
    Timer {
        id: capture
        interval: 25
        onTriggered: {
            if(!planet.ready || !planet.shaderReady || !planet.weatherReady) {
                capture.restart();
                return;
            }
            planet.grabToImage(result => {
                const name="frame-"+String(win.frame).padStart(4,"0")+".png";
                if(!result.saveToFile(win.output+"/"+name)) { Qt.exit(1); return; }
                win.frame++;
                if(win.frame === win.count) { Qt.quit(); return; }
                planet.weatherModel.scheduleStep(planet.weatherModel.simulatedTime+win.modelStep,false);
            });
        }
    }
    Timer { interval: 120000; running: true; onTriggered: Qt.exit(2) }
}
