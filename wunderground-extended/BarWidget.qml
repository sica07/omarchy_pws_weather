import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "wunderground.extended"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelItem
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function refresh() { if (panelItem) panelItem.refresh(true) }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(function() {
        root.injectPanel()
        if (root.panelItem && !root.panelItem.initialized) root.panelItem.refresh(true)
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.panelItem ? root.panelItem.barLabel : "󰖐 —"
    tooltipText: root.panelItem ? root.panelItem.barTooltip : "Wunderground Extended"
    dimmed: root.panelItem ? root.panelItem.loading : false

    onPressed: function(code) {
      if (code === Qt.LeftButton) root.toggle()
      else if (code === Qt.MiddleButton) root.refresh()
      else if (code === Qt.RightButton && root.panelItem) root.panelItem.openStationDashboard()
    }
  }
}
