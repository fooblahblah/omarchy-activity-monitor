import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Owns the Activity panel's sampling lifecycle and derived data. Keeping process I/O,
// framing, watchdogs, and power-reader escalation here leaves Panel.qml focused
// on presentation and interaction.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  property var settings: ({})
  property bool active: false
  property bool expanded: false

  readonly property string statsHelperPath: decodeURIComponent(
    String(Qt.resolvedUrl("activity-stats")).replace("file://", ""))
  readonly property string powerHelperPath: decodeURIComponent(
    String(Qt.resolvedUrl("activity-power-reader")).replace("file://", ""))

  readonly property var snapshot: _snapshot
  readonly property var thermalSnapshot: _thermalSnapshot
  readonly property var storageSnapshot: _storageSnapshot
  readonly property var processPower: _processPower
  readonly property var processes: _processes
  readonly property var metrics: _metrics
  readonly property bool processMetricsReady: _processMetricsReady
  readonly property bool processPowerUnavailable: _processPowerState === powerStateUnavailable
  readonly property string processPowerState: _processPowerState

  readonly property string powerStateStopped: "stopped"
  readonly property string powerStateStartingUser: "starting-user"
  readonly property string powerStateReadyUser: "ready-user"
  readonly property string powerStateSwitchingRoot: "switching-root"
  readonly property string powerStateStartingRoot: "starting-root"
  readonly property string powerStateReadyRoot: "ready-root"
  readonly property string powerStateUnavailable: "unavailable"

  readonly property int refreshInterval: boundedSetting("refreshIntervalMs", 1500, 500, 10000)
  readonly property int processRefreshInterval: boundedSetting("processRefreshIntervalMs", 3000, 1000, 15000)
  readonly property int thermalRefreshInterval: boundedSetting("thermalRefreshIntervalMs", 10000, 3000, 60000)
  readonly property int storageRefreshInterval: boundedSetting("storageRefreshIntervalMs", 30000, 10000, 120000)
  readonly property int historySamples: boundedSetting("historySamples", 60, 20, 240)

  property var _snapshot: Model.emptySnapshot()
  property var _thermalSnapshot: Model.emptyThermalSnapshot()
  property var _storageSnapshot: Model.emptyStorageSnapshot()
  property var _processPower: Model.emptyPower()
  property var _processes: []
  property var _metrics: Model.emptyMetrics()
  property bool _processMetricsReady: false

  property var _previousSnapshot: Model.emptySnapshot()
  property var _previousProcessSnapshot: Model.emptyProcessSnapshot()
  property var _previousProcessPowerSnapshot: Model.emptyPackagePowerSnapshot()

  property var _statsReaderBuffer: []
  property bool _statsReaderReady: false
  property bool _resourceSamplePending: false
  property bool _processSamplePending: false
  property bool _thermalSamplePending: false
  property bool _storageSamplePending: false

  property var _processPowerBuffer: []
  property bool _processPowerSamplePending: false
  property string _processPowerState: powerStateStopped

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boundedSetting(name, fallback, minimum, maximum) {
    var value = Number(setting(name, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function statsPending(kind) {
    if (kind === "resources") return _resourceSamplePending
    if (kind === "processes") return _processSamplePending
    if (kind === "thermals") return _thermalSamplePending
    if (kind === "storage") return _storageSamplePending
    return false
  }

  function anyStatsPending() {
    return _resourceSamplePending
      || _processSamplePending
      || _thermalSamplePending
      || _storageSamplePending
  }

  function setStatsPending(kind, value) {
    if (kind === "resources") _resourceSamplePending = value
    else if (kind === "processes") _processSamplePending = value
    else if (kind === "thermals") _thermalSamplePending = value
    else if (kind === "storage") _storageSamplePending = value
  }

  function resetStatsReaderState() {
    _statsReaderReady = false
    _statsReaderBuffer = []
    _resourceSamplePending = false
    _processSamplePending = false
    _thermalSamplePending = false
    _storageSamplePending = false
    statsReaderWatchdog.stop()
  }

  function startStatsReader() {
    if (!active || statsReaderProc.running) return
    _statsReaderReady = false
    _statsReaderBuffer = []
    statsReaderProc.running = true
  }

  function sendStatsRequest(kind) {
    if (!active || statsPending(kind)) return
    setStatsPending(kind, true)
    statsReaderWatchdog.restart()
    if (!statsReaderProc.running) startStatsReader()
    if (_statsReaderReady) statsReaderProc.write(kind + "\n")
  }

  function sendPendingStatsRequests() {
    if (!_statsReaderReady) return
    if (_resourceSamplePending) statsReaderProc.write("resources\n")
    if (_processSamplePending) statsReaderProc.write("processes\n")
    if (_thermalSamplePending) statsReaderProc.write("thermals\n")
    if (_storageSamplePending) statsReaderProc.write("storage\n")
  }

  function refreshResources() {
    sendStatsRequest("resources")
  }

  function refreshProcesses() {
    sendStatsRequest("processes")
  }

  function refreshThermals() {
    sendStatsRequest("thermals")
  }

  function refreshStorage() {
    sendStatsRequest("storage")
  }

  function consumeStatsReaderLine(line) {
    var value = String(line || "")
    if (value.indexOf("snapshot-end\t") !== 0) {
      _statsReaderBuffer.push(value)
      return
    }

    var kind = value.slice("snapshot-end\t".length)
    var raw = _statsReaderBuffer.join("\n")
    _statsReaderBuffer = []
    setStatsPending(kind, false)
    if (anyStatsPending()) statsReaderWatchdog.restart()
    else statsReaderWatchdog.stop()
    if (kind === "resources") consumeSnapshot(raw)
    else if (kind === "processes") consumeProcesses(raw)
    else if (kind === "thermals") consumeThermals(raw)
    else if (kind === "storage") consumeStorage(raw)
  }

  function processPowerUsesUserReader() {
    return _processPowerState === powerStateStartingUser
      || _processPowerState === powerStateReadyUser
  }

  function processPowerReaderReady() {
    return _processPowerState === powerStateReadyUser
      || _processPowerState === powerStateReadyRoot
  }

  function startProcessPowerReader() {
    if (!active || !expanded || processPowerUnavailable || processPowerProc.running) return

    var useRoot = _processPowerState === powerStateSwitchingRoot
    _processPowerBuffer = []
    _processPowerState = useRoot ? powerStateStartingRoot : powerStateStartingUser
    processPowerProc.command = useRoot
      ? [powerHelperPath]
      : [statsHelperPath, "--activity-process-power-reader"]
    processPowerProc.running = true
  }

  function requestProcessPowerSample() {
    if (!active || !expanded || processPowerUnavailable || _processPowerSamplePending) return
    _processPowerSamplePending = true
    processPowerWatchdog.restart()
    if (!processPowerProc.running) startProcessPowerReader()
    if (processPowerReaderReady()) processPowerProc.write("sample\n")
  }

  function stopProcessPowerReader() {
    _processPowerState = powerStateStopped
    _processPowerSamplePending = false
    _processPowerBuffer = []
    processPowerWatchdog.stop()
    if (processPowerProc.running) processPowerProc.running = false
  }

  function consumeProcessPowerLine(line) {
    var value = String(line || "")
    if (value !== "snapshot-end\tpower") {
      _processPowerBuffer.push(value)
      return
    }

    var raw = _processPowerBuffer.join("\n")
    _processPowerBuffer = []
    _processPowerSamplePending = false
    processPowerWatchdog.stop()
    consumeProcessPower(raw)
  }

  function refreshProcessCycle() {
    if (expanded && !processPowerUnavailable) requestProcessPowerSample()
    else refreshProcesses()
  }

  function refresh() {
    refreshResources()
    refreshProcessCycle()
    refreshThermals()
    refreshStorage()
  }

  function consumeSnapshot(raw) {
    var next = Model.parseSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    _metrics = Model.nextMetrics(_previousSnapshot, next, metrics, historySamples)
    _previousSnapshot = next
    _snapshot = next
  }

  function consumeThermals(raw) {
    var next = Model.parseThermalSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    _thermalSnapshot = next
  }

  function consumeStorage(raw) {
    var next = Model.parseStorageSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    _storageSnapshot = next
  }

  function consumeProcessPower(raw) {
    if (!expanded) return
    var next = Model.parsePackagePowerSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0 || !Model.packageEnergyReadable(next)) {
      rejectProcessPowerSample()
      return
    }

    _processPower = Model.nextPackagePower(_previousProcessPowerSnapshot, next)
    _previousProcessPowerSnapshot = next
    refreshProcesses()
  }

  function rejectProcessPowerSample() {
    var retryAsRoot = processPowerUsesUserReader()
    if (retryAsRoot) {
      resetProcessPowerMeasurement()
      _processPowerState = powerStateSwitchingRoot
    } else {
      markProcessPowerUnavailable()
      refreshProcesses()
    }
    if (processPowerProc.running) processPowerProc.running = false
  }

  function consumeProcesses(raw) {
    var next = Model.parseProcessSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    if (_previousProcessSnapshot.sample <= 0) {
      _previousProcessSnapshot = next
      _processes = []
      if (active) processWarmup.restart()
      return
    }
    var busyDelta = Model.processSystemBusyDelta(_previousProcessSnapshot, next)
    var nextProcesses = Model.nextProcesses(
      _previousProcessSnapshot,
      next,
      snapshot.memory.total
    )
    _processes = Model.estimateProcessPower(
      nextProcesses,
      processPower.available ? processPower.watts : -1,
      busyDelta
    )
    _previousProcessSnapshot = next
    _processMetricsReady = true
  }

  function resetProcessPowerMeasurement() {
    _previousProcessPowerSnapshot = Model.emptyPackagePowerSnapshot()
    _processPower = Model.emptyPower()
    _processes = Model.estimateProcessPower(processes, -1, -1)
  }

  function markProcessPowerUnavailable() {
    _processPowerState = powerStateUnavailable
    resetProcessPowerMeasurement()
  }

  function resetSessionData() {
    _snapshot = Model.emptySnapshot()
    _thermalSnapshot = Model.emptyThermalSnapshot()
    _storageSnapshot = Model.emptyStorageSnapshot()
    _processPower = Model.emptyPower()
    _processes = []
    _metrics = Model.emptyMetrics()
    _processMetricsReady = false

    _previousSnapshot = Model.emptySnapshot()
    _previousProcessSnapshot = Model.emptyProcessSnapshot()
    _previousProcessPowerSnapshot = Model.emptyPackagePowerSnapshot()
    resetStatsReaderState()
    _processPowerBuffer = []
    _processPowerSamplePending = false
    _processPowerState = powerStateStopped
  }

  function startSession() {
    resetSessionData()
    refresh()
  }

  function stopSession() {
    resetStatsReaderState()
    if (statsReaderProc.running) statsReaderProc.running = false
    stopProcessPowerReader()
    processWarmup.stop()
  }

  onActiveChanged: {
    if (active) startSession()
    else stopSession()
  }

  onExpandedChanged: {
    if (!expanded) {
      stopProcessPowerReader()
      resetProcessPowerMeasurement()
    } else if (active) {
      refreshProcessCycle()
    }
  }

  Process {
    id: statsReaderProc
    command: [root.statsHelperPath, "--activity-reader"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.consumeStatsReaderLine(line) }
    }
    onStarted: {
      root._statsReaderReady = true
      root.sendPendingStatsRequests()
    }
    onExited: root.resetStatsReaderState()
  }

  Process {
    id: processPowerProc
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.consumeProcessPowerLine(line) }
    }
    onStarted: {
      if (!root.active || !root.expanded) {
        root.stopProcessPowerReader()
        return
      }
      if (root._processPowerState === root.powerStateStartingUser)
        root._processPowerState = root.powerStateReadyUser
      else if (root._processPowerState === root.powerStateStartingRoot)
        root._processPowerState = root.powerStateReadyRoot
      else {
        root.stopProcessPowerReader()
        return
      }
      if (root._processPowerSamplePending) processPowerProc.write("sample\n")
    }
    onExited: {
      var exitedState = root._processPowerState
      root._processPowerSamplePending = false
      root._processPowerBuffer = []
      processPowerWatchdog.stop()

      if (!root.active || !root.expanded || exitedState === root.powerStateStopped) {
        root._processPowerState = root.powerStateStopped
        return
      }
      if (exitedState === root.powerStateUnavailable) return

      if (exitedState === root.powerStateSwitchingRoot
          || exitedState === root.powerStateStartingUser
          || exitedState === root.powerStateReadyUser) {
        root._processPowerState = root.powerStateSwitchingRoot
        Qt.callLater(function() { root.requestProcessPowerSample() })
        return
      }

      root.markProcessPowerUnavailable()
      Qt.callLater(function() { root.refreshProcesses() })
    }
  }

  Timer {
    id: processWarmup
    interval: 600
    repeat: false
    onTriggered: if (root.active) root.refreshProcesses()
  }

  Timer {
    id: statsReaderWatchdog
    interval: 5000
    repeat: false
    onTriggered: {
      root._statsReaderReady = false
      if (statsReaderProc.running) statsReaderProc.running = false
    }
  }

  Timer {
    id: processPowerWatchdog
    interval: 5000
    repeat: false
    onTriggered: if (processPowerProc.running) processPowerProc.running = false
  }

  Timer {
    interval: root.refreshInterval
    running: root.active
    repeat: true
    onTriggered: root.refreshResources()
  }

  Timer {
    interval: root.processRefreshInterval
    running: root.active
    repeat: true
    onTriggered: root.refreshProcessCycle()
  }

  Timer {
    interval: root.thermalRefreshInterval
    running: root.active
    repeat: true
    onTriggered: root.refreshThermals()
  }

  Timer {
    interval: root.storageRefreshInterval
    running: root.active
    repeat: true
    onTriggered: root.refreshStorage()
  }
}
