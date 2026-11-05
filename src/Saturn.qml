pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property real phase: 0
    property real cloudTime: 0
    property real rotationPeriodSeconds: 360
    readonly property real modelDaySeconds: 38520
    property real modelTimeSeconds: cloudTime * modelDaySeconds / Math.max(1, rotationPeriodSeconds)
    property bool weatherEnabled: true
    property url assetRoot: Qt.resolvedUrl("assets/")
    readonly property bool ready: background.status === Image.Ready
    readonly property bool shaderReady: effect.status === ShaderEffect.Compiled
    readonly property bool weatherReady: weather.ready && !weather.stepPending
    readonly property var weatherModel: weather
    readonly property var diagnostics: ({ renderer: "saturn-rings-atmosphere", ready: ready,
        shaderStatus: effect.status, shaderLog: effect.log, phase: phase,
        cloudTime: cloudTime, modelTimeSeconds: modelTimeSeconds, weather: weather.diagnostics })
    function resetWeather() { weather.requestReset(root.modelTimeSeconds); }

    Image {
        id: background
        source: root.assetRoot + "space-without-clouds.png"
        visible: false
        asynchronous: true
        smooth: true
    }
    SaturnAtmosphere {
        id: weather
        timeSeconds: root.modelTimeSeconds
        rotationPeriodSeconds: root.rotationPeriodSeconds
        simulationEnabled: root.weatherEnabled
    }
    ShaderEffect {
        id: effect
        anchors.fill: parent
        visible: root.ready && weather.ready
        property variant skyMap: background
        property variant atmosphereMap: weather.stateTexture
        property real phase: root.phase
        property real screenWidth: width
        property real screenHeight: height
        fragmentShader: Qt.resolvedUrl("saturn.frag.qsb")
    }
}
