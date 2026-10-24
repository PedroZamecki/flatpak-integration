import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "flatpak-integration"

  property bool updateAvailable: false
  property int updateCount: 0

  function refresh() {
    if (!updateProc.running) updateProc.running = true
  }

  function clear() {
    if (updateProc.running) updateProc.running = false
    updateAvailable = false
    updateCount = 0
  }

  function runUpdate() {
    if (root.bar) {
      root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-flatpak-update")
    }
  }

  visible: updateAvailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "flatpak-integration-update"

    function refresh(): void {
      root.broadcast("refresh")
    }

    function clear(): void {
      root.broadcast("clear")
    }
  }

  Process {
    id: updateProc
    command: ["omarchy-flatpak-update-available"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var count = parseInt(text.trim()) || 0
        root.updateCount = count
      }
    }
    onExited: function(exitCode) {
      root.updateAvailable = (exitCode === 0)
      if (exitCode !== 0) root.updateCount = 0
    }
  }

  // Grace period on boot/startup (15 seconds) to allow network connection to establish
  Timer {
    id: startupTimer
    interval: 15000
    running: true
    repeat: false
    onTriggered: root.refresh()
  }

  // Periodic refresh every 4 hours (14400000 ms)
  Timer {
    interval: 14400000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏓"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.updateCount > 0 ? ("Pending Flatpak Updates (" + root.updateCount + ")") : "Pending Flatpak Updates"
    onPressed: root.runUpdate()
  }
}
