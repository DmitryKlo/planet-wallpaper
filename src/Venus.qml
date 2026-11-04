pragma ComponentBehavior: Bound
import QtQuick
Item {
    id: root
    property real phase: 0
    property real cloudTime: 0
    property url assetRoot: Qt.resolvedUrl("assets/")
    readonly property bool ready: background.status === Image.Ready
    readonly property bool shaderReady: effect.status === ShaderEffect.Compiled
    readonly property var diagnostics: ({ renderer: "venus-prototype", ready: ready,
                                          shaderStatus: effect.status, shaderLog: effect.log,
                                          phase: phase, cloudTime: cloudTime })
    Image {
        id: background
        source: root.assetRoot + "space-without-clouds.png"
        visible: false
        asynchronous: true
        smooth: true
    }
    ShaderEffect {
        id: effect
        anchors.fill: parent
        visible: root.ready
        property variant skyMap: background
        property real phase: root.phase
        property real screenWidth: width
        property real screenHeight: height
        fragmentShader: Qt.resolvedUrl("venus.frag.qsb")
    }
}
