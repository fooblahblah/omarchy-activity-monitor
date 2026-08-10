# Activity Monitor

Third-party Omarchy bar plugin for a fast system overview and an expandable
process monitor. It is self-contained under the user plugin directory, so
normal packaged Quattro updates do not replace it.

![Expanded Activity Monitor panel with live resource and process data](preview.png)

## Install

```bash
omarchy plugin add https://github.com/stappmus/omarchy-activity-monitor.git --enable
```

Enable or disable it through `Setup > Plugins`, or use:

```bash
omarchy plugin enable stappmus.activity-monitor
omarchy plugin disable stappmus.activity-monitor
```

The compact panel shows CPU, memory, network and disk activity plus the three
busiest processes. Expand it with the button or `e` for per-core activity,
memory, reclaimable cache and swap details, disk storage used and remaining,
search, process sorting, estimated CPU-package watts, and a larger process list.
Your own apps can be asked to close from the expanded view after a confirmation.

The `USED MEMORY` percentage follows Linux's available-memory accounting:
`(MemTotal - MemAvailable) / MemTotal`. The expanded `RECLAIMABLE CACHE` value
is `Cached + SReclaimable`, matching `free`'s cache column. Linux can reuse
that cache automatically when applications need RAM, so it is not an extra
amount to add to used memory.

The expanded CPU card shows the measured total CPU-package watts. Individual
process rows show their estimated share of that total.

Keyboard shortcuts in the expanded view:

- `j` / `k`: select a process
- `/`: search
- `c` / `m` / `w` / `p` / `t` / `n`: sort by CPU, memory, estimated watts,
  PID, runtime, or name
- `h` / `l`: cycle sort columns
- `r`: refresh
- `x`: confirm closing the explicitly selected app
- `e` or `Esc`: collapse

The widget keeps one stdin-driven plugin-local stats reader alive only
while its panel is open. Resource, process, temperature, and storage requests
retain their independent refresh cadences without repeatedly launching
collectors. Its process scanner starts lazily with the first process request
and is then reused for the rest of the panel session. It reads Linux
procfs/sysfs directly, requires no monitoring daemon, and hides measurements
the hardware does not expose.

App actions use a PID file descriptor plus the sampled process start time,
resolve worker processes to a verified same-user app ancestor, reject foreign
and protected processes, and never invoke a shell or privilege prompt. The
confirmation discloses that an app still running after a three-second graceful
close window will be force-closed.

`EST. W` is an interval estimate (three seconds by default): measured RAPL CPU
package energy is assigned by each process's CPU-time share. It is
intentionally marked with `~` because Linux exposes energy for hardware
domains, not individual processes. Package coverage is processor-specific and
can include cores, uncore, integrated graphics, and on-chip interfaces; it does
not represent wall, display, storage, network, or audio power. Energy sampling
runs only while the advanced view is expanded. The plugin reads RAPL directly
when the kernel exposes it to the user. On systems where RAPL is root-only, an
optional root-owned companion helper may be installed; the plugin never opens
a privilege prompt while sampling. Unsupported hardware or an unavailable
reader shows `—`.

### Optional root-only RAPL reader

The base plugin needs no package or elevated access. If your kernel exposes
RAPL energy counters only to root, build the optional helper package:

```bash
git clone https://github.com/stappmus/omarchy-activity-monitor.git
cd omarchy-activity-monitor
makepkg --cleanbuild --install
```

That package installs one immutable collector copy and one narrow sudoers rule
which permits only its power-reader mode. The panel uses `sudo -n`, so it never
opens a password prompt. Remove it independently with:

```bash
sudo pacman -Rns omarchy-activity-monitor-power-helper
```

## Structure

- `Panel.qml` owns layout, keyboard/pointer interaction, selection, and sorting.
- `ActivityController.qml` owns reader processes, framing, refresh timers,
  watchdogs, derived samples, and the explicit user/root power-reader state.
- `ProcessActionController.qml` owns confirmation state and guarded helper
  execution for app actions.
- `Model.js` contains snapshot factories, parsers, calculations, formatting,
  sorting, and side-effect-free UI policy helpers.

Resource, thermal, storage, package-energy, and derived-metric models remain
separate rather than being merged into a catch-all snapshot. The QML action
policy only provides immediate feedback; the plugin-local process helper always
revalidates live procfs identity, ownership, state, and protection before it
signals anything. All helpers live at the plugin root and are addressed by
absolute plugin-relative paths, avoiding dependence on Omarchy's packaged
command tree.

## Remove

```bash
omarchy plugin remove stappmus.activity-monitor
```

## Test

```bash
./test/all.sh
qmllint -I /usr/share/omarchy/shell ActivityController.qml Panel.qml ProcessActionController.qml Sparkline.qml
omarchy plugin validate .
makepkg --verifysource
```

Licensed under the MIT License. The panel began as an Omarchy activity-panel
implementation and is maintained as an independent plugin by Kristoffer
Haugland.
