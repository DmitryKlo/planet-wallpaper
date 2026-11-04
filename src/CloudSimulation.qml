import QtQuick
import QtQuick.Window

Item {
    id: root
    property url assetRoot: Qt.resolvedUrl("assets/")
    width: 768
    height: 384
    property real timeSeconds: 0
    property real rotationPeriodSeconds: 360
    readonly property real secondsPerAnimationSecond: 86400 / rotationPeriodSeconds
    property bool automatic: true
    property bool simulationEnabled: true
    property bool resumeClock: false
    readonly property real fixedStep: secondsPerAnimationSecond / 6
    readonly property real maximumStep: secondsPerAnimationSecond
    readonly property alias textureLow: lowHistory
    readonly property alias textureHigh: highHistory
    readonly property alias climateTexture: climateHistory
    property bool seedReady: false
    property bool stepPending: false
    property int stepCount: 0
    property real simulatedTime: 0
    // Retained evolution time excludes intervals with weather disabled.
    property real evolutionTime: 0
    property real stepDelta: 0
    property real initialize: 1
    property real pendingResetTime: -1
    property int completedFrames: 0
    readonly property bool ready: seedReady
        && lowStep.status !== ShaderEffect.Error && highStep.status !== ShaderEffect.Error
        && climateStep.status !== ShaderEffect.Error
    readonly property var diagnostics: ({
        ready: ready, enabled: simulationEnabled, stepPending: stepPending,
        stepCount: stepCount, simulatedTime: simulatedTime, evolutionTime: evolutionTime,
        modelDaySeconds: 86400, modelDayFraction: (simulatedTime / 86400) % 1,
        secondsPerAnimationSecond: secondsPerAnimationSecond,
        textureSize: "768x384", minimumStepSeconds: fixedStep,
        lastStepSeconds: stepDelta, maximumStepSeconds: maximumStep,
        lagSeconds: Math.max(0, timeSeconds - simulatedTime),
        stateFormat: "packed RGBA8 clouds (10/10/10 bits) / climate (8/12/12 bits)",
        low: "cumulus, stratus, stratocumulus",
        high: "cirrus, lenticular, cumulonimbus",
        climate: "temperature, water vapour, condensed water",
        cloudSource: "simulated condensate with v8 cirrus fibres and wind-shaped rolls",
        climateSize: "384x192", wind: "latitude jets and temperature-gradient curls",
        lowLog: lowStep.log, highLog: highStep.log, climateLog: climateStep.log
    })
    signal stepCompleted(int stepNumber)

    function scheduleStep(target, initial) {
        if (stepPending || terrain.status !== Image.Ready || (!initial && !simulationEnabled))
            return false;
        stepDelta = initial ? 0 : Math.max(0, target - simulatedTime);
        evolutionTime = initial ? Math.max(0, target) : evolutionTime + stepDelta;
        simulatedTime = Math.max(0, target);
        initialize = initial ? 1 : 0;
        stepPending = true;
        completedFrames = 0;
        climateHistory.scheduleUpdate();
        lowHistory.scheduleUpdate();
        highHistory.scheduleUpdate();
        // A manual step still needs a scene-graph frame if the desktop is paused.
        if (root.Window.window)
            root.Window.window.update();
        return true;
    }
    function reset(targetTime) {
        if (stepPending)
            return false;
        seedReady = false;
        stepCount = 0;
        resumeClock = false;
        return scheduleStep(targetTime === undefined ? 0 : targetTime, true);
    }
    function requestReset(targetTime) {
        // Explicit timeline seeks differ from ordinary frame lag. Queue the
        // reseed if a feedback draw is still in flight.
        pendingResetTime = Math.max(0, targetTime);
        if (!stepPending)
            synchronize();
    }
    function advanceFixedStep() {
        if (!seedReady || !simulationEnabled)
            return false;
        automatic = false;
        return scheduleStep(simulatedTime + fixedStep, false);
    }
    function synchronize() {
        if (stepPending)
            return;
        if (pendingResetTime >= 0) {
            const requested = pendingResetTime;
            pendingResetTime = -1;
            reset(requested);
            return;
        }
        const target = Math.max(0, timeSeconds);
        // Seed once even when disabled, so the retained cloud layers are usable.
        if (!seedReady)
            reset(target);
        else if (!simulationEnabled)
            return;
        else if (resumeClock) {
            // Resume the retained fields at today's solar phase. Do not replay
            // missed steps or replace the clouds after a long disabled interval.
            simulatedTime = target;
            resumeClock = false;
        } else if (target < simulatedTime - 0.001)
            reset(target);
        else if (target - simulatedTime >= fixedStep - 0.0001 * secondsPerAnimationSecond)
            // A busy frame at x10 must not reset all weather. Catch up with
            // bounded physical steps instead of treating a forward lag as seek.
            scheduleStep(Math.min(target, simulatedTime + maximumStep), false);
    }
    onTimeSecondsChanged: if (automatic && simulationEnabled) synchronize()
    onSimulationEnabledChanged: {
        resumeClock = simulationEnabled;
        if (automatic && simulationEnabled)
            synchronize();
    }
    Component.onCompleted: synchronize()
    Connections {
        target: root.Window.window
        function onFrameSwapped() {
            if (!root.stepPending)
                return;
            root.completedFrames++;
            // scheduleUpdate is asynchronous; wait one additional presented
            // frame before a readback, reset or next explicit solver step.
            if (root.completedFrames < 2) {
                root.Window.window.update();
                return;
            }
            root.stepPending = false;
            root.seedReady = true;
            root.stepCount++;
            root.stepCompleted(root.stepCount);
            if (root.automatic || root.pendingResetTime >= 0)
                Qt.callLater(root.synchronize);
        }
    }

    Image {
        id: terrain
        source: root.assetRoot + "earth-emission-v8.png"
        sourceSize: Qt.size(768, 384)
        asynchronous: true
        smooth: true
        visible: false
        onStatusChanged: if (status === Image.Ready) root.synchronize()
    }
    ShaderEffect {
        id: climateStep
        width: 384
        height: 192
        visible: false
        blending: false
        property variant previousClimate: climateHistory
        property variant terrainMap: terrain
        property real simulationTime: root.simulatedTime
        property real deltaSeconds: root.stepDelta
        property real initialize: root.initialize
        fragmentShader: Qt.resolvedUrl("climate-step.frag.qsb")
    }
    ShaderEffectSource {
        id: climateHistory
        visible: false
        sourceItem: climateStep
        textureSize: Qt.size(384, 192)
        samples: 1
        // This backend rejects both float formats. Pack vapour/condensate
        // into 12-bit values in RGBA8 instead of silently losing precision.
        format: ShaderEffectSource.RGBA8
        recursive: true
        live: false
        smooth: false
        wrapMode: ShaderEffectSource.RepeatHorizontally
    }

    ShaderEffect {
        id: lowStep
        width: root.width
        height: root.height
        visible: false
        blending: false
        property variant previousState: lowHistory
        property variant climateState: climateHistory
        property variant terrainMap: terrain
        property real simulationTime: root.simulatedTime
        property real deltaSeconds: root.stepDelta
        property real initialize: root.initialize
        property real group: 0
        fragmentShader: Qt.resolvedUrl("cloud-step.frag.qsb")
    }
    ShaderEffectSource {
        id: lowHistory
        visible: false
        sourceItem: lowStep
        textureSize: Qt.size(root.width, root.height)
        samples: 1
        format: ShaderEffectSource.RGBA8
        recursive: true
        live: false
        // Residual density bits live in alpha; decode before interpolation.
        smooth: false
        wrapMode: ShaderEffectSource.RepeatHorizontally
    }
    ShaderEffect {
        id: highStep
        width: root.width
        height: root.height
        visible: false
        blending: false
        property variant previousState: highHistory
        property variant climateState: climateHistory
        property variant terrainMap: terrain
        property real simulationTime: root.simulatedTime
        property real deltaSeconds: root.stepDelta
        property real initialize: root.initialize
        property real group: 1
        fragmentShader: Qt.resolvedUrl("cloud-step.frag.qsb")
    }
    ShaderEffectSource {
        id: highHistory
        visible: false
        sourceItem: highStep
        textureSize: Qt.size(root.width, root.height)
        samples: 1
        format: ShaderEffectSource.RGBA8
        recursive: true
        live: false
        smooth: false
        wrapMode: ShaderEffectSource.RepeatHorizontally
    }
}
