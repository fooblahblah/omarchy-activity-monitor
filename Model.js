function number(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : (fallback === undefined ? 0 : fallback)
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, number(value)))
}

function emptySnapshot() {
  return {
    schema: 0,
    sample: 0,
    cpuFrequencyMHz: -1,
    memorySpeedMTs: -1,
    cpu: { total: 0, idle: 0 },
    cores: [],
    memory: {
      total: 0,
      available: 0,
      cached: 0,
      swapTotal: 0,
      swapFree: 0
    },
    tasks: { running: 0, total: 0 },
    uptime: 0,
    networks: [],
    disks: []
  }
}

function emptyMetrics() {
  return {
    cpu: 0,
    memory: 0,
    swap: 0,
    download: 0,
    upload: 0,
    diskRead: 0,
    diskWrite: 0,
    networkInterface: "",
    cores: [],
    cpuHistory: [],
    memoryHistory: [],
    networkHistory: [],
    diskHistory: []
  }
}

function emptyProcessSnapshot() {
  return {
    schema: 0,
    sample: 0,
    clockTicks: 100,
    systemBusyTicks: 0,
    processes: []
  }
}

function emptyThermalSnapshot() {
  return {
    schema: 0,
    sample: 0,
    temperatures: []
  }
}

function emptyPackagePowerSnapshot() {
  return {
    schema: 0,
    sample: 0,
    packages: []
  }
}

function emptyPower() {
  return {
    available: false,
    watts: -1
  }
}

function emptyStorageSnapshot() {
  return {
    schema: 0,
    sample: 0,
    path: "/",
    total: 0,
    used: 0,
    available: 0
  }
}

function emptyGpuSnapshot() {
  return {
    schema: 0,
    sample: 0,
    gpus: []
  }
}

function gpuSnapshotEntry(snapshot, id) {
  var gpuId = String(id || "")
  for (var i = 0; i < snapshot.gpus.length; i++) {
    if (snapshot.gpus[i].id === gpuId) return snapshot.gpus[i]
  }

  var gpu = {
    id: gpuId,
    vendor: "GPU",
    driver: "unknown",
    name: "GPU",
    frequencyMHz: -1,
    directUtilization: -1,
    memoryUsed: -1,
    memoryTotal: -1,
    memoryKind: "unknown",
    engines: [],
    dedicatedMemory: 0,
    sharedMemory: 0,
    dedicatedMemorySeen: false,
    sharedMemorySeen: false
  }
  snapshot.gpus.push(gpu)
  return gpu
}

function temperatureFromFields(fields) {
  return {
    id: String(fields[1] || ""),
    chip: String(fields[2] || ""),
    label: String(fields[3] || "Sensor"),
    value: number(fields[4]) / 1000
  }
}

function cpuCounters(fields) {
  return {
    total: number(fields[2]),
    idle: number(fields[3])
  }
}

function parseSnapshot(raw) {
  var snapshot = emptySnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    var kind = fields[0]

    if (kind === "schema") {
      snapshot.schema = fields[1] === "activity-resources" ? number(fields[2]) : 0
    } else if (kind === "sample") {
      snapshot.sample = number(fields[1])
    } else if (kind === "cpu") {
      var counters = cpuCounters(fields)
      if (fields[1] === "cpu") snapshot.cpu = counters
      else snapshot.cores.push({
        name: String(fields[1] || ""),
        total: counters.total,
        idle: counters.idle
      })
    } else if (kind === "frequency") {
      if (fields[1] === "cpu")
        snapshot.cpuFrequencyMHz = Math.max(-1, number(fields[2], -1))
      else if (fields[1] === "memory")
        snapshot.memorySpeedMTs = Math.max(-1, number(fields[2], -1))
    } else if (kind === "memory") {
      snapshot.memory = {
        total: number(fields[1]) * 1024,
        available: number(fields[2]) * 1024,
        swapTotal: number(fields[3]) * 1024,
        swapFree: number(fields[4]) * 1024,
        cached: number(fields[5]) * 1024
      }
    } else if (kind === "tasks") {
      snapshot.tasks = {
        running: number(fields[1]),
        total: number(fields[2])
      }
    } else if (kind === "network") {
      snapshot.networks.push({
        name: String(fields[1] || ""),
        received: number(fields[2]),
        transmitted: number(fields[3]),
        state: String(fields[4] || "unknown"),
        defaultRoute: number(fields[5]) === 1,
        physical: number(fields[6]) === 1
      })
    } else if (kind === "disk") {
      snapshot.disks.push({
        id: String(fields[1] || fields[2] || ""),
        name: String(fields[2] || ""),
        read: number(fields[3]) * 512,
        written: number(fields[4]) * 512
      })
    }
  }

  snapshot.uptime = snapshot.sample
  return snapshot
}

function parseProcessSnapshot(raw) {
  var snapshot = emptyProcessSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    var kind = fields[0]

    if (kind === "schema") {
      snapshot.schema = fields[1] === "activity-processes" ? number(fields[2]) : 0
    } else if (kind === "sample") {
      snapshot.sample = number(fields[1])
      snapshot.clockTicks = Math.max(1, number(fields[2], 100))
      snapshot.systemBusyTicks = Math.max(0, number(fields[3]))
    } else if (kind === "process") {
      snapshot.processes.push({
        pid: number(fields[1]),
        user: String(fields[2] || ""),
        state: String(fields[3] || ""),
        startTicks: number(fields[4]),
        cpuTicks: number(fields[5]),
        rss: Math.max(0, number(fields[6])) * 1024,
        name: String(fields.slice(7).join("\t") || "unknown")
      })
    }
  }

  return snapshot
}

function parseThermalSnapshot(raw) {
  var snapshot = emptyThermalSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    if (fields[0] === "schema") {
      snapshot.schema = fields[1] === "activity-thermals" ? number(fields[2]) : 0
    } else if (fields[0] === "sample") {
      snapshot.sample = number(fields[1])
    } else if (fields[0] === "temperature") {
      snapshot.temperatures.push(temperatureFromFields(fields))
    }
  }

  return snapshot
}

function parsePackagePowerSnapshot(raw) {
  var snapshot = emptyPackagePowerSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    if (fields[0] === "schema") {
      snapshot.schema = fields[1] === "activity-process-power" ? number(fields[2]) : 0
    } else if (fields[0] === "sample") {
      snapshot.sample = number(fields[1])
    } else if (fields[0] === "package") {
      var packageValue = {
        id: String(fields[1] || ""),
        name: String(fields[2] || fields[1] || "Package"),
        energy: !fields[3] ? -1 : Math.max(0, number(fields[3])),
        maximumEnergyRange: Math.max(0, number(fields[4]))
      }
      snapshot.packages.push(packageValue)
    }
  }

  return snapshot
}

function parseStorageSnapshot(raw) {
  var snapshot = emptyStorageSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    if (fields[0] === "schema") {
      snapshot.schema = fields[1] === "activity-storage" ? number(fields[2]) : 0
    } else if (fields[0] === "sample") {
      snapshot.sample = number(fields[1])
    } else if (fields[0] === "storage") {
      snapshot.path = String(fields[1] || "/")
      snapshot.total = Math.max(0, number(fields[2]))
      snapshot.used = Math.min(snapshot.total, Math.max(0, number(fields[3])))
      snapshot.available = Math.min(snapshot.total, Math.max(0, number(fields[4])))
    }
  }

  return snapshot
}

function parseGpuSnapshot(raw) {
  var snapshot = emptyGpuSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    var kind = fields[0]

    if (kind === "schema") {
      snapshot.schema = fields[1] === "activity-gpus" ? number(fields[2]) : 0
    } else if (kind === "sample") {
      snapshot.sample = number(fields[1])
    } else if (kind === "gpu") {
      var gpu = gpuSnapshotEntry(snapshot, fields[1])
      gpu.vendor = String(fields[2] || "GPU")
      gpu.driver = String(fields[3] || "unknown")
      gpu.name = String(fields[4] || gpu.vendor + " GPU")
      gpu.frequencyMHz = Math.max(-1, number(fields[9], -1))
      gpu.directUtilization = Math.max(-1, number(fields[5], -1))
      gpu.memoryUsed = Math.max(-1, number(fields[6], -1))
      gpu.memoryTotal = Math.max(-1, number(fields[7], -1))
      gpu.memoryKind = String(fields[8] || "unknown")
    } else if (kind === "engine") {
      gpuSnapshotEntry(snapshot, fields[1]).engines.push({
        client: String(fields[2] || ""),
        name: String(fields[3] || "engine"),
        busy: Math.max(0, number(fields[4])),
        total: number(fields[5], -1),
        capacity: Math.max(1, number(fields[6], 1)),
        kind: String(fields[7] || "time")
      })
    } else if (kind === "gpu-memory") {
      var memoryGpu = gpuSnapshotEntry(snapshot, fields[1])
      var memoryValue = Math.max(0, number(fields[3]))
      if (fields[2] === "vram") {
        memoryGpu.dedicatedMemory += memoryValue
        memoryGpu.dedicatedMemorySeen = true
      } else if (fields[2] === "shared") {
        memoryGpu.sharedMemory += memoryValue
        memoryGpu.sharedMemorySeen = true
      }
    }
  }

  for (var j = 0; j < snapshot.gpus.length; j++) {
    var value = snapshot.gpus[j]
    if (value.memoryUsed < 0 && value.dedicatedMemorySeen) {
      value.memoryUsed = value.dedicatedMemory
      value.memoryKind = "vram"
    } else if (value.memoryUsed < 0 && value.sharedMemorySeen) {
      value.memoryUsed = value.sharedMemory
      value.memoryKind = "shared"
    }
    if (value.memoryTotal > 0 && value.memoryUsed > value.memoryTotal)
      value.memoryUsed = value.memoryTotal
  }
  return snapshot
}

function gpuEngineKey(engine) {
  return String(engine && engine.client || "") + ":"
    + String(engine && engine.name || "") + ":"
    + String(engine && engine.kind || "")
}

function nextGpus(previous, current) {
  var result = []
  var previousGpus = previous && Array.isArray(previous.gpus) ? previous.gpus : []
  var currentGpus = current && Array.isArray(current.gpus) ? current.gpus : []
  var beforeByGpu = {}
  var seconds = previous && current && current.sample > previous.sample
    ? current.sample - previous.sample
    : 0

  for (var i = 0; i < previousGpus.length; i++) beforeByGpu[previousGpus[i].id] = previousGpus[i]

  for (var j = 0; j < currentGpus.length; j++) {
    var gpu = currentGpus[j]
    var usage = number(gpu.directUtilization, -1)
    if (usage < 0) {
      var oldGpu = beforeByGpu[gpu.id]
      var oldEngines = {}
      var engineUsage = {}
      var comparable = false
      var oldValues = oldGpu && Array.isArray(oldGpu.engines) ? oldGpu.engines : []
      var newValues = Array.isArray(gpu.engines) ? gpu.engines : []

      for (var k = 0; k < oldValues.length; k++) oldEngines[gpuEngineKey(oldValues[k])] = oldValues[k]
      for (var m = 0; m < newValues.length; m++) {
        var engine = newValues[m]
        var oldEngine = oldEngines[gpuEngineKey(engine)]
        if (!oldEngine) continue
        var busyDelta = number(engine.busy) - number(oldEngine.busy)
        if (busyDelta < 0) continue
        var percent = -1
        if (engine.kind === "cycles") {
          var totalDelta = number(engine.total, -1) - number(oldEngine.total, -1)
          if (totalDelta > 0) percent = busyDelta / totalDelta / engine.capacity * 100
        } else if (seconds > 0) {
          percent = busyDelta / (seconds * 1000000000) / engine.capacity * 100
        }
        if (!isFinite(percent) || percent < 0) continue
        comparable = true
        engineUsage[engine.name] = number(engineUsage[engine.name]) + percent
      }

      usage = -1
      if (comparable) {
        usage = 0
        // Different engine classes can run in parallel. Their maximum is a
        // stable whole-GPU indicator without double-counting that overlap.
        for (var engineName in engineUsage)
          usage = Math.max(usage, engineUsage[engineName])
      }
    }

    result.push({
      id: gpu.id,
      vendor: gpu.vendor,
      driver: gpu.driver,
      name: gpu.name,
      frequencyMHz: gpu.frequencyMHz,
      usage: usage < 0 ? -1 : clamp(usage, 0, 100),
      memoryUsed: gpu.memoryUsed,
      memoryTotal: gpu.memoryTotal,
      memoryKind: gpu.memoryKind
    })
  }
  return result
}

function packageEnergyReadable(snapshot) {
  var packages = snapshot && Array.isArray(snapshot.packages) ? snapshot.packages : []
  if (packages.length === 0) return false

  for (var i = 0; i < packages.length; i++) {
    if (number(packages[i].energy, -1) < 0
        || number(packages[i].maximumEnergyRange) <= 0) {
      return false
    }
  }
  return true
}

function packageCountersComparable(previous, current) {
  if (!previous || !current) return 0

  var before = number(previous.energy, -1)
  var after = number(current.energy, -1)
  var previousMaximum = number(previous.maximumEnergyRange)
  var currentMaximum = number(current.maximumEnergyRange)
  var validRange = before >= 0
    && after >= 0
    && currentMaximum > 0
    && previousMaximum === currentMaximum
    && before <= currentMaximum
    && after <= currentMaximum
  if (!validRange || after >= before) return validRange

  // A real RAPL wrap crosses the end of the published counter range. Treat
  // other decreases as a reset/new counter instead of inventing a large draw.
  return before >= currentMaximum * 0.75
    && after <= currentMaximum * 0.25
}

function packageEnergyDelta(previous, current) {
  if (!packageCountersComparable(previous, current)) return 0

  var before = number(previous.energy)
  var after = number(current.energy)
  var currentMaximum = number(current.maximumEnergyRange)
  if (after >= before) return after - before
  return currentMaximum - before + after
}

function nextPackagePower(previous, current) {
  var before = {}
  var totalWatts = 0
  var previousPackages = previous && Array.isArray(previous.packages) ? previous.packages : []
  var currentPackages = current && Array.isArray(current.packages) ? current.packages : []
  var seconds = previous && previous.sample > 0 && current.sample > previous.sample
    ? current.sample - previous.sample
    : 0
  var complete = seconds > 0
    && currentPackages.length > 0
    && currentPackages.length === previousPackages.length

  for (var i = 0; i < previousPackages.length; i++) {
    before[previousPackages[i].id] = previousPackages[i]
  }

  for (var j = 0; j < currentPackages.length; j++) {
    var value = currentPackages[j]
    var delta = packageEnergyDelta(before[value.id], value)
    var comparable = seconds > 0 && packageCountersComparable(before[value.id], value)
    var watts = comparable ? delta / 1000000 / seconds : -1
    if (!isFinite(watts) || watts < 0) watts = -1
    if (watts < 0) complete = false
    if (watts >= 0) totalWatts += watts
  }

  return {
    available: complete,
    watts: complete ? totalWatts : -1
  }
}

function counterPercent(previous, current) {
  if (!previous || !current) return 0
  var total = number(current.total) - number(previous.total)
  var idle = number(current.idle) - number(previous.idle)
  if (total <= 0 || idle < 0) return 0
  return clamp((1 - idle / total) * 100, 0, 100)
}

function counterRate(previous, current, seconds) {
  if (seconds <= 0) return 0
  var delta = number(current) - number(previous)
  return delta < 0 ? 0 : delta / seconds
}

function memoryPercent(memory) {
  var total = number(memory && memory.total)
  if (total <= 0) return 0
  return clamp((total - number(memory.available)) / total * 100, 0, 100)
}

function swapPercent(memory) {
  var total = number(memory && memory.swapTotal)
  if (total <= 0) return 0
  return clamp((total - number(memory.swapFree)) / total * 100, 0, 100)
}

function appendHistory(values, value, limit) {
  var history = Array.isArray(values) ? values.slice() : []
  history.push(number(value))
  var cap = Math.max(1, Math.round(number(limit, 60)))
  if (history.length > cap) history.splice(0, history.length - cap)
  return history
}

function coreUsage(previous, current) {
  var before = {}
  var result = []
  var previousCores = previous && Array.isArray(previous.cores) ? previous.cores : []
  var currentCores = current && Array.isArray(current.cores) ? current.cores : []

  for (var i = 0; i < previousCores.length; i++) before[previousCores[i].name] = previousCores[i]
  for (var j = 0; j < currentCores.length; j++) {
    result.push({
      name: currentCores[j].name,
      usage: counterPercent(before[currentCores[j].name], currentCores[j])
    })
  }
  return result
}

function networkByName(networks, name) {
  var values = Array.isArray(networks) ? networks : []
  for (var i = 0; i < values.length; i++) {
    if (values[i].name === name) return values[i]
  }
  return null
}

function selectNetwork(previous, current, preferredName) {
  var values = current && Array.isArray(current.networks) ? current.networks : []
  if (values.length === 0) return null

  var preferred = networkByName(values, preferredName)
  if (preferred && preferred.defaultRoute) return preferred

  for (var i = 0; i < values.length; i++) {
    if (values[i].defaultRoute) return values[i]
  }
  if (preferred && preferred.state === "up") return preferred

  var previousValues = previous && Array.isArray(previous.networks) ? previous.networks : []
  var best = null
  var bestDelta = -1
  for (var j = 0; j < values.length; j++) {
    if (values[j].state !== "up") continue
    if (!values[j].physical && best && best.physical) continue
    var before = networkByName(previousValues, values[j].name)
    var delta = before
      ? Math.max(0, values[j].received - before.received) + Math.max(0, values[j].transmitted - before.transmitted)
      : 0
    if (!best || (values[j].physical && !best.physical) || delta > bestDelta) {
      best = values[j]
      bestDelta = delta
    }
  }
  return best || values[0]
}

function aggregateDisks(disks) {
  var values = Array.isArray(disks) ? disks : []
  var selected = []
  var read = 0
  var written = 0
  for (var i = 0; i < values.length; i++) {
    selected.push(values[i].id || values[i].name)
    read += number(values[i].read)
    written += number(values[i].written)
  }
  selected.sort()
  return {
    signature: selected.join(","),
    read: read,
    written: written
  }
}

// A counter-based metric needs two samples. While the fresh baseline is being
// established, retain the last derived rates so reopening the panel does not
// flash zero, but immediately refresh values that are valid from one sample.
function baselineMetrics(current, existing) {
  var old = existing || emptyMetrics()
  var network = selectNetwork(null, current, old.networkInterface || "")
  var oldCores = Array.isArray(old.cores) ? old.cores : []
  return {
    cpu: number(old.cpu),
    memory: memoryPercent(current && current.memory),
    swap: swapPercent(current && current.memory),
    download: number(old.download),
    upload: number(old.upload),
    diskRead: number(old.diskRead),
    diskWrite: number(old.diskWrite),
    networkInterface: network ? network.name : String(old.networkInterface || ""),
    cores: oldCores.length > 0 ? oldCores : coreUsage(null, current),
    cpuHistory: Array.isArray(old.cpuHistory) ? old.cpuHistory.slice() : [],
    memoryHistory: Array.isArray(old.memoryHistory) ? old.memoryHistory.slice() : [],
    networkHistory: Array.isArray(old.networkHistory) ? old.networkHistory.slice() : [],
    diskHistory: Array.isArray(old.diskHistory) ? old.diskHistory.slice() : []
  }
}

function nextMetrics(previous, current, existing, historyLimit) {
  var old = existing || {}
  var seconds = previous && previous.sample > 0 && current.sample > previous.sample
    ? current.sample - previous.sample
    : 0
  var cpu = counterPercent(previous && previous.cpu, current.cpu)
  var memory = memoryPercent(current.memory)
  var network = selectNetwork(previous, current, old.networkInterface || "")
  var previousNetwork = network ? networkByName(previous && previous.networks, network.name) : null
  var download = seconds > 0 && previousNetwork
    ? counterRate(previousNetwork.received, network.received, seconds)
    : 0
  var upload = seconds > 0 && previousNetwork
    ? counterRate(previousNetwork.transmitted, network.transmitted, seconds)
    : 0
  var disk = aggregateDisks(current.disks)
  var previousDisk = aggregateDisks(previous && previous.disks)
  var sameDisks = disk.signature !== "" && disk.signature === previousDisk.signature
  var diskRead = seconds > 0 && sameDisks ? counterRate(previousDisk.read, disk.read, seconds) : 0
  var diskWrite = seconds > 0 && sameDisks ? counterRate(previousDisk.written, disk.written, seconds) : 0

  return {
    cpu: cpu,
    memory: memory,
    swap: swapPercent(current.memory),
    download: download,
    upload: upload,
    diskRead: diskRead,
    diskWrite: diskWrite,
    networkInterface: network ? network.name : "",
    cores: coreUsage(previous, current),
    cpuHistory: appendHistory(old.cpuHistory, cpu, historyLimit),
    memoryHistory: appendHistory(old.memoryHistory, memory, historyLimit),
    networkHistory: appendHistory(old.networkHistory, download + upload, historyLimit),
    diskHistory: appendHistory(old.diskHistory, diskRead + diskWrite, historyLimit)
  }
}

function nextProcesses(previous, current, totalMemory) {
  var before = {}
  var result = []
  var previousProcesses = previous && Array.isArray(previous.processes) ? previous.processes : []
  var currentProcesses = current && Array.isArray(current.processes) ? current.processes : []
  var seconds = previous && previous.sample > 0 && current.sample > previous.sample
    ? current.sample - previous.sample
    : 0
  var clockTicks = Math.max(1, number(current && current.clockTicks, 100))
  var memoryTotal = Math.max(0, number(totalMemory))

  for (var i = 0; i < previousProcesses.length; i++) {
    var previousKey = previousProcesses[i].pid + ":" + previousProcesses[i].startTicks
    before[previousKey] = previousProcesses[i]
  }

  for (var j = 0; j < currentProcesses.length; j++) {
    var process = currentProcesses[j]
    var key = process.pid + ":" + process.startTicks
    var old = before[key]
    var cpuTicksDelta = old && seconds > 0
      ? Math.max(0, process.cpuTicks - old.cpuTicks)
      : 0
    var cpu = cpuTicksDelta / clockTicks / (seconds > 0 ? seconds : 1) * 100
    result.push({
      pid: process.pid,
      user: process.user,
      state: process.state,
      startTicks: process.startTicks,
      cpu: cpu,
      cpuTicksDelta: cpuTicksDelta,
      memory: memoryTotal > 0 ? process.rss / memoryTotal * 100 : 0,
      rss: process.rss,
      elapsed: Math.max(0, current.sample - process.startTicks / clockTicks),
      name: process.name
    })
  }
  return result
}

function processSystemBusyDelta(previous, current) {
  if (!previous || !current) return -1
  if (number(previous.schema) <= 0 || number(current.schema) <= 0) return -1
  if (number(current.sample) <= number(previous.sample)) return -1

  var before = number(previous.systemBusyTicks, -1)
  var after = number(current.systemBusyTicks, -1)
  if (before < 0 || after < before) return -1
  return after - before
}

function estimateProcessPower(processes, packageWatts, systemBusyDelta) {
  var values = Array.isArray(processes) ? processes : []
  var result = []
  var measuredWatts = Number(packageWatts)
  var busyDelta = Number(systemBusyDelta)
  var observedDelta = 0
  var powerAvailable = packageWatts !== null
    && packageWatts !== ""
    && isFinite(measuredWatts)
    && measuredWatts >= 0
    && isFinite(busyDelta)
    && busyDelta > 0

  for (var i = 0; i < values.length; i++) {
    observedDelta += Math.max(0, number(values[i] && values[i].cpuTicksDelta))
  }
  var denominator = Math.max(busyDelta, observedDelta)

  for (var j = 0; j < values.length; j++) {
    var source = values[j] || {}
    var clone = {}
    for (var key in source) clone[key] = source[key]
    var cpuTicksDelta = Math.max(0, number(source.cpuTicksDelta))
    clone.power = powerAvailable
      ? measuredWatts * cpuTicksDelta / denominator
      : -1
    result.push(clone)
  }
  return result
}

function processIdentityKey(process) {
  if (!process) return ""
  return String(number(process.pid)) + ":" + String(number(process.startTicks))
}

// This list only gives immediate UI feedback. The plugin-local process helper remains
// authoritative and revalidates identity, ownership, state, and protection
// against live procfs data immediately before taking action.
var protectedProcessNames = [
  "quickshell",
  "hyprland",
  "uwsm",
  "systemd",
  "systemd-executo",
  "systemd-executor",
  "(sd-pam)",
  "dbus-broker",
  "dbus-broker-lau",
  "omarchy-hyprlan"
]

function processActionBlockReason(process, currentUser) {
  if (!process || number(process.pid) <= 1) return "Protected system process"
  if (number(process.startTicks) <= 0) return "Process identity is unavailable"
  if (/^[ZXx]$/.test(String(process.state || ""))) return "Process has already stopped"
  if (String(process.user || "") !== String(currentUser || ""))
    return "Only your own processes can be ended"
  if (protectedProcessNames.indexOf(String(process.name || "").toLowerCase()) >= 0)
    return "Desktop session is protected"
  return ""
}

function processValue(process, key) {
  if (key === "memory") return number(process.memory)
  if (key === "power") return number(process.power, -1)
  if (key === "pid") return number(process.pid)
  if (key === "runtime") return number(process.elapsed)
  if (key === "name") return String(process.name || "").toLowerCase()
  return number(process.cpu)
}

function filterAndSortProcesses(processes, query, sortKey, ascending) {
  var values = Array.isArray(processes) ? processes.slice() : []
  var needle = String(query || "").trim().toLowerCase()
  if (needle) {
    values = values.filter(function(process) {
      return String(process.pid).indexOf(needle) >= 0
        || String(process.name || "").toLowerCase().indexOf(needle) >= 0
        || String(process.user || "").toLowerCase().indexOf(needle) >= 0
    })
  }

  var key = sortKey || "cpu"
  var direction = ascending ? 1 : -1
  values.sort(function(left, right) {
    var a = processValue(left, key)
    var b = processValue(right, key)
    if (a < b) return -1 * direction
    if (a > b) return 1 * direction
    return number(left.pid) - number(right.pid)
  })
  return values
}

function formatBytes(value, suffix) {
  var bytes = Math.max(0, number(value))
  var units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var unit = 0
  while (bytes >= 1024 && unit < units.length - 1) {
    bytes /= 1024
    unit++
  }
  var precision = bytes >= 100 || unit === 0 ? 0 : (bytes >= 10 ? 1 : 2)
  return bytes.toFixed(precision) + " " + units[unit] + (suffix || "")
}

function formatDuration(value) {
  var seconds = Math.max(0, Math.floor(number(value)))
  var days = Math.floor(seconds / 86400)
  var hours = Math.floor((seconds % 86400) / 3600)
  var minutes = Math.floor((seconds % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + minutes + "m"
  if (minutes === 0) return seconds + "s"
  return minutes + "m"
}

function samplingProfile(value) {
  var name = String(value || "balanced").trim().toLowerCase()
  if (name === "efficient") {
    return {
      name: "Efficient",
      resources: 3000,
      processes: 6000,
      thermals: 15000,
      gpus: 4000,
      storage: 60000
    }
  }
  if (name === "fast" || name === "responsive") {
    return {
      name: "Fast",
      resources: 750,
      processes: 1500,
      thermals: 5000,
      gpus: 1000,
      storage: 15000
    }
  }
  return {
    name: "Balanced",
    resources: 1500,
    processes: 3000,
    thermals: 10000,
    gpus: 2000,
    storage: 30000
  }
}

function formatTemperature(value, unit) {
  var celsius = Number(value)
  if (!isFinite(celsius)) return "—"
  var fahrenheit = String(unit || "Celsius").toLowerCase() === "fahrenheit"
  var displayed = fahrenheit ? celsius * 9 / 5 + 32 : celsius
  return Math.round(displayed) + (fahrenheit ? "°F" : "°C")
}

function temperatureRank(temperature) {
  var chip = String(temperature && temperature.chip || "").toLowerCase()
  var label = String(temperature && temperature.label || "").toLowerCase()
  if (chip === "coretemp" && label.indexOf("package id") >= 0) return 0
  if (chip === "k10temp" && label === "tctl") return 1
  if (label.indexOf("cpu") >= 0 || label.indexOf("package") >= 0 || label === "tctl") return 2
  if (chip === "coretemp" || chip === "k10temp") return 3
  return 100
}

function cpuTemperature(temperatures) {
  var values = Array.isArray(temperatures) ? temperatures : []
  var selected = null
  var selectedRank = 100
  for (var i = 0; i < values.length; i++) {
    var value = number(values[i].value)
    if (value <= 0 || value >= 150) continue
    var rank = temperatureRank(values[i])
    if (rank < selectedRank || (rank === selectedRank && selected && value > selected.value)) {
      selected = values[i]
      selectedRank = rank
    }
  }
  return selectedRank < 100 ? selected : null
}

if (typeof module !== "undefined") {
  module.exports = {
    clamp: clamp,
    emptySnapshot: emptySnapshot,
    emptyMetrics: emptyMetrics,
    emptyProcessSnapshot: emptyProcessSnapshot,
    emptyThermalSnapshot: emptyThermalSnapshot,
    emptyPackagePowerSnapshot: emptyPackagePowerSnapshot,
    emptyPower: emptyPower,
    emptyStorageSnapshot: emptyStorageSnapshot,
    emptyGpuSnapshot: emptyGpuSnapshot,
    parseSnapshot: parseSnapshot,
    parseProcessSnapshot: parseProcessSnapshot,
    parseThermalSnapshot: parseThermalSnapshot,
    parsePackagePowerSnapshot: parsePackagePowerSnapshot,
    parseStorageSnapshot: parseStorageSnapshot,
    parseGpuSnapshot: parseGpuSnapshot,
    packageEnergyReadable: packageEnergyReadable,
    packageCountersComparable: packageCountersComparable,
    packageEnergyDelta: packageEnergyDelta,
    nextPackagePower: nextPackagePower,
    nextGpus: nextGpus,
    counterPercent: counterPercent,
    counterRate: counterRate,
    memoryPercent: memoryPercent,
    swapPercent: swapPercent,
    appendHistory: appendHistory,
    coreUsage: coreUsage,
    selectNetwork: selectNetwork,
    aggregateDisks: aggregateDisks,
    baselineMetrics: baselineMetrics,
    nextMetrics: nextMetrics,
    nextProcesses: nextProcesses,
    processSystemBusyDelta: processSystemBusyDelta,
    estimateProcessPower: estimateProcessPower,
    processIdentityKey: processIdentityKey,
    processActionBlockReason: processActionBlockReason,
    filterAndSortProcesses: filterAndSortProcesses,
    formatBytes: formatBytes,
    formatDuration: formatDuration,
    samplingProfile: samplingProfile,
    formatTemperature: formatTemperature,
    cpuTemperature: cpuTemperature
  }
}
