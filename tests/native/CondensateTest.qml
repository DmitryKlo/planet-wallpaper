pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

Window {
    id: win
    width: 1536
    height: 384
    visible: true
    property real water: 0
    property int stage: 0
    property real testTime: 123456
    readonly property string output: "@TEST_OUTPUT@/condensate-test/"

    ShaderEffect {
        id: climate
        width: 384
        height: 192
        blending: false
        property real condensate: win.water
        fragmentShader: Qt.resolvedUrl("climate-input.frag.qsb")
    }
    ShaderEffectSource {
        id: climateMap
        sourceItem: climate
        hideSource: true
        visible: false
        textureSize: Qt.size(384, 192)
        format: ShaderEffectSource.RGBA8
        smooth: false
        live: true
    }
    Image {
        id: terrain
        source: Qt.resolvedUrl("../assets/earth-emission-v8.png")
        sourceSize: Qt.size(768,384)
        asynchronous: true
        visible: false
    }
    Row {
        id: view
        Repeater {
            id: fields
            model: 2
            Item {
                required property int index
                width: 768
                height: 384
                readonly property int status: update.status
                readonly property string log: update.log
                ShaderEffect {
                    id: update
                    width: 768
                    height: 384
                    blending: false
                    property variant previousState: climateMap
                    property variant climateState: climateMap
                    property variant terrainMap: terrain
                    property real simulationTime: win.testTime
                    property real deltaSeconds: 0
                    property real initialize: 1
                    property real group: parent.index
                    fragmentShader: Qt.resolvedUrl("../cloud-step.frag.qsb")
                }
                ShaderEffectSource {
                    id: packed
                    sourceItem: update
                    hideSource: true
                    visible: false
                    textureSize: Qt.size(768,384)
                    format: ShaderEffectSource.RGBA8
                    smooth: false
                }
                ShaderEffect {
                    anchors.fill: parent
                    property variant field: packed
                    fragmentShader: Qt.resolvedUrl("cloud-display.frag.qsb")
                }
            }
        }
    }
    Timer {
        id: capture
        interval: 150
        running: terrain.status === Image.Ready && climate.status === ShaderEffect.Compiled
                 && fields.itemAt(0)?.status === ShaderEffect.Compiled
                 && fields.itemAt(1) && fields.itemAt(1).status !== ShaderEffect.Error
        onTriggered: view.grabToImage(result => {
            const names = ["no-condensate", "with-condensate", "same-condensate-later", "condensate-removed"];
            if (!result.saveToFile(win.output + names[win.stage] + ".png")) { Qt.exit(1); return; }
            win.stage++;
            if (win.stage === 4) { Qt.quit(); return; }
            win.water = win.stage === 1 || win.stage === 2 ? 0.38 : 0;
            if (win.stage === 2)
                win.testTime += 86400;
            capture.restart();
        })
    }
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.warn("CONDENSATE TEST TIMEOUT", terrain.status, climate.status, climate.log,
                         fields.itemAt(0)?.status, fields.itemAt(0)?.log,
                         fields.itemAt(1)?.status, fields.itemAt(1)?.log, view.width, view.height);
            Qt.exit(2);
        }
    }
}
