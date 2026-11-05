pragma ComponentBehavior: Bound
import QtQuick
Item {
    id: root
    property real phase: 0
    property real cloudTime: 0
    property real rotationPeriodSeconds: 360
    readonly property real modelDaySeconds: 345600
    // One visible cloud circuit represents four terrestrial days of
    // upper-atmosphere superrotation, rather than the solid body's spin.
    property real modelTimeSeconds: cloudTime * modelDaySeconds / Math.max(1, rotationPeriodSeconds)
    property bool weatherEnabled: true
    property url assetRoot: Qt.resolvedUrl("assets/")
    // Window visibility must depend only on assets: the feedback seed needs
    // presented frames before weather.ready can become true.
    readonly property bool ready: background.status === Image.Ready
    readonly property bool shaderReady: effect.status === ShaderEffect.Compiled
    readonly property bool weatherReady: weather.ready && !weather.stepPending
    readonly property var weatherModel: weather
    function resetWeather() { weather.requestReset(root.modelTimeSeconds); }
    readonly property var diagnostics: ({ renderer: "venus-retained-atmosphere-v1", ready: ready,
                                          shaderStatus: effect.status, shaderLog: effect.log,
                                          phase: phase, cloudTime: cloudTime,
                                          modelTimeSeconds: modelTimeSeconds,
                                          modelDaySeconds: modelDaySeconds,
                                          weather: weather.diagnostics })
    Image {
        id: background
        source: root.assetRoot + "space-without-clouds.png"
        visible: false
        asynchronous: true
        smooth: true
    }
    VenusAtmosphere {
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
        fragmentShader: Qt.resolvedUrl("venus.frag.qsb")
    }
}
