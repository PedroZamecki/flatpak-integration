import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : (home + "/.config/omarchy/plugins/flatpak-integration")

  Component.onCompleted: {
    installerProcess.command = ["bash", pluginDir + "/install.sh", "--quiet"]
    installerProcess.running = true
  }

  Process {
    id: installerProcess
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("flatpak-integration install: " + text.trim())
    }
  }

  // Flatpak exports its desktop entries outside the directories this shell
  // scans, so apps installed with `flatpak install` only show up once the
  // plugin has linked them. Poll the export tree (a cheap hash comparison) so
  // manually installed apps appear in the Omarchy Apps menu on their own.
  Timer {
    interval: 30000
    repeat: true
    running: true

    onTriggered: {
      if (!desktopSyncProcess.running)
        desktopSyncProcess.running = true
    }
  }

  Process {
    id: desktopSyncProcess
    running: false
    command: ["bash", root.pluginDir + "/bin/omarchy-flatpak-setup", "desktop", "--if-needed", "--quiet"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("flatpak-integration desktop sync: " + text.trim())
    }
  }
}
