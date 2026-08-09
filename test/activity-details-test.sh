#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const activity = requireFromRoot('Model.js')

const storage = activity.parseStorageSnapshot([
  'schema\tactivity-storage\t1',
  'sample\t99.75',
  'storage\t/\t4096000\t3072000\t819200',
  ''
].join('\n'))

assertEqual(storage.schema, 1, 'activity parses the storage schema version')
assertEqual(storage.sample, 99.75, 'activity parses the storage monotonic sample')
assertEqual(storage.path, '/', 'activity identifies the root filesystem')
assertEqual(storage.total, 4096000, 'activity parses total storage bytes')
assertEqual(storage.used, 3072000, 'activity parses used storage bytes')
assertEqual(storage.available, 819200, 'activity parses user-available storage bytes')

const invalidStorage = activity.parseStorageSnapshot(
  'schema\tactivity-storage\t1\nstorage\t/\t100\t120\t110\n'
)
assertEqual(invalidStorage.used, 100, 'activity bounds used storage by filesystem size')
assertEqual(invalidStorage.available, 100, 'activity bounds available storage by filesystem size')

const thermals = activity.parseThermalSnapshot([
  'schema\tactivity-thermals\t1',
  'sample\t100.25',
  'temperature\thwmon0/temp1\tcoretemp\tPackage id 0\t62500',
  ''
].join('\n'))

assertEqual(thermals.schema, 1, 'activity parses the thermal schema version')
assertEqual(thermals.sample, 100.25, 'activity parses the thermal monotonic sample')
assertEqual(thermals.temperatures[0].value, 62.5, 'activity parses the CPU temperature')

const resources = activity.parseSnapshot(
  'schema\tactivity-resources\t1\nsample\t100.00\nmemory\tMemTotal\t1024\n'
)
assertEqual(
  activity.cpuTemperature(thermals.temperatures).label,
  'Package id 0',
  'activity selects CPU temperature from its independent thermal snapshot'
)
assertEqual(
  Object.prototype.hasOwnProperty.call(resources, 'temperatures'),
  false,
  'activity keeps thermal state out of resource snapshots'
)
assertDeepEqual(
  activity.emptyPower(),
  { available: false, watts: -1 },
  'activity exposes a dedicated empty power model'
)

const firstPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t200',
  'package\tintel-rapl:0\tpackage-0\t2000000\t10000000',
  'package\tintel-rapl:1\tpackage-1\t4000000\t20000000',
  ''
].join('\n'))
const secondPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t202',
  'package\tintel-rapl:0\tpackage-0\t6000000\t10000000',
  'package\tintel-rapl:1\tpackage-1\t10000000\t20000000',
  ''
].join('\n'))
const power = activity.nextPackagePower(firstPower, secondPower)
assertEqual(power.watts, 5, 'activity sums package power from raw energy deltas')
assertEqual(power.available, true, 'activity exposes complete multi-package measurements')
assertEqual(
  activity.packageEnergyReadable(secondPower),
  true,
  'activity accepts a complete set of readable package counters'
)

const metadataOnlyPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t203',
  'package\tintel-rapl:0\tpackage-0\t\t10000000',
  ''
].join('\n'))
const metadataOnlyDerived = activity.nextPackagePower(activity.emptyPackagePowerSnapshot(), metadataOnlyPower)
assertEqual(metadataOnlyPower.packages[0].energy, -1, 'activity marks an unreadable energy counter')
assertEqual(metadataOnlyDerived.available, false, 'activity does not invent watts without an energy counter')
assertEqual(
  activity.packageEnergyReadable(metadataOnlyPower),
  false,
  'activity rejects package metadata without a readable energy counter'
)

const beforeWrap = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t300\npackage\tintel-rapl:0\tpackage-0\t9000000\t10000000\n'
)
const afterWrap = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t302\npackage\tintel-rapl:0\tpackage-0\t1000000\t10000000\n'
)
assertEqual(
  activity.nextPackagePower(beforeWrap, afterWrap).watts,
  1,
  'activity handles a RAPL energy counter wrap'
)

const beforeReset = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t600\npackage\tintel-rapl:0\tpackage-0\t6000000\t10000000\n'
)
const afterReset = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t602\npackage\tintel-rapl:0\tpackage-0\t1000000\t10000000\n'
)
assertEqual(
  activity.nextPackagePower(beforeReset, afterReset).watts,
  -1,
  'activity rejects a decreasing RAPL counter away from its wrap boundary'
)
assertEqual(
  activity.packageEnergyDelta(beforeReset.packages[0], afterReset.packages[0]),
  0,
  'activity treats a decreasing mid-range RAPL counter as reset'
)

const beforeMultiSocketPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t200',
  'package\tintel-rapl:0\tpackage-0\t2000000\t10000000',
  'package\tintel-rapl:1\tpackage-1\t4000000\t20000000',
  ''
].join('\n'))
const partialSocketPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t202',
  'package\tintel-rapl:0\tpackage-0\t6000000\t10000000',
  'package\tintel-rapl:1\tpackage-1\t\t20000000',
  ''
].join('\n'))
assertEqual(
  activity.nextPackagePower(beforeMultiSocketPower, partialSocketPower).available,
  false,
  'activity does not present partial multi-socket energy as whole-system power'
)
assertEqual(
  activity.packageEnergyReadable(partialSocketPower),
  false,
  'activity retries privilege when any processor package is unreadable'
)

const changedRange = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t304\npackage\tintel-rapl:0\tpackage-0\t2000000\t20000000\n'
)
assertEqual(
  activity.nextPackagePower(afterWrap, changedRange).watts,
  -1,
  'activity treats a changed RAPL range as a new counter'
)
assertEqual(
  activity.packageEnergyDelta(afterWrap.packages[0], changedRange.packages[0]),
  0,
  'activity rejects a changed RAPL counter range'
)
const beforePackageWrap = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t500\npackage\tintel-rapl:0\tpackage-0\t9000000\t10000000\n'
)
const afterPackageWrap = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t502\npackage\tintel-rapl:0\tpackage-0\t1000000\t10000000\n'
)
assertEqual(
  activity.nextPackagePower(beforePackageWrap, afterPackageWrap).watts,
  1,
  'activity process power handles a package energy counter wrap'
)

const firstProcessPowerSample = activity.parseProcessSnapshot([
  'schema\tactivity-processes\t1',
  'sample\t400\t100\t10000',
  'process\t10\t1000\tS\t100\t1000\t100\tbrowser',
  ''
].join('\n'))
const secondProcessPowerSample = activity.parseProcessSnapshot([
  'schema\tactivity-processes\t1',
  'sample\t402\t100\t10200',
  'process\t10\t1000\tR\t100\t1100\t100\tbrowser',
  ''
].join('\n'))
const sampledPowerProcesses = activity.nextProcesses(
  firstProcessPowerSample,
  secondProcessPowerSample,
  1000
)
assertEqual(secondProcessPowerSample.systemBusyTicks, 10200, 'activity parses aggregate system busy ticks')
assertEqual(sampledPowerProcesses[0].cpuTicksDelta, 100, 'activity retains a process CPU tick delta')
assertEqual(
  activity.processSystemBusyDelta(firstProcessPowerSample, secondProcessPowerSample),
  200,
  'activity derives the matching aggregate system busy tick delta'
)

const processRows = [
  { pid: 10, name: 'browser', cpuTicksDelta: 100, memory: 10 },
  { pid: 20, name: 'music', cpuTicksDelta: 50, memory: 5 },
  { pid: 30, name: 'idle', cpuTicksDelta: 25, memory: 1 },
  { pid: 40, name: 'reset', cpuTicksDelta: -25, memory: 2 }
]
const estimatedPower = activity.estimateProcessPower(processRows, 10, 200)
assertEqual(estimatedPower[0].power, 5, 'activity allocates package power by system CPU ticks')
assertEqual(estimatedPower[1].power, 2.5, 'activity allocates a second proportional package power estimate')
assertEqual(estimatedPower[2].power, 1.25, 'activity allocates a third proportional package power estimate')
assertEqual(estimatedPower[3].power, 0, 'activity treats a negative CPU delta as no package share')
assertEqual(
  estimatedPower.reduce((total, process) => total + process.power, 0),
  8.75,
  'activity leaves kernel and unobserved package power unallocated'
)
assert(
  estimatedPower[0] !== processRows[0] && !Object.prototype.hasOwnProperty.call(processRows[0], 'power'),
  'activity process power estimation does not mutate input rows'
)
assertDeepEqual(
  activity.estimateProcessPower(processRows, -1, 200).map(process => process.power),
  [-1, -1, -1, -1],
  'activity marks process power unavailable without a package measurement'
)
assertDeepEqual(
  activity.estimateProcessPower(processRows, 10, 0).map(process => process.power),
  [-1, -1, -1, -1],
  'activity marks process power unavailable across a zero busy interval'
)
assertDeepEqual(
  activity.estimateProcessPower(processRows, 10, -50).map(process => process.power),
  [-1, -1, -1, -1],
  'activity marks process power unavailable after a system counter reset'
)
assertDeepEqual(
  activity.filterAndSortProcesses(estimatedPower, '', 'power', false)
    .map(process => process.pid),
  [10, 20, 30, 40],
  'activity sorts processes by estimated power'
)
const overAccountedPower = activity.estimateProcessPower([
  { pid: 1, cpuTicksDelta: 80 },
  { pid: 2, cpuTicksDelta: 60 }
], 10, 100)
assert(
  Math.abs(overAccountedPower.reduce((total, process) => total + process.power, 0) - 10) < 1e-9,
  'activity caps over-accounted process estimates at measured package power'
)
JS

fixture_root=$(mktemp -d)
trap 'rm -rf -- "$fixture_root"' EXIT

proc_path="$fixture_root/proc"
sys_path="$fixture_root/sys"
hwmon_path="$sys_path/class/hwmon/hwmon0"
powercap_path="$sys_path/class/powercap/intel-rapl"
package_path="$powercap_path/intel-rapl:0"
subzone_path="$powercap_path/intel-rapl:0:0"

mkdir -p \
  "$fixture_root/bin" \
  "$proc_path/net" \
  "$fixture_root/root filesystem" \
  "$sys_path/class/block" \
  "$sys_path/class/net/eth0/device" \
  "$hwmon_path" \
  "$package_path" \
  "$subzone_path"

printf '321.50 100.00\n' >"$proc_path/uptime"
printf 'cpu 100 0 50 800 10 5 5 0 0 0\ncpu0 50 0 25 400 5 2 3 0 0 0\n' >"$proc_path/stat"
printf 'MemTotal: 1024 kB\nMemAvailable: 512 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' >"$proc_path/meminfo"
printf '0.50 0.25 0.10 1/100 123\n' >"$proc_path/loadavg"
printf 'Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\neth0\t00000000\t00000000\t0001\t0\t0\t25\t00000000\t0\t0\t0\n' \
  >"$proc_path/net/route"
printf 'Inter-| Receive | Transmit\n face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\neth0: 1000 1 0 0 0 0 0 0 2000 1 0 0 0 0 0 0\n' \
  >"$proc_path/net/dev"
printf 'up\n' >"$sys_path/class/net/eth0/operstate"
printf 'DRIVER=test\n' >"$sys_path/class/net/eth0/device/uevent"

printf 'coretemp\n' >"$hwmon_path/name"
printf '62500\n' >"$hwmon_path/temp1_input"
printf 'Package id 0\n' >"$hwmon_path/temp1_label"

printf '%s\n' \
  '#!/bin/bash' \
  '[[ $1 == -f && $2 == -c && $4 == -- ]] || exit 64' \
  '[[ $5 == "$OMARCHY_SYSTEM_STATS_EXPECTED_ROOT_PATH" ]] || exit 65' \
  'printf '"'"'4096\t1000\t250\t200\n'"'" \
  >"$fixture_root/bin/stat"
chmod +x "$fixture_root/bin/stat"

storage_snapshot=$(
  PATH="$fixture_root/bin:$PATH" \
    OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_ROOT_PATH="$fixture_root/root filesystem" \
    OMARCHY_SYSTEM_STATS_EXPECTED_ROOT_PATH="$fixture_root/root filesystem" \
    "$ROOT/activity-stats" --activity-storage
)
expected_storage=$'schema\tactivity-storage\t1\nsample\t321.50\nstorage\t/\t4096000\t3072000\t819200'
[[ $storage_snapshot == "$expected_storage" ]] ||
  fail "activity root storage output is exact, versioned, and byte-based" "$storage_snapshot"
pass "activity root storage output is exact, versioned, and byte-based"

thermal_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-thermals
)
expected_thermals=$'schema\tactivity-thermals\t1\nsample\t321.50\ntemperature\thwmon0/temp1\tcoretemp\tPackage id 0\t62500'
[[ $thermal_snapshot == "$expected_thermals" ]] ||
  fail "activity CPU thermal output is exact and versioned" "$thermal_snapshot"
pass "activity CPU thermal output is exact and versioned"

read_thermal_frame() {
  local output_fd="$1"
  local result_name="$2"
  local line
  local -n result="$result_name"
  result=""

  while IFS= read -r -u "$output_fd" line; do
    [[ $line == $'snapshot-end\tthermals' ]] && return 0
    result+="$line"$'\n'
  done
  return 1
}

coproc THERMAL_READER {
  exec env \
    OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-reader
}
thermal_reader_pid=$THERMAL_READER_PID
thermal_reader_input=${THERMAL_READER[1]}
thermal_reader_output=${THERMAL_READER[0]}
printf 'thermals\n' >&"$thermal_reader_input"
read_thermal_frame "$thermal_reader_output" first_thermal_frame ||
  fail "activity thermal reader stopped before its first frame"
grep -Fq $'temperature\thwmon0/temp1\tcoretemp\tPackage id 0\t62500' \
  <<<"$first_thermal_frame" ||
  fail "activity thermal reader did not cache its selected CPU sensor"

rm -- "$hwmon_path/temp1_input"
fallback_hwmon_path="$sys_path/class/hwmon/hwmon1"
mkdir -p "$fallback_hwmon_path"
printf 'k10temp\n' >"$fallback_hwmon_path/name"
printf '55000\n' >"$fallback_hwmon_path/temp1_input"
printf 'Tctl\n' >"$fallback_hwmon_path/temp1_label"
printf 'thermals\n' >&"$thermal_reader_input"
read_thermal_frame "$thermal_reader_output" second_thermal_frame ||
  fail "activity thermal reader stopped before its fallback frame"
exec {thermal_reader_input}>&-
wait "$thermal_reader_pid"
grep -Fq $'temperature\thwmon1/temp1\tk10temp\tTctl\t55000' \
  <<<"$second_thermal_frame" ||
  fail "activity thermal reader did not rescan after its cached sensor vanished"
pass "activity thermal reader caches and safely invalidates its CPU sensor"

resource_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-resources
)
grep -Fxq $'schema\tactivity-resources\t1' <<<"$resource_snapshot" ||
  fail "activity resources output has its own schema"
grep -Fxq $'network\teth0\t1000\t2000\tup\t1\t1' <<<"$resource_snapshot" ||
  fail "activity resources do not follow an up default route without a gateway"
if grep -q '^temperature' <<<"$resource_snapshot"; then
  fail "activity resources output avoids detailed sensor reads"
fi
pass "activity resources output avoids detailed sensor reads"

rm -- "$proc_path/net/route"
resource_without_route=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-resources
)
grep -Fxq $'schema\tactivity-resources\t1' <<<"$resource_without_route" ||
  fail "activity resources fail when optional route metadata is absent"
pass "activity resources tolerate missing optional procfs inputs"

process_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_PASSWD_PATH="$fixture_root/missing-passwd" \
    OMARCHY_SYSTEM_STATS_CLOCK_TICKS=100 \
    "$ROOT/activity-stats" --activity-processes
)
expected_process_snapshot=$'schema\tactivity-processes\t1\nsample\t321.50\t100\t160'
[[ $process_snapshot == "$expected_process_snapshot" ]] ||
  fail "activity process output includes exact aggregate busy ticks" "$process_snapshot"
pass "activity process output includes exact aggregate busy ticks"

printf 'package-0\n' >"$package_path/name"
printf '9000000\n' >"$package_path/energy_uj"
printf '10000000\n' >"$package_path/max_energy_range_uj"
printf 'core\n' >"$subzone_path/name"
printf '0\n' >"$subzone_path/enabled"
printf '1000000\n' >"$subzone_path/energy_uj"
printf '10000000\n' >"$subzone_path/max_energy_range_uj"

psys_path="$powercap_path/intel-rapl:1"
non_package_path="$powercap_path/intel-rapl:2"
uncore_path="$powercap_path/intel-rapl:0:1"
dram_path="$powercap_path/intel-rapl:0:2"
mkdir -p "$psys_path" "$non_package_path" "$uncore_path" "$dram_path"
printf 'psys\n' >"$psys_path/name"
printf '8000000\n' >"$psys_path/energy_uj"
printf '10000000\n' >"$psys_path/max_energy_range_uj"
printf 'dram\n' >"$non_package_path/name"
printf '7000000\n' >"$non_package_path/energy_uj"
printf '10000000\n' >"$non_package_path/max_energy_range_uj"
printf 'uncore\n' >"$uncore_path/name"
printf '6000000\n' >"$uncore_path/energy_uj"
printf '10000000\n' >"$uncore_path/max_energy_range_uj"
printf 'dram\n' >"$dram_path/name"
printf '5000000\n' >"$dram_path/energy_uj"
printf '10000000\n' >"$dram_path/max_energy_range_uj"

process_power_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-process-power
)
expected_process_power=$'schema\tactivity-process-power\t1\nsample\t321.50\npackage\tintel-rapl:0\tpackage-0\t9000000\t10000000'
[[ $process_power_snapshot == "$expected_process_power" ]] ||
  fail "activity process power output is exact and includes only the RAPL package domain" "$process_power_snapshot"
pass "activity process power output is exact and includes only the RAPL package domain"

process_power_reader_snapshot=$(
  printf 'ignored\nsample\nsample\n' |
    OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
      OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
      "$ROOT/activity-stats" --activity-process-power-reader
)
[[ $(grep -c '^snapshot-end' <<<"$process_power_reader_snapshot") -eq 2 ]] ||
  fail "activity process power reader does not frame each requested sample"
[[ $(grep -c '^package' <<<"$process_power_reader_snapshot") -eq 2 ]] ||
  fail "activity process power reader does not reuse its process for requested samples"
pass "activity process power reader serves framed samples until its input closes"
