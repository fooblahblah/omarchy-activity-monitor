import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "stappmus.activity-monitor"
  ipcTarget: "stappmus.activity-monitor"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property bool expanded: false
  property bool cursorActive: false
  property int selectedProcessIndex: 0
  property string selectedProcessKey: ""
  property string processQuery: ""
  property string sortKey: "cpu"
  property bool sortAscending: false
  property Item searchField: null
  property var processViewport: null

  readonly property color foreground: Color.popups.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Color.muted
  readonly property var snapshot: activity.snapshot
  readonly property var storageSnapshot: activity.storageSnapshot
  readonly property var processPower: activity.processPower
  readonly property var processes: activity.processes
  readonly property var metrics: activity.metrics
  readonly property bool processMetricsReady: activity.processMetricsReady
  readonly property bool processPowerUnavailable: activity.processPowerUnavailable
  readonly property bool hasSnapshot: snapshot.sample > 0
  readonly property int processPidColumnWidth: Style.space(54)
  readonly property int processUserColumnWidth: Style.space(96)
  readonly property int processMetricColumnWidth: Style.space(66)
  readonly property bool showProcessUserColumn: panel.contentWidth >= Style.space(650)
  readonly property bool showProcessTimeColumn: panel.contentWidth >= Style.space(560)
  readonly property string processPowerTooltip: processPowerUnavailable
    ? "CPU package energy is unavailable on this system"
    : (processPower.available
        ? "Estimated CPU-time share of measured CPU package power"
        : "Measuring CPU package energy…")
  readonly property var cpuTemperature: Model.cpuTemperature(activity.thermalSnapshot.temperatures)
  readonly property real storageUsedFraction: storageSnapshot.total > 0
    ? Math.max(0, Math.min(1, storageSnapshot.used / storageSnapshot.total))
    : 0
  readonly property var sortedProcesses: expanded
    ? Model.filterAndSortProcesses(processes, processQuery, sortKey, sortAscending)
    : []
  readonly property var topProcesses: expanded
    ? []
    : Model.filterAndSortProcesses(processes, "", "cpu", false).slice(0, 3)
  readonly property var selectedProcess: sortedProcesses.length > 0
    ? sortedProcesses[Math.max(0, Math.min(selectedProcessIndex, sortedProcesses.length - 1))]
    : null

  function refresh() {
    activity.refresh()
  }

  function setExpanded(value) {
    if (!value && processActions.confirmationOpen) processActions.cancel()
    expanded = value
    cursorActive = false
    selectedProcessIndex = 0
    selectedProcessKey = ""
    if (!expanded) processQuery = ""
    if (!expanded && sortKey === "power") {
      sortKey = "cpu"
      sortAscending = false
    }
    Qt.callLater(function() {
      if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function clampProcessCursor() {
    if (sortedProcesses.length === 0) {
      selectedProcessIndex = 0
      selectedProcessKey = ""
      return
    }
    selectedProcessIndex = Math.max(0, Math.min(selectedProcessIndex, sortedProcesses.length - 1))
    selectedProcessKey = Model.processIdentityKey(sortedProcesses[selectedProcessIndex])
  }

  function restoreProcessCursor() {
    if (sortedProcesses.length === 0) {
      selectedProcessIndex = 0
      selectedProcessKey = ""
      return
    }
    if (selectedProcessKey) {
      for (var i = 0; i < sortedProcesses.length; i++) {
        if (Model.processIdentityKey(sortedProcesses[i]) === selectedProcessKey) {
          selectedProcessIndex = i
          return
        }
      }
    }
    clampProcessCursor()
  }

  function selectProcess(index) {
    if (sortedProcesses.length === 0) return
    selectedProcessIndex = Math.max(0, Math.min(sortedProcesses.length - 1, index))
    selectedProcessKey = Model.processIdentityKey(sortedProcesses[selectedProcessIndex])
  }

  function moveProcess(delta) {
    if (!expanded || sortedProcesses.length === 0) return
    cursorActive = true
    selectProcess(selectedProcessIndex + delta)
    pointerGate.reset()
    Qt.callLater(function() {
      if (root.processViewport && root.processViewport.ensureSelected) root.processViewport.ensureSelected()
    })
  }

  function setSort(nextKey) {
    if (nextKey === "power" && !processPower.available) return
    if (sortKey === nextKey) sortAscending = !sortAscending
    else {
      sortKey = nextKey
      sortAscending = nextKey === "name"
    }
  }

  function cycleSort(delta) {
    var keys = processPower.available
      ? ["cpu", "memory", "power", "pid", "runtime", "name"]
      : ["cpu", "memory", "pid", "runtime", "name"]
    var index = keys.indexOf(sortKey)
    if (index < 0) index = 0
    index = (index + delta + keys.length) % keys.length
    setSort(keys[index])
  }

  function focusSearch() {
    if (!expanded || !searchField) return
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function finishSearch() {
    if (searchField) searchField.focus = false
    keyCatcher.forceActiveFocus()
  }

  function percentText(value) {
    return Math.round(Number(value) || 0) + "%"
  }

  function pressureColor(value) {
    return Number(value) >= 90 ? urgent : accent
  }

  function estimatedPowerText(value) {
    var watts = Number(value)
    if (!isFinite(watts) || watts < 0) return "—"
    if (watts < 0.005) return "~0 W"
    if (watts < 1) return "~" + watts.toFixed(2) + " W"
    if (watts < 10) return "~" + watts.toFixed(1) + " W"
    return "~" + Math.round(watts) + " W"
  }

  function measuredPackagePowerText(value) {
    var watts = Number(value)
    if (!isFinite(watts) || watts < 0) return ""
    if (watts < 10) return watts.toFixed(2) + " W"
    if (watts < 100) return watts.toFixed(1) + " W"
    return Math.round(watts) + " W"
  }

  function sortLabel(key, label) {
    if (sortKey !== key) return label
    return label + (sortAscending ? " ↑" : " ↓")
  }

  function selectProcessFromPointer(index, item, mouse) {
    // Pointer events can arrive at the mouse polling rate. Once this row owns
    // the cursor, avoid coordinate mapping and QML property writes until the
    // pointer actually reaches a different row.
    if (cursorActive && selectedProcessIndex === index) return
    if (!pointerGate.moved(item, mouse)) return
    cursorActive = true
    selectProcess(index)
  }

  function processNameColumnWidth(availableWidth, spacing) {
    var fixedWidth = processPidColumnWidth + processMetricColumnWidth * 3
    var gaps = 4
    if (showProcessUserColumn) {
      fixedWidth += processUserColumnWidth
      gaps++
    }
    if (showProcessTimeColumn) {
      fixedWidth += processMetricColumnWidth
      gaps++
    }
    return Math.max(0, availableWidth - fixedWidth - spacing * gaps)
  }

  onSortedProcessesChanged: {
    pointerGate.reset()
    restoreProcessCursor()
  }

  onProcessPowerUnavailableChanged: {
    if (processPowerUnavailable && sortKey === "power") {
      sortKey = "cpu"
      sortAscending = false
    }
  }

  onOpenedChanged: {
    if (opened) {
      expanded = false
      cursorActive = false
      selectedProcessIndex = 0
      selectedProcessKey = ""
      processQuery = ""
    } else {
      expanded = false
      processQuery = ""
    }
  }

  ActivityController {
    id: activity
    settings: root.settings
    active: root.opened
    expanded: root.expanded
  }

  ProcessActionController {
    id: processActions
    active: root.opened
    enabled: root.expanded
    onConfirmationRequested: processConfirm.selectedIndex = 0
    onFocusRequested: if (root.opened) keyCatcher.forceActiveFocus()
    onRefreshRequested: activity.refreshProcessCycle()
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: root.processViewport
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf201"
    tooltipText: "Activity"
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Keep both layouts attached to the invoking widget. When the wider
    // layout reaches a screen edge, KeyboardPanel grows it inward instead of
    // moving the card to the center of the display.
    centerOnBar: false
    contentWidth: panel.fittedContentWidth(root.expanded ? Style.space(780) : Style.space(380))
    contentHeight: panel.fittedContentHeight(
      contentLoader.item ? contentLoader.item.implicitHeight : Style.space(320),
      root.expanded ? Style.space(720) : Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: !!(root.searchField && root.searchField.activeFocus)

      onMoveRequested: function(dx, dy) {
        if (processActions.confirmationOpen) {
          if (dx !== 0) processConfirm.selectedIndex = processConfirm.selectedIndex === 0 ? 1 : 0
          return
        }
        if (!root.expanded) return
        if (dy !== 0) root.moveProcess(dy)
        else if (dx !== 0) root.cycleSort(dx)
      }
      onActivateRequested: {
        if (processActions.confirmationOpen) {
          if (processConfirm.selectedIndex === 0) processActions.cancel()
          else processActions.confirm()
          return
        }
        if (!root.expanded) root.setExpanded(true)
      }
      onCloseRequested: {
        if (processActions.confirmationOpen) {
          processActions.cancel()
          return
        }
        if (root.expanded) root.setExpanded(false)
        else root.close()
      }
      onDeleteRequested: {
        if (!processActions.confirmationOpen && root.cursorActive)
          processActions.request(root.selectedProcess)
      }
      onTabRequested: function(direction) {
        if (processActions.confirmationOpen) {
          processConfirm.selectedIndex = processConfirm.selectedIndex === 0 ? 1 : 0
          return
        }
        root.switchPanel(direction)
      }
      onTextKey: function(text) {
        if (processActions.confirmationOpen) return
        var key = String(text || "").toLowerCase()
        if (key === "e") root.setExpanded(!root.expanded)
        else if (key === "r") root.refresh()
        else if (key === "/" && root.expanded) root.focusSearch()
        else if (key === "c" && root.expanded) root.setSort("cpu")
        else if (key === "m" && root.expanded) root.setSort("memory")
        else if (key === "w" && root.expanded) root.setSort("power")
        else if (key === "p" && root.expanded) root.setSort("pid")
        else if (key === "t" && root.expanded) root.setSort("runtime")
        else if (key === "n" && root.expanded) root.setSort("name")
      }

      Loader {
        id: contentLoader
        width: parent.width
        sourceComponent: root.expanded ? expandedContent : compactContent
      }

      ConfirmDialog {
        id: processConfirm
        anchors.fill: parent
        opened: processActions.confirmationOpen
        z: 20
        message: processActions.pendingAction
          ? "End " + processActions.pendingAction.name + "?\nPID " + processActions.pendingAction.pid
            + " · " + processActions.pendingAction.user
            + "\nCloses its verified parent app and windows."
            + "\nForce-closes it after 3 seconds if needed."
          : ""
        confirmText: "End app"
        background: Color.popups.background
        foreground: root.foreground
        selectedText: root.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        cornerRadius: Style.cornerRadius
        onCanceled: processActions.cancel()
        onConfirmed: processActions.confirm()
      }
    }
  }

  Component {
    id: activityIcon

    Text {
      text: "\uf201"
      color: root.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.display
    }
  }

  Component {
    id: compactContent

    Column {
      width: contentLoader.width
      spacing: Style.spacing.panelGap

      ActivityHeader {
        width: parent.width
        expanded: false
      }

      Row {
        width: parent.width
        spacing: Style.spacing.md

        MetricCard {
          width: (parent.width - parent.spacing) / 2
          label: "CPU"
          value: root.hasSnapshot ? root.percentText(root.metrics.cpu) : "—"
          detail: root.snapshot.cores.length ? root.snapshot.cores.length + " LOGICAL CPUS" : "CPU TOTAL"
          history: root.metrics.cpuHistory
          ceiling: 100
          tone: root.pressureColor(root.metrics.cpu)
        }

        MetricCard {
          width: (parent.width - parent.spacing) / 2
          label: "MEMORY"
          value: root.hasSnapshot ? root.percentText(root.metrics.memory) : "—"
          detail: root.snapshot.memory.total
            ? Model.formatBytes(root.snapshot.memory.total - root.snapshot.memory.available) + " USED"
            : "TOTAL"
          history: root.metrics.memoryHistory
          ceiling: 100
          tone: root.pressureColor(root.metrics.memory)
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.panelGap

        ActivityPair {
          width: (parent.width - parent.spacing) / 2
          iconText: "\uf019"
          label: "Network"
          value: Model.formatBytes(root.metrics.download, "/s")
          secondary: "\uf093  " + Model.formatBytes(root.metrics.upload, "/s")
        }

        ActivityPair {
          width: (parent.width - parent.spacing) / 2
          iconText: "\uf0a0"
          label: "Disk"
          value: Model.formatBytes(root.metrics.diskRead, "/s")
          secondary: "\uf093  " + Model.formatBytes(root.metrics.diskWrite, "/s")
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
      }

      Column {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          text: "BUSIEST PROCESSES"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Text {
          visible: root.topProcesses.length === 0
          text: root.processMetricsReady ? "No running processes" : "Sampling process activity…"
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.topProcesses

          ProcessRow {
            required property var modelData
            width: parent.width
            processData: modelData
            compact: true
          }
        }
      }

      Button {
        width: parent.width
        iconText: "\uf065"
        text: "More details"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        bordered: true
        onClicked: root.setExpanded(true)
      }
    }
  }

  Component {
    id: expandedContent

    Column {
      width: contentLoader.width
      spacing: Style.spacing.panelGap

      ActivityHeader {
        width: parent.width
        expanded: true
      }

      Grid {
        id: summaryGrid
        width: parent.width
        columns: width >= Style.space(640) ? 4 : 2
        spacing: Style.spacing.md

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: "CPU"
          value: root.hasSnapshot ? root.percentText(root.metrics.cpu) : "—"
          detail: root.processPower.available
            ? root.measuredPackagePowerText(root.processPower.watts) + " PACKAGE · "
              + (root.snapshot.cores.length ? root.snapshot.cores.length + " CPUS" : "CPU TOTAL")
            : (root.snapshot.cores.length ? root.snapshot.cores.length + " LOGICAL CPUS" : "CPU TOTAL")
          history: root.metrics.cpuHistory
          ceiling: 100
          tone: root.pressureColor(root.metrics.cpu)
        }

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: "MEMORY"
          value: root.hasSnapshot ? root.percentText(root.metrics.memory) : "—"
          detail: root.snapshot.memory.total ? Model.formatBytes(root.snapshot.memory.total) + " TOTAL" : "TOTAL"
          history: root.metrics.memoryHistory
          ceiling: 100
          tone: root.pressureColor(root.metrics.memory)
        }

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: "NETWORK"
          value: Model.formatBytes(root.metrics.download, "/s")
          detail: "\uf093  " + Model.formatBytes(root.metrics.upload, "/s")
          history: root.metrics.networkHistory
          tone: root.accent
        }

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: "DISK"
          value: Model.formatBytes(root.metrics.diskRead, "/s")
          detail: "\uf093  " + Model.formatBytes(root.metrics.diskWrite, "/s")
          history: root.metrics.diskHistory
          tone: root.accent
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.md

        DetailSurface {
          width: (parent.width - parent.spacing) / 2
          height: Style.space(164)

          Column {
            anchors.fill: parent
            anchors.margins: Style.spacing.xl
            spacing: Style.spacing.sm

            PanelSectionHeader {
              text: "CPU CORES"
              foreground: root.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.spacing.xl
              rowSpacing: Style.spacing.xs

              Repeater {
                model: root.metrics.cores.slice(0, 16)

                CoreLine {
                  required property var modelData
                  width: (parent.width - parent.columnSpacing) / 2
                  coreData: modelData
                }
              }
            }

            Text {
              visible: root.metrics.cores.length > 16
              text: "+" + (root.metrics.cores.length - 16) + " more logical cores"
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          height: Style.space(164)
          spacing: Style.spacing.md

          DetailSurface {
            width: parent.width
            height: (parent.height - parent.spacing) / 2

            Column {
              anchors.fill: parent
              anchors.margins: Style.spacing.lg
              spacing: Style.spacing.labelGap

              PanelSectionHeader {
                text: "SYSTEM"
                foreground: root.foreground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              }

              Grid {
                id: systemDetails
                width: parent.width
                columns: 2
                columnSpacing: Style.spacing.xl
                rowSpacing: Style.spacing.xxs

                Repeater {
                  model: [
                    {
                      label: "RAM",
                      value: root.snapshot.memory.total
                        ? Model.formatBytes(root.snapshot.memory.total - root.snapshot.memory.available)
                        : "—"
                    },
                    {
                      label: "SWAP",
                      value: root.snapshot.memory.swapTotal ? root.percentText(root.metrics.swap) : "NONE"
                    },
                    {
                      label: "CORES",
                      value: root.snapshot.cores.length ? root.snapshot.cores.length + " LOGICAL" : "—"
                    },
                    {
                      label: "TASKS",
                      value: root.snapshot.tasks.running + "/" + root.snapshot.tasks.total
                    }
                  ]

                  DetailLine {
                    required property var modelData
                    width: (systemDetails.width - systemDetails.columnSpacing) / 2
                    label: modelData.label
                    value: modelData.value
                  }
                }
              }
            }
          }

          DetailSurface {
            width: parent.width
            height: (parent.height - parent.spacing) / 2

            Column {
              anchors.fill: parent
              anchors.margins: Style.spacing.lg
              spacing: Style.spacing.labelGap

              PanelSectionHeader {
                text: "DISK STORAGE"
                foreground: root.foreground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              }

              Row {
                width: parent.width
                spacing: Style.spacing.xl

                Column {
                  width: (parent.width - parent.spacing) / 2
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    text: "USED"
                    color: root.dim
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    text: root.storageSnapshot.sample > 0
                      ? Model.formatBytes(root.storageSnapshot.used)
                      : "—"
                    color: root.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }
                }

                Column {
                  width: (parent.width - parent.spacing) / 2
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    text: "REMAINING"
                    color: root.dim
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                  }

                  Text {
                    width: parent.width
                    text: root.storageSnapshot.sample > 0
                      ? Model.formatBytes(root.storageSnapshot.available)
                      : "—"
                    color: root.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideLeft
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                color: Util.alpha(root.foreground, 0.12)

                Rectangle {
                  width: parent.width * root.storageUsedFraction
                  height: parent.height
                  radius: parent.radius
                  color: root.accent
                }
              }
            }
          }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          text: "PROCESSES"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          width: Math.max(0, parent.width - parent.children[0].implicitWidth - searchBox.width
            - cpuSort.implicitWidth - memorySort.implicitWidth - powerSort.implicitWidth
            - pidSort.implicitWidth - parent.spacing * 6)
          height: 1
        }

        TextField {
          id: searchBox
          width: Math.max(Style.space(120), Math.min(Style.space(180), parent.width * 0.24))
          placeholderText: "\uf002 Search"
          foreground: root.foreground
          accent: root.accent
          font.pixelSize: Style.font.bodySmall
          verticalPadding: Style.spacing.sm
          onTextChanged: {
            root.processQuery = text
            root.selectedProcessIndex = 0
            root.selectedProcessKey = ""
            root.cursorActive = false
            pointerGate.reset()
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.finishSearch()
              event.accepted = true
            }
          }
          Component.onCompleted: {
            text = root.processQuery
            root.searchField = searchBox
          }
          Component.onDestruction: if (root.searchField === searchBox) root.searchField = null
        }

        Button {
          id: cpuSort
          text: root.sortLabel("cpu", "CPU")
          selected: root.sortKey === "cpu"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.sm
          onClicked: root.setSort("cpu")
        }

        Button {
          id: memorySort
          text: root.sortLabel("memory", "RAM")
          selected: root.sortKey === "memory"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.sm
          onClicked: root.setSort("memory")
        }

        Button {
          id: powerSort
          text: root.sortLabel("power", "EST. W")
          selected: root.sortKey === "power"
          tooltipText: root.processPowerTooltip
          foreground: root.processPower.available ? root.foreground : root.dim
          accent: root.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.sm
          onClicked: root.setSort("power")
        }

        Button {
          id: pidSort
          text: root.sortLabel("pid", "PID")
          selected: root.sortKey === "pid"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.sm
          onClicked: root.setSort("pid")
        }
      }

      ProcessHeader {
        width: parent.width
      }

      Item {
        width: parent.width
        height: Style.space(190)
        clip: true

        ListView {
          id: processList
          anchors.fill: parent
          model: root.sortedProcesses
          spacing: Style.spacing.xxs
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          reuseItems: true

          function ensureSelected() {
            if (root.selectedProcessIndex >= 0 && root.selectedProcessIndex < count)
              positionViewAtIndex(root.selectedProcessIndex, ListView.Contain)
          }

          Component.onCompleted: root.processViewport = processList
          Component.onDestruction: if (root.processViewport === processList) root.processViewport = null

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }

          delegate: ProcessRow {
            required property var modelData
            required property int index
            width: ListView.view.width
            processData: modelData
            rowIndex: index
            compact: false
            selected: root.cursorActive
              && root.selectedProcessKey === Model.processIdentityKey(modelData)
          }
        }

        Text {
          anchors.centerIn: parent
          visible: processList.count === 0
          text: root.processQuery
            ? "No processes match “" + root.processQuery + "”"
            : (root.processMetricsReady ? "No running processes" : "Sampling process activity…")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Row {
        x: Style.spacing.md
        width: Math.max(0, parent.width - Style.spacing.md * 2)
        spacing: Style.spacing.md

        DetailLine {
          width: Math.max(0, parent.width - (endProcessButton.visible
            ? endProcessButton.implicitWidth + parent.spacing : 0))
          anchors.verticalCenter: parent.verticalCenter
          label: root.selectedProcess ? root.selectedProcess.name + "  ·  PID " + root.selectedProcess.pid : "No process selected"
          value: root.selectedProcess
            ? root.selectedProcess.user + "  ·  " + root.selectedProcess.state + "  ·  "
              + Model.formatBytes(root.selectedProcess.rss) + "  ·  " + Model.formatDuration(root.selectedProcess.elapsed)
            : ""
        }

        Button {
          id: endProcessButton
          readonly property string blockReason: processActions.blockReason(root.selectedProcess)
          readonly property bool targetAllowed: blockReason === ""

          visible: root.selectedProcess !== null
          enabled: !processActions.running && targetAllowed
          opacity: targetAllowed || processActions.running ? 1 : 0.48
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf2ed"
          text: processActions.running
            ? "Ending…"
            : (targetAllowed ? "End app" : "Unavailable")
          tooltipText: targetAllowed
            ? "Close the selected app; force-close after 3 seconds if needed"
            : blockReason
          foreground: targetAllowed ? root.urgent : root.dim
          accent: targetAllowed ? root.urgent : root.dim
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.xs
          bordered: true
          onClicked: processActions.request(root.selectedProcess)
        }
      }

      Text {
        width: parent.width
        text: processActions.status || "e collapse  ·  / search  ·  c/m/w/p/t/n sort  ·  r refresh  ·  j/k select  ·  x end app"
        textFormat: Text.PlainText
        color: processActions.failed ? root.urgent : root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }

  component ActivityHeader: Row {
    property bool expanded: false

    spacing: Style.spacing.md

    PanelHero {
      id: hero
      width: Math.max(1, parent.width - headerActions.implicitWidth - parent.spacing)
      anchors.verticalCenter: parent.verticalCenter
      iconComponent: activityIcon
      title: "Activity"
      meta: root.hasSnapshot ? "UP " + Model.formatDuration(root.snapshot.uptime) : "READING SYSTEM"
      foreground: root.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    }

    Row {
      id: headerActions
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.sm

      TemperatureBadge {
        visible: root.cpuTemperature !== null
        text: visible ? Math.round(root.cpuTemperature.value) + "°C" : ""
        implicitHeight: expandButton.implicitHeight
      }

      PanelActionButton {
        id: expandButton
        iconText: expanded ? "\uf066" : "\uf065"
        tooltipText: expanded ? "Collapse details" : "Expand details"
        foreground: root.foreground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        bordered: true
        onClicked: root.setExpanded(!expanded)
      }
    }
  }

  component TemperatureBadge: BorderSurface {
    property string text: ""

    implicitWidth: temperatureText.implicitWidth + Style.space(10)
    implicitHeight: temperatureText.implicitHeight + Style.space(4)
    color: "transparent"
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    radius: Style.cornerRadius

    Text {
      id: temperatureText
      anchors.centerIn: parent
      text: parent.text
      color: root.dim
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  component MetricCard: BorderSurface {
    property string label: ""
    property string value: ""
    property string detail: ""
    property var history: []
    property real ceiling: 0
    property color tone: root.accent

    implicitHeight: Style.space(92)
    color: Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    radius: Style.cornerRadius

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.lg
      spacing: Style.spacing.xxs

      PanelSectionHeader {
        text: label
        foreground: root.foreground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      }

      Text {
        width: parent.width
        text: value
        color: tone
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        text: detail
        width: parent.width
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Sparkline {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.spacing.lg
      anchors.rightMargin: Style.spacing.lg
      anchors.bottomMargin: Style.spacing.sm
      height: Style.space(20)
      values: history
      ceiling: parent.ceiling
      lineColor: tone
      fillColor: Util.alpha(tone, 0.10)
    }
  }

  component ActivityPair: Row {
    property string iconText: ""
    property string label: ""
    property string value: ""
    property string secondary: ""

    spacing: Style.spacing.md

    Text {
      id: icon
      anchors.verticalCenter: parent.verticalCenter
      text: iconText
      color: root.accent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.title
    }

    Column {
      id: labels
      width: Math.max(1, parent.width - icon.implicitWidth - parent.spacing)
      spacing: Style.spacing.xxs

      Text {
        text: label.toUpperCase()
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        width: parent.width
        text: value
        color: root.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: secondary
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  component DetailSurface: BorderSurface {
    color: Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    radius: Style.cornerRadius
  }

  component DetailLine: Item {
    id: detailLine

    property string label: ""
    property string value: ""

    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.38
      text: label
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      id: valueText
      anchors.left: labelText.right
      anchors.leftMargin: Style.spacing.md
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: value
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideLeft
      horizontalAlignment: Text.AlignRight
    }
  }

  component CoreLine: Row {
    property var coreData: ({ name: "", usage: 0 })

    spacing: Style.spacing.sm

    Text {
      id: coreIndex
      width: Style.space(24)
      text: String(coreData.name || "").replace("cpu", "")
      color: root.dim
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
    }

    Rectangle {
      width: Math.max(1, parent.width - coreIndex.width - usageText.width - parent.spacing * 2)
      height: Style.space(5)
      radius: height / 2
      color: Util.alpha(root.foreground, 0.12)
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, Number(coreData.usage || 0) / 100))
        height: parent.height
        radius: parent.radius
        color: root.pressureColor(coreData.usage)

        Behavior on width {
          NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: usageText
      width: Style.space(34)
      text: Math.round(Number(coreData.usage || 0)) + "%"
      color: root.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
    }
  }

  component ProcessHeader: Item {
    implicitHeight: headerRow.implicitHeight

    Row {
      id: headerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.md

      ProcessCell {
        width: root.processNameColumnWidth(parent.width, parent.spacing)
        text: "NAME"
        dimmed: true
      }
      ProcessCell {
        width: root.processPidColumnWidth
        text: "PID"
        dimmed: true
        alignment: Text.AlignRight
      }
      ProcessCell {
        visible: root.showProcessUserColumn
        width: root.processUserColumnWidth
        text: "USER"
        dimmed: true
      }
      ProcessCell {
        width: root.processMetricColumnWidth
        text: "CPU"
        dimmed: true
        alignment: Text.AlignRight
      }
      ProcessCell {
        width: root.processMetricColumnWidth
        text: "RAM"
        dimmed: true
        alignment: Text.AlignRight
      }
      ProcessCell {
        width: root.processMetricColumnWidth
        text: "EST. W"
        dimmed: true
        alignment: Text.AlignRight
      }
      ProcessCell {
        visible: root.showProcessTimeColumn
        width: root.processMetricColumnWidth
        text: "TIME"
        dimmed: true
        alignment: Text.AlignRight
      }
    }
  }

  component ProcessRow: CursorSurface {
    property var processData: ({})
    property int rowIndex: -1
    property bool compact: false
    property bool selected: false

    hasCursor: selected
    foreground: root.foreground
    accent: root.accent
    implicitHeight: compact ? Style.space(34) : Style.space(28)

    Row {
      anchors.fill: parent
      anchors.leftMargin: compact ? Style.spacing.sm : Style.spacing.md
      anchors.rightMargin: compact ? Style.spacing.sm : Style.spacing.md
      spacing: Style.spacing.md

      Column {
        width: compact
          ? Math.max(1, parent.width - cpuValue.width - memoryValue.width - parent.spacing * 2)
          : root.processNameColumnWidth(parent.width, parent.spacing)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          width: parent.width
          text: String(processData.name || "unknown")
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: compact ? Style.font.body : Style.font.bodySmall
          font.bold: compact
          elide: Text.ElideRight
        }

        Text {
          visible: compact
          width: parent.width
          text: String(processData.user || "") + "  ·  " + String(processData.pid || "")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ProcessCell {
        visible: !compact
        width: root.processPidColumnWidth
        text: String(processData.pid || "")
        alignment: Text.AlignRight
      }

      ProcessCell {
        visible: !compact && root.showProcessUserColumn
        width: root.processUserColumnWidth
        text: String(processData.user || "")
      }

      ProcessCell {
        id: cpuValue
        width: compact ? Style.space(46) : root.processMetricColumnWidth
        text: Number(processData.cpu || 0).toFixed(1) + "%"
        alignment: Text.AlignRight
        emphasized: Number(processData.cpu || 0) >= 25
      }

      ProcessCell {
        id: memoryValue
        width: compact ? Style.space(46) : root.processMetricColumnWidth
        text: Number(processData.memory || 0).toFixed(1) + "%"
        alignment: Text.AlignRight
      }

      ProcessCell {
        visible: !compact
        width: root.processMetricColumnWidth
        text: root.estimatedPowerText(processData.power)
        alignment: Text.AlignRight
      }

      ProcessCell {
        visible: !compact && root.showProcessTimeColumn
        width: root.processMetricColumnWidth
        text: Model.formatDuration(processData.elapsed)
        alignment: Text.AlignRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: !compact
      cursorShape: compact ? Qt.ArrowCursor : Qt.PointingHandCursor
      onPositionChanged: function(mouse) {
        if (!compact) root.selectProcessFromPointer(parent.rowIndex, parent, mouse)
      }
      onClicked: {
        if (!compact) {
          root.cursorActive = true
          root.selectProcess(parent.rowIndex)
        }
      }
    }
  }

  component ProcessCell: Text {
    property bool dimmed: false
    property bool emphasized: false
    property int alignment: Text.AlignLeft

    color: emphasized ? root.accent : (dimmed ? root.dim : root.foreground)
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: dimmed ? Style.font.caption : Style.font.bodySmall
    font.bold: emphasized || dimmed
    textFormat: Text.PlainText
    elide: Text.ElideRight
    horizontalAlignment: alignment
    verticalAlignment: Text.AlignVCenter
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  }
}
