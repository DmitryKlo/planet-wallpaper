import QtQuick
import QtQuick.Window

Item {
    id: root
    width: 256
    height: 128
    property real timeSeconds: 0
    property real rotationPeriodSeconds: 360
    readonly property real secondsPerAnimationSecond: 38520 / Math.max(1, rotationPeriodSeconds)
    // Sub-texel transport must accumulate enough displacement to survive
    // quantization in the RGBA8 feedback texture.
    readonly property real fixedStep: secondsPerAnimationSecond
    readonly property real maximumStep: secondsPerAnimationSecond
    property bool automatic: true
    property bool simulationEnabled: true
    readonly property alias stateTexture: history
    property bool seedReady: false
    property bool stepPending: false
    property bool resumeClock: false
    property int stepCount: 0
    property int completedFrames: 0
    property real simulatedTime: 0
    property real evolutionTime: 0
    property real stepDelta: 0
    property real initialize: 1
    property real pendingResetTime: -1
    readonly property bool ready: seedReady && step.status !== ShaderEffect.Error
    readonly property var diagnostics: ({
        ready: ready, enabled: simulationEnabled, stepPending: stepPending,
        stepCount: stepCount, simulatedTime: simulatedTime, evolutionTime: evolutionTime,
        modelDaySeconds: 38520, secondsPerAnimationSecond: secondsPerAnimationSecond,
        textureSize: "256x128", stateFormat: "packed RGBA8, three 10-bit fields",
        lastStepSeconds: stepDelta, maximumStepSeconds: maximumStep,
        lagSeconds: Math.max(0, timeSeconds - simulatedTime), shaderLog: step.log
    })
    signal stepCompleted(int stepNumber)

    function scheduleStep(target, initial) {
        if (stepPending || (!initial && !simulationEnabled))
            return false;
        stepDelta = initial ? 0 : Math.max(0, target - simulatedTime);
        evolutionTime = initial ? 0 : evolutionTime + stepDelta;
        simulatedTime = Math.max(0, target);
        initialize = initial ? 1 : 0;
        stepPending = true;
        completedFrames = 0;
        history.scheduleUpdate();
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
        pendingResetTime = Math.max(0, targetTime === undefined ? 0 : targetTime);
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
        if (!seedReady)
            reset(target);
        else if (!simulationEnabled)
            return;
        else if (resumeClock) {
            simulatedTime = target;
            resumeClock = false;
        } else if (target < simulatedTime - 0.001)
            reset(target);
        else if (target - simulatedTime >= fixedStep - 0.0001 * secondsPerAnimationSecond)
            scheduleStep(Math.min(target, simulatedTime + maximumStep), false);
    }
    onTimeSecondsChanged: if (automatic && simulationEnabled) synchronize()
    onSimulationEnabledChanged: {
        resumeClock = simulationEnabled;
        if (automatic && simulationEnabled) synchronize();
    }
    Component.onCompleted: synchronize()
    Connections {
        target: root.Window.window
        function onFrameSwapped() {
            if (!root.stepPending) return;
            root.completedFrames++;
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
    ShaderEffect {
        id: step
        width: root.width
        height: root.height
        visible: false
        blending: false
        property variant previousState: history
        property real deltaSeconds: root.stepDelta
        property real evolutionTime: root.evolutionTime
        property real initialize: root.initialize
        fragmentShader: Qt.resolvedUrl("saturn-atmosphere-step.frag.qsb")
    }
    ShaderEffectSource {
        id: history
        visible: false
        sourceItem: step
        textureSize: Qt.size(256, 128)
        samples: 1
        format: ShaderEffectSource.RGBA8
        recursive: true
        live: false
        smooth: false
        wrapMode: ShaderEffectSource.RepeatHorizontally
    }
}
