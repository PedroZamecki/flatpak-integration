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
}
