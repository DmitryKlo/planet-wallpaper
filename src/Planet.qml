pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property url imagePath
    property url assetRoot: Qt.resolvedUrl("assets/")
    property real phase: 0
    property real fullGlobe: 0
    property real cloudAmount: 0.90
    property real cloudPhase: phase
    property real cloudTime: 0
    property real rotationPeriodSeconds: 360
    property real modelTimeSeconds: cloudTime * 86400 / rotationPeriodSeconds
    property bool weatherEnabled: true
    property int planetVisualVersion: 6
    property real skyBrightness: 1.0
    property real surfaceSoftness: 0.85
    property real cityGlow: 0.50
    property real sunTipBoost: 0.16
    property real diagnosticMode: 0
    property real cloudType: 0
    readonly property bool shaderReady: effect.status === ShaderEffect.Compiled
    readonly property bool weatherReady: weather.ready && !weather.stepPending
    readonly property var weatherModel: weather
    function resetWeather() { weather.requestReset(root.modelTimeSeconds); }
    readonly property bool ready: background.status === Image.Ready
                                  && surface.status === Image.Ready
                                  && emission.status === Image.Ready
    readonly property var diagnostics: ({
        renderer: "weather-layers-v8", ready: ready,
        width: effect.width, height: effect.height,
        surfaceSize: surface.sourceSize.toString(),
        fullGlobe: fullGlobe, cloudTime: cloudTime,
        cloudPhase: phase, cloudAngularSpeedRatio: 1,
        weather: weather.diagnostics,
        planetVisualVersion: planetVisualVersion,
        lightingSource: "v8 material-dependent", sunTipBoost: sunTipBoost,
        textureStyle: planetVisualVersion === 6 ? "painted-night-geography-v6-clear-ocean" : "midnight-blue-land",
        skyBrightness: skyBrightness, shaderStatus: effect.status, shaderLog: effect.log,
        surfaceSoftness: surfaceSoftness, cityGlow: cityGlow
    })

    Image {
        id: background
        source: root.assetRoot + "space-without-clouds.png"
        visible: false
        asynchronous: true
        smooth: true
    }
    Image {
        id: surface
        source: root.assetRoot + (root.planetVisualVersion === 6
                ? "earth-surface-v6-clear-ocean.png" : "earth-surface-pixel-v8.png")
        visible: false
        asynchronous: true
        smooth: true
        mipmap: true
    }
    Image {
        id: emission
        source: root.assetRoot + "earth-emission-v8.png"
        visible: false
        asynchronous: true
        smooth: true
        mipmap: true
    }
    CloudSimulation {
        id: weather
        assetRoot: root.assetRoot
        timeSeconds: root.modelTimeSeconds
        rotationPeriodSeconds: root.rotationPeriodSeconds
        simulationEnabled: root.weatherEnabled
    }
    ShaderEffect {
        id: effect
        anchors.fill: parent
        visible: root.ready
        property variant skyMap: background
        property variant surfaceMap: surface
        property variant emissionMap: emission
        property variant cloudLowMap: weather.textureLow
        property variant cloudHighMap: weather.textureHigh
        property real sunTipBoost: root.sunTipBoost
        property real planetVisualVersion: root.planetVisualVersion
        property real phase: root.phase
        property real fullGlobe: root.fullGlobe
        property real cloudAmount: root.cloudAmount
        property real cloudPhase: root.cloudPhase
        property real cloudTime: root.cloudTime
        property real weatherTime: weather.evolutionTime
        property real cloudType: root.cloudType
        property real skyBrightness: root.skyBrightness
        property real diagnosticMode: root.diagnosticMode
        property real screenWidth: width
        property real screenHeight: height
        property real surfaceSoftness: root.surfaceSoftness
        property real cityGlow: root.cityGlow
        fragmentShader: Qt.resolvedUrl("planet.frag.qsb")
    }
}
