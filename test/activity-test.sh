#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const activity = requireFromRoot('Model.js')

const first = activity.parseSnapshot([
  'schema\tactivity-resources\t1',
  'sample\t1000',
  'frequency\tcpu\t2400\tMHz',
  'frequency\tmemory\t6400\tMT/s',
  'cpu\tcpu\t1000\t700',
  'cpu\tcpu0\t500\t350',
  'cpu\tcpu1\t500\t350',
  'memory\t1000\t400\t200\t150\t125',
  'tasks\t2\t100',
  'network\teth0\t10000\t20000\tup\t1\t1',
  'network\ttailscale0\t500000\t600000\tup\t0\t0',
  'disk\t8:0\tsda\t100\t200',
  ''
].join('\n'))

assertEqual(first.sample, 1000, 'activity parses the monotonic resource sample')
assertEqual(first.cpuFrequencyMHz, 2400, 'activity parses the average current CPU clock')
assertEqual(first.memorySpeedMTs, 6400, 'activity parses the configured DDR transfer rate')
assertEqual(first.cores.length, 2, 'activity parses per-core counters')
assertEqual(first.memory.cached, 125 * 1024, 'activity parses reclaimable cache')
assertEqual(first.memory.swapTotal, 200 * 1024, 'activity parses swap counters')
assertEqual(
  activity.parseSnapshot('schema\tactivity-processes\t1\nsample\t1000\n').schema,
  0,
  'activity rejects a mismatched snapshot contract'
)

const second = activity.parseSnapshot([
  'schema\tactivity-resources\t1',
  'sample\t1001',
  'frequency\tcpu\t2600\tMHz',
  'frequency\tmemory\t6400\tMT/s',
  'cpu\tcpu\t1200\t800',
  'cpu\tcpu0\t600\t390',
  'cpu\tcpu1\t600\t410',
  'memory\t1000\t350\t200\t100\t120',
  'tasks\t3\t110',
  'network\teth0\t12048\t21024\tup\t1\t1',
  'network\ttailscale0\t900000\t1000000\tup\t0\t0',
  'disk\t8:0\tsda\t108\t204',
  ''
].join('\n'))

const metrics = activity.nextMetrics(first, second, {}, 2)
assertEqual(metrics.cpu, 50, 'activity derives CPU usage from counter deltas')
assertEqual(metrics.memory, 65, 'activity derives memory usage')
assertEqual(metrics.swap, 50, 'activity derives swap usage')
assertEqual(metrics.download, 2048, 'activity derives network receive rate')
assertEqual(metrics.upload, 1024, 'activity derives network transmit rate')
assertEqual(metrics.diskRead, 4096, 'activity derives disk read rate')
assertEqual(metrics.diskWrite, 2048, 'activity derives disk write rate')
assertEqual(metrics.cores[0].usage, 60, 'activity derives per-core usage')
assertEqual(metrics.networkInterface, 'eth0', 'activity follows the default interface without double-counting tunnels')

const withHistory = activity.nextMetrics(second, second, {
  cpuHistory: [10, 20],
  memoryHistory: [30, 40]
}, 2)
assertDeepEqual(withHistory.cpuHistory, [20, 0], 'activity caps history buffers')
assertEqual(activity.counterPercent({ total: 100, idle: 20 }, { total: 50, idle: 10 }), 0, 'activity handles reset CPU counters')
assertEqual(activity.counterRate(100, 50, 1), 0, 'activity handles reset byte counters')

const baseline = activity.baselineMetrics(second, {
  cpu: 42,
  download: 100,
  upload: 50,
  diskRead: 25,
  diskWrite: 10,
  cpuHistory: [20, 42],
  memoryHistory: [60, 65]
})
assertEqual(baseline.cpu, 42, 'activity retains the last CPU rate while taking a fresh baseline')
assertEqual(baseline.memory, 65, 'activity immediately refreshes single-sample memory usage')
assertDeepEqual(baseline.cpuHistory, [20, 42], 'activity does not add zeroes while taking a fresh baseline')

const firstProcesses = activity.parseProcessSnapshot([
  'schema\tactivity-processes\t1',
  'sample\t100\t100',
  'process\t42\talice\tS\t1000\t500\t100\tcode helper',
  ''
].join('\n'))
const secondProcesses = activity.parseProcessSnapshot([
  'schema\tactivity-processes\t1',
  'sample\t102\t100',
  'process\t42\talice\tR\t1000\t600\t100\tcode helper',
  ''
].join('\n'))
const sampledProcesses = activity.nextProcesses(firstProcesses, secondProcesses, 1000 * 1024)
assertEqual(sampledProcesses[0].name, 'code helper', 'activity preserves process names with spaces')
assertEqual(sampledProcesses[0].user, 'alice', 'activity resolves process users')
assertEqual(sampledProcesses[0].cpu, 50, 'activity derives sampled process CPU')
assertEqual(sampledProcesses[0].memory, 10, 'activity derives process memory share')
assertEqual(sampledProcesses[0].elapsed, 92, 'activity derives process runtime from monotonic uptime')
const reusedPid = activity.parseProcessSnapshot(
  'schema\tactivity-processes\t1\nsample\t104\t100\nprocess\t42\talice\tR\t2000\t900\t100\tnew process\n'
)
assertEqual(
  activity.nextProcesses(secondProcesses, reusedPid, 1000 * 1024)[0].cpu,
  0,
  'activity does not carry CPU history across PID reuse'
)

const processes = [
  { pid: 3, name: 'firefox', user: 'alice', cpu: 4, memory: 10, elapsed: 50 },
  { pid: 1, name: 'quickshell', user: 'alice', cpu: 8, memory: 2, elapsed: 100 },
  { pid: 2, name: 'postgres', user: 'postgres', cpu: 1, memory: 20, elapsed: 200 }
]
assertDeepEqual(
  activity.filterAndSortProcesses(processes, '', 'cpu', false).map(process => process.pid),
  [1, 3, 2],
  'activity sorts processes by CPU'
)
assertDeepEqual(
  activity.filterAndSortProcesses(processes, 'post', 'memory', false).map(process => process.pid),
  [2],
  'activity filters processes by name and user'
)
assertEqual(
  activity.processIdentityKey({ pid: 42, startTicks: 1234 }),
  '42:1234',
  'activity ties process selection to PID and sampled start time'
)
assertEqual(
  activity.processActionBlockReason(
    { pid: 42, startTicks: 1234, state: 'S', user: 'alice', name: 'firefox' },
    'alice'
  ),
  '',
  'activity allows an actionable same-user app'
)
assertEqual(
  activity.processActionBlockReason(
    { pid: 42, startTicks: 1234, state: 'S', user: 'alice', name: 'quickshell' },
    'alice'
  ),
  'Desktop session is protected',
  'activity gives immediate feedback for a protected session process'
)
assertEqual(
  activity.processActionBlockReason(
    { pid: 42, startTicks: 1234, state: 'S', user: 'root', name: 'worker' },
    'alice'
  ),
  'Only your own processes can be ended',
  'activity gives immediate feedback for a foreign process'
)
assertEqual(activity.formatBytes(1536, '/s'), '1.50 KiB/s', 'activity formats byte rates')
assertEqual(activity.formatDuration(42), '42s', 'activity formats short process runtimes')
assertEqual(activity.formatDuration(90061), '1d 1h', 'activity formats long durations')
assertEqual(activity.samplingProfile('Efficient').resources, 3000, 'activity offers a low-overhead sampling profile')
assertEqual(activity.samplingProfile('Balanced').processes, 3000, 'activity keeps the balanced process cadence')
assertEqual(activity.samplingProfile('Fast').resources, 750, 'activity offers a responsive sampling profile')
assertEqual(activity.samplingProfile('unknown').name, 'Balanced', 'activity safely defaults unknown sampling profiles')
assertEqual(activity.formatTemperature(20, 'Celsius'), '20°C', 'activity formats Celsius temperatures')
assertEqual(activity.formatTemperature(20, 'Fahrenheit'), '68°F', 'activity converts temperatures to Fahrenheit')
const manifest = requireFromRoot('manifest.json')
const settingKeys = manifest.barWidget.schema.map(entry => entry.key)
assertDeepEqual(
  settingKeys,
  ['samplingSpeed', 'historySamples', 'temperatureUnit', 'showFrequencies', 'openExpanded', 'processPowerEnabled'],
  'activity publishes the same focused preferences offered by its settings menu'
)
JS

snapshot=$("$ROOT/activity-stats" --activity-resources)
grep -Eq '^schema[[:space:]]+activity-resources[[:space:]]+1$' <<<"$snapshot" || fail "activity collector emits its schema"
grep -Eq '^sample[[:space:]][0-9]+([.][0-9]+)?$' <<<"$snapshot" || fail "activity collector emits a monotonic sample"
grep -Eq '^cpu[[:space:]]+cpu[[:space:]]' <<<"$snapshot" || fail "activity collector emits CPU counters"
grep -Eq '^memory[[:space:]]' <<<"$snapshot" || fail "activity collector emits memory counters"
grep -Eq '^network[[:space:]]' <<<"$snapshot" || fail "activity collector emits network counters"
grep -Eq '^disk[[:space:]]' <<<"$snapshot" || fail "activity collector emits disk counters"
pass "activity collector emits the resource snapshot contract"

gpu_snapshot=$("$ROOT/activity-stats" --activity-gpus)
grep -Eq '^schema[[:space:]]+activity-gpus[[:space:]]+1$' <<<"$gpu_snapshot" ||
  fail "activity GPU collector emits its schema"
grep -Eq '^sample[[:space:]][0-9]+([.][0-9]+)?$' <<<"$gpu_snapshot" ||
  fail "activity GPU collector emits a monotonic sample"
pass "activity collector emits the independent GPU snapshot contract"

process_snapshot=$("$ROOT/activity-stats" --activity-processes)
grep -Eq '^schema[[:space:]]+activity-processes[[:space:]]+1$' <<<"$process_snapshot" || fail "activity process collector emits its schema"
grep -Eq '^sample[[:space:]][0-9]+([.][0-9]+)?[[:space:]][0-9]+[[:space:]][0-9]+$' <<<"$process_snapshot" ||
  fail "activity process collector emits its sample and CPU clocks"
grep -Eq '^process[[:space:]]' <<<"$process_snapshot" || fail "activity process collector emits process rows"
pass "activity collector emits the process snapshot contract"

[[ -x $ROOT/activity-sampler ]] || fail "native activity sampler is executable"
[[ $("$ROOT/activity-sampler" --version) == "activity-sampler 2.1.1" ]] ||
  fail "native activity sampler reports the release protocol version"
[[ ! -e $ROOT/activity-process-stats ]] ||
  fail "legacy process helper remains beside the unified native sampler"
pass "activity ships one native sampler instead of a process-helper chain"

reader_snapshot=$(
  printf 'resources\nprocesses\nprocesses\nthermals\ngpus\nstorage\n' |
    "$ROOT/activity-stats" --activity-reader
)
[[ $(grep -c '^snapshot-end' <<<"$reader_snapshot") -eq 6 ]] ||
  fail "activity reader does not frame every requested snapshot"
grep -Fq $'snapshot-end\tresources' <<<"$reader_snapshot" ||
  fail "activity reader does not frame resource snapshots"
grep -Fq $'snapshot-end\tprocesses' <<<"$reader_snapshot" ||
  fail "activity reader does not frame process snapshots"
[[ $(grep -c $'^snapshot-end\tprocesses$' <<<"$reader_snapshot") -eq 2 ]] ||
  fail "activity reader does not serve repeated process snapshots"
grep -Fq $'snapshot-end\tthermals' <<<"$reader_snapshot" ||
  fail "activity reader does not frame thermal snapshots"
grep -Fq $'snapshot-end\tgpus' <<<"$reader_snapshot" ||
  fail "activity reader does not frame GPU snapshots"
grep -Fq $'snapshot-end\tstorage' <<<"$reader_snapshot" ||
  fail "activity reader does not frame storage snapshots"
pass "activity reader serves independently requested snapshots in one native process"

coproc SELF_READER { exec "$ROOT/activity-stats" --activity-reader; }
self_reader_pid=$SELF_READER_PID
self_reader_input=${SELF_READER[1]}
self_reader_output=${SELF_READER[0]}
self_reader_snapshot=""
printf 'processes\n' >&"$self_reader_input"
while IFS= read -r -u "$self_reader_output" line; do
  [[ $line == $'snapshot-end\tprocesses' ]] && break
  self_reader_snapshot+="$line"$'\n'
done
process_children=$(<"/proc/$self_reader_pid/task/$self_reader_pid/children")
[[ -z $process_children ]] ||
  fail "native activity reader spawned a child collector"

printf 'processes\n' >&"$self_reader_input"
while IFS= read -r -u "$self_reader_output" line; do
  [[ $line == $'snapshot-end\tprocesses' ]] && break
done
process_children=$(<"/proc/$self_reader_pid/task/$self_reader_pid/children")
[[ -z $process_children ]] ||
  fail "native activity reader spawned a child between process snapshots"

exec {self_reader_input}>&-
wait "$self_reader_pid"
pass "activity reader keeps all unprivileged sampling in one native process"

if grep -Fq $'process\t'"$self_reader_pid"$'\t' <<<"$self_reader_snapshot"; then
  fail "activity reader reports its own sampling process as workload"
fi
pass "activity reader excludes its own sampling process"

fixture_root=$(mktemp -d)
trap 'rm -rf -- "$fixture_root"' EXIT

mkdir -p "$fixture_root/proc/101" "$fixture_root/proc/102" "$fixture_root/proc/103"
printf '200.00 100.00\n' >"$fixture_root/proc/uptime"
printf '%s\n' \
  '101 (worker task) R 1 1 1 0 -1 0 0 0 0 0 12 8 0 0 20 0 3 0 1000 4096000 25' \
  >"$fixture_root/proc/101/stat"
printf 'Name:\tworker task\nUid:\t1000\t1000\t1000\t1000\nVmRSS:\t120 kB\n' \
  >"$fixture_root/proc/101/status"
printf '%s\n' \
  '103 (kernel worker) I 2 0 0 0 0 2097152 0 0 0 0 0 0 0 0 20 0 1 0 1000 0 0' \
  >"$fixture_root/proc/103/stat"
printf 'alice:x:1000:1000:Alice:/home/alice:/bin/bash\n' >"$fixture_root/passwd"

fixture_process_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$fixture_root/proc" \
    OMARCHY_SYSTEM_STATS_PASSWD_PATH="$fixture_root/passwd" \
    OMARCHY_SYSTEM_STATS_CLOCK_TICKS=100 \
    OMARCHY_SYSTEM_STATS_PAGE_SIZE=4096 \
    "$ROOT/activity-stats" --activity-processes
)
grep -Fq $'process\t101\talice\tR\t1000\t20\t100\tworker task' \
  <<<"$fixture_process_snapshot" || fail "activity process collector reads a stable fixture process"
[[ $(grep -c '^process' <<<"$fixture_process_snapshot") -eq 1 ]] ||
  fail "activity process collector did not skip a vanished fixture PID"
pass "activity process collector skips PIDs that vanish during a snapshot"

if grep -Fq $'process\t103\t' <<<"$fixture_process_snapshot"; then
  fail "activity process collector included a kernel thread"
fi
pass "activity process collector omits non-actionable kernel threads"

grep -Fq 'centerOnBar: false' "$ROOT/Panel.qml" ||
  fail "activity panel keeps compact and expanded layouts on the same bar anchor"
pass "activity panel expansion preserves its bar anchor"

grep -Fq 'implicitWidth: button.implicitWidth' "$ROOT/Panel.qml" ||
  fail "activity bar widget does not expose its icon width"
grep -Fq 'implicitHeight: button.implicitHeight' "$ROOT/Panel.qml" ||
  fail "activity bar widget does not expose its icon height"
pass "activity bar widget exposes its icon geometry"

grep -Fq 'id: headerActions' "$ROOT/Panel.qml" ||
  fail "activity temperature and expand controls do not share a header row"
grep -A3 -F 'id: headerActions' "$ROOT/Panel.qml" |
  grep -Fq 'anchors.verticalCenter: parent.verticalCenter' ||
  fail "activity header controls are not vertically centered together"
pass "activity temperature aligns with the header action"

grep -Fq 'implicitHeight: expandButton.implicitHeight' "$ROOT/Panel.qml" ||
  fail "activity temperature does not match the expand button height"
pass "activity temperature matches the expand button height"

panel_file="$ROOT/Panel.qml"
controller_file="$ROOT/ActivityController.qml"
action_controller_file="$ROOT/ProcessActionController.qml"
if grep -Eq 'label: "LOAD"|detail: .*"LOAD ' "$panel_file"; then
  fail "activity panel exposes the Linux load average"
fi
grep -Fq 'root.snapshot.cores.length + " LOGICAL CPUS"' "$panel_file" ||
  fail "activity panel does not replace load with a logical CPU count"
pass "activity uses a plain logical CPU count instead of load average"

grep -Fq 'text: "DISK STORAGE"' "$panel_file" ||
  fail "activity expanded details do not show disk storage"
grep -Fq 'text: root.gpuHeadingText()' "$panel_file" &&
  grep -Fq 'items.push({ label: "USAGE", value: gpuUsageText(adapters[0]) })' "$panel_file" ||
  fail "activity expanded details do not show GPU adapters"
grep -Fq 'return "SHARED"' "$panel_file" ||
  fail "activity panel does not distinguish integrated shared GPU memory"
grep -Fq 'return "VRAM"' "$panel_file" ||
  fail "activity panel does not label dedicated GPU memory"
grep -Fq 'text: "USED"' "$panel_file" ||
  fail "activity storage details do not show used storage"
grep -Fq 'text: "REMAINING"' "$panel_file" ||
  fail "activity storage details do not show remaining storage"
if grep -Fq 'POWER & THERMALS' "$panel_file"; then
  fail "activity expanded details still show power and thermals"
fi
pass "activity replaces power and thermals with disk capacity"

grep -Fq 'ActivityController {' "$panel_file" &&
  grep -Fq 'active: root.opened' "$panel_file" &&
  grep -Fq 'expanded: root.expanded' "$panel_file" ||
  fail "activity panel does not delegate sampling lifecycle to its controller"
grep -Fq 'readonly property var snapshot: _snapshot' "$controller_file" &&
  grep -Fq 'readonly property var processes: _processes' "$controller_file" ||
  fail "activity controller does not expose read-only sampled state"
if grep -Eq '^[[:space:]]*Process[[:space:]]*[{]' "$panel_file"; then
  fail "activity visual panel still owns a helper process"
fi
grep -Fq 'command: [root.statsHelperPath, "--activity-reader"]' "$controller_file" ||
  fail "activity panel does not reuse a single unprivileged stats reader"
grep -Fq 'String(Qt.resolvedUrl("activity-sampler"))' "$controller_file" ||
  fail "activity panel does not launch the native sampler directly"
grep -Fq '? [powerHelperPath]' "$controller_file" ||
  fail "activity panel does not use the persistent guarded CPU-energy reader"
grep -Fq 'if (!active || !expanded || !processPowerEnabled' "$controller_file" &&
  grep -Fq '|| processPowerUnavailable || _processPowerSamplePending) return' "$controller_file" ||
  fail "activity panel samples process power outside the advanced view"
grep -Fq 'onExpandedChanged:' "$controller_file" &&
  grep -Fq 'resetProcessPowerMeasurement()' "$controller_file" ||
  fail "activity panel carries an energy baseline across collapsed time"
grep -Fq 'root.markProcessPowerUnavailable()' "$controller_file" ||
  fail "activity panel does not clear stale watts after an energy read failure"
grep -Fq 'refreshProcessCycle()' "$controller_file" ||
  fail "activity panel does not coordinate energy and process refreshes"
grep -Fq 'id: deadlineScheduler' "$controller_file" &&
  grep -Fq 'function collectDueSnapshots()' "$controller_file" &&
  grep -Fq '_resourceDue = nextDeadline(_resourceDue, refreshInterval, now)' "$controller_file" &&
  grep -Fq '_processDue = nextDeadline(_processDue, processRefreshInterval, now)' "$controller_file" &&
  grep -Fq '_thermalDue = nextDeadline(_thermalDue, thermalRefreshInterval, now)' "$controller_file" &&
  grep -Fq '_gpuDue = nextDeadline(_gpuDue, gpuRefreshInterval, now)' "$controller_file" &&
  grep -Fq '_storageDue = nextDeadline(_storageDue, storageRefreshInterval, now)' "$controller_file" ||
  fail "activity panel does not coalesce its independent deadlines"
if grep -Fq 'repeat: true' "$controller_file"; then
  fail "activity panel still wakes separate recurring timers"
fi
grep -Fq 'id: statsReaderWatchdog' "$controller_file" &&
  grep -Fq 'id: processPowerWatchdog' "$controller_file" ||
  fail "activity readers can remain stuck indefinitely"
grep -Fq 'powerStateSwitchingRoot: "switching-root"' "$controller_file" &&
  grep -Fq 'readonly property string processPowerState: _processPowerState' "$controller_file" ||
  fail "activity power reader lifecycle is not represented by an explicit state"
if grep -Eq 'processPowerRestartWithSudo|processPowerUseSudo|processPowerReaderReady[[:space:]]*:' "$controller_file"; then
  fail "activity power reader still uses overlapping lifecycle booleans"
fi
if grep -Eq 'activity-package-power|refreshPackagePower|packagePowerProc' "$controller_file"; then
  fail "activity panel still polls package power"
fi
grep -Fq 'if (expanded) sendStatsRequest("gpus")' "$controller_file" &&
  grep -Fq '_gpuDue = 0' "$controller_file" &&
  grep -Fq 'resetGpuMeasurement()' "$controller_file" ||
  fail "activity panel samples GPU details while the advanced view is collapsed"
grep -Fq '_metrics = Model.baselineMetrics(next, metrics)' "$controller_file" &&
  grep -Fq 'function resetSessionSampling()' "$controller_file" &&
  grep -Fq 'if (_gpus.length === 0)' "$controller_file" ||
  fail "activity panel does not retain valid display data while taking fresh baselines"
if grep -Fq '    _snapshot = Model.emptySnapshot()' "$controller_file" ||
   grep -Fq '    _processes = []' "$controller_file" ||
   grep -Fq '    _gpus = []' "$controller_file"; then
  fail "activity panel clears stale display data when a sampling session changes"
fi
pass "activity controller coalesces deadlines and refreshes retained values without blanking"

grep -Fq 'text: "EST. W"' "$panel_file" ||
  fail "activity process table does not label estimated CPU watts"
grep -Fq 'root.measuredPackagePowerText(root.processPower.watts) + " PACKAGE · "' "$panel_file" ||
  fail "activity CPU summary does not expose measured total CPU-package power"
grep -Fq 'return "~" + watts.toFixed' "$panel_file" ||
  fail "activity process watts are not visibly marked as estimates"
grep -Fq 'root.setSort("power")' "$panel_file" ||
  fail "activity process power cannot be sorted"
grep -Fq 'if (nextKey === "power" && (!powerEstimatesEnabled || !processPower.available)) return' "$panel_file" ||
  fail "activity process power sorting remains active without a measurement"
grep -Fq 'showProcessUserColumn' "$panel_file" &&
  grep -Fq 'showProcessTimeColumn' "$panel_file" ||
  fail "activity process table does not adapt its optional columns on narrow screens"
grep -Fq 'model: root.sortedProcesses' "$panel_file" ||
  fail "activity process table silently caps the virtualized process list"
grep -Fq 'Model.formatBytes(snapshot.memory.cached)' "$panel_file" ||
  fail "activity panel does not expose reclaimable memory cache"
[[ $(grep -Fc 'label: root.memoryCardLabel()' "$panel_file") -eq 2 ]] ||
  fail "activity panel does not place RAM speed in both card headings"
[[ $(grep -Fc 'label: root.cpuCardLabel()' "$panel_file") -eq 2 ]] ||
  fail "activity panel does not place CPU frequency in both card headings"
grep -Fq 'function memoryBreakdownText()' "$panel_file" &&
  grep -Fq 'if (usedUnit && usedUnit === cacheUnit)' "$panel_file" &&
  grep -Fq '" · CACHE " + cacheText' "$panel_file" ||
  fail "activity RAM card does not show used memory and cache together"
grep -Fq 'snapshot.memorySpeedMTs, "MT/s"' "$panel_file" &&
  grep -Fq 'snapshot.cpuFrequencyMHz, "MHz"' "$panel_file" &&
  grep -Fq 'var frequency = gpuFrequencyText(adapters[0])' "$panel_file" &&
  grep -Fq 'if (frequency === 0) return "IDLE"' "$panel_file" ||
  fail "activity card headings do not distinguish DDR transfer rate from CPU and GPU clocks"
grep -Fq 'label: "RAM TOTAL"' "$panel_file" ||
  fail "activity system details do not retain total RAM"
grep -Fq 'label: "CORES"' "$panel_file" ||
  fail "activity system details lose the logical core count"
grep -Fq 'badge: root.swapBadgeText()' "$panel_file" &&
  grep -Fq 'return snapshot.memory.swapTotal ? "SWAP " + percentText(metrics.swap) : "NO SWAP"' "$panel_file" ||
  fail "activity disk card does not expose swap usage"
if grep -Fq 'label: "SWAP"' "$panel_file"; then
  fail "activity system details still contain the displaced swap reading"
fi
grep -Fq 'id: settingsContent' "$panel_file" &&
  grep -Fq 'label: "Update speed"' "$panel_file" &&
  grep -Fq 'label: "Graph history"' "$panel_file" &&
  grep -Fq 'label: "Temperature"' "$panel_file" &&
  grep -Fq 'function persistSettings(values)' "$panel_file" &&
  grep -Fq 'root.bar.shell.updateEntryInline(root.moduleName, entry)' "$panel_file" ||
  fail "activity panel does not expose persistent personalization controls"
grep -Fq 'processPowerEnabled: root.powerEstimatesEnabled' "$panel_file" &&
  grep -Fq 'onProcessPowerEnabledChanged:' "$controller_file" &&
  grep -Fq 'visible: !compact && root.powerEstimatesEnabled' "$panel_file" ||
  fail "activity power preference does not stop sampling and simplify the process table"
if grep -Fq 'text: "POWER"' "$panel_file"; then
  fail "activity presents estimated per-process power as an exact measurement"
fi
pass "activity clearly labels and sorts estimated per-process CPU power"

grep -Fq 'if (cursorActive && selectedProcessIndex === index) return' "$panel_file" ||
  fail "activity process rows remap pointer coordinates after already being selected"
grep -Fq 'hoverEnabled: !compact' "$panel_file" ||
  fail "activity compact process rows subscribe to unused hover movement"
if grep -Fq 'animateCursor: true' "$panel_file"; then
  fail "activity process row selection starts multi-frame hover animations"
fi
pass "activity process rows avoid input-rate pointer and animation work"

grep -Fq 'ConfirmDialog {' "$panel_file" ||
  fail "activity process actions are not confirmed"
grep -Fq 'processConfirm.selectedIndex = 0' "$panel_file" ||
  fail "activity process confirmation does not default to Cancel"
grep -Fq 'if (!root.settingsOpen && !processActions.confirmationOpen && root.cursorActive)' "$panel_file" ||
  fail "activity process shortcut can act without an explicit selection"
grep -Fq 'ProcessActionController {' "$panel_file" &&
  grep -Fq 'active: root.opened' "$panel_file" &&
  grep -Fq 'enabled: root.expanded && !root.settingsOpen' "$panel_file" ||
  fail "activity panel does not delegate guarded app actions to their controller"
grep -Fq 'Model.processIdentityKey' "$panel_file" ||
  fail "activity process selection is not tied to its sampled start time"
grep -Fq 'signalHelperPath,' "$action_controller_file" ||
  fail "activity panel does not use the guarded process signal helper"
grep -Fq 'action: "APP_TERM"' "$action_controller_file" ||
  fail "activity panel does not resolve worker processes to their parent app"
grep -Fq 'confirmText: "End app"' "$panel_file" ||
  fail "activity panel does not describe the app-wide process action"
grep -Fq 'Force-closes it after 3 seconds if needed.' "$panel_file" ||
  fail "activity panel does not disclose force-close escalation"
grep -Fq '"hyprland"' "$ROOT/Model.js" ||
  fail "activity panel does not protect the desktop compositor"
grep -Fq '"systemd-executo"' "$ROOT/Model.js" ||
  fail "activity panel does not protect the kernel-truncated systemd executor name"
grep -Fq 'disposition === "graceful"' "$action_controller_file" &&
  grep -Fq 'disposition === "escalated"' "$action_controller_file" ||
  fail "activity app action status does not distinguish normal and forced closure"
if grep -Eq 'bash[[:space:]]+-c|pkexec' "$panel_file" "$action_controller_file"; then
  fail "activity process actions invoke a shell or privilege prompt"
fi
pass "activity app actions use guarded identity and safe confirmation"
