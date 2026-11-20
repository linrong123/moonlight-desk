import QtQuick 2.9
import QtTest 1.2
import "../../app/office"

TestCase {
    id: testCase
    name: "DeskHome"
    visible: true
    width: 1100; height: 1000
    when: windowShown

    property var sampleDevices: [
        { uuid: "a", name: "设计工作站", address: "10.0.0.5:47989", addresses: ["10.0.0.5:47989"],
          online: true, paired: true, statusUnknown: false, serverSupported: true, wakeable: true },
        { uuid: "b", name: "办公室电脑", address: "10.0.0.6:47989", addresses: ["10.0.0.6:47989"],
          online: false, paired: true, statusUnknown: false, serverSupported: true, wakeable: true },
        { uuid: "c", name: "新电脑", address: "10.0.0.7:47989", addresses: ["10.0.0.7:47989"],
          online: true, paired: false, statusUnknown: false, serverSupported: true, wakeable: false },
        { uuid: "d", name: "旧电脑", address: "10.0.0.8:47989", addresses: ["10.0.0.8:47989"],
          online: false, paired: true, statusUnknown: false, serverSupported: true, wakeable: false }
    ]

    DeskHome { id: home; anchors.fill: parent }
    SignalSpy { id: connectSpy; target: home; signalName: "connectRequested" }
    SignalSpy { id: openSpy; target: home; signalName: "openDevice" }
    SignalSpy { id: pairSpy; target: home; signalName: "pairDevice" }
    SignalSpy { id: wakeSpy; target: home; signalName: "wakeDevice" }
    SignalSpy { id: removeSpy; target: home; signalName: "removeDevice" }
    SignalSpy { id: disconnectSpy; target: home; signalName: "disconnectDevice" }
    SignalSpy { id: settingsSpy; target: home; signalName: "settings" }
    SignalSpy { id: quitSpy; target: home; signalName: "quitRequested" }

    function init() {
        home.devices = sampleDevices
        home.sessionStates = {}
        home.connecting = false
        home.connectStatus = ""
        home.addressText = ""
        var menu = findChild(home, "deviceMenu")
        if (menu) menu.close()
        connectSpy.clear(); openSpy.clear(); pairSpy.clear(); wakeSpy.clear()
        removeSpy.clear(); disconnectSpy.clear(); settingsSpy.clear(); quitSpy.clear()
        wait(30)
    }

    function cards() {
        var list = findChild(home, "deviceList")
        var result = []
        for (var i = 0; i < list.children.length; ++i)
            if (list.children[i].objectName === "deviceCard") result.push(list.children[i])
        return result
    }
    function card(uuid) {
        var all = cards()
        for (var i = 0; i < all.length; ++i) if (all[i].uuid === uuid) return all[i]
        return null
    }
    function actions(uuid) {
        return home.menuActions(uuid).map(function(item) { return item.action }).join(",")
    }

    function test_emptyState() {
        home.devices = []
        wait(30)
        verify(findChild(home, "emptyState").visible)
        compare(cards().length, 0)
        verify(findChild(home, "emptyHint").text.indexOf("IP") >= 0)
        home.devices = sampleDevices
        wait(30)
        verify(!findChild(home, "emptyState").visible)
        compare(cards().length, 4)
    }

    function test_cardContent() {
        var c = card("a")
        compare(findChild(c, "deviceName").text, "设计工作站")
        compare(findChild(c, "deviceAddress").text, "10.0.0.5")
        compare(findChild(c, "deviceState").text, "在线")
        compare(findChild(card("c"), "deviceState").text, "未配对")
        home.sessionStates = { "a": "远程桌面已打开" }
        wait(10)
        compare(findChild(card("a"), "deviceState").text, "远程桌面已打开")
        compare(findChild(card("a"), "cardPrimary").text, "显示桌面")
    }

    function test_connectSubmit() {
        var input = findChild(home, "addressInput")
        compare(input.placeholderText, "输入被控端 IP 或域名")
        home.addressText = "  10.0.0.9 "
        mouseClick(findChild(home, "connectButton"))
        compare(connectSpy.count, 1)
        compare(connectSpy.signalArguments[0][0], "10.0.0.9")

        input.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(connectSpy.count, 2)

        home.connecting = true
        home.connectStatus = "正在查找这台电脑…"
        wait(10)
        verify(!findChild(home, "connectButton").enabled)
        home.submitAddress()
        compare(connectSpy.count, 2)
        compare(findChild(home, "connectStatus").text, "正在查找这台电脑…")
    }

    function test_menuRules() {
        compare(actions("a"), "rename,remove")
        compare(actions("b"), "wake,rename,remove")
        compare(actions("c"), "pair,rename,remove")
        compare(actions("d"), "rename,remove")
        home.sessionStates = { "a": "远程桌面已打开" }
        compare(actions("a"), "disconnect,rename")
        compare(actions("missing"), "")
    }

    function test_menuShowsAllowedItems() {
        home.sessionStates = { "a": "远程桌面已打开" }
        wait(10)
        mouseClick(findChild(card("a"), "cardMenuButton"))
        var menu = findChild(home, "deviceMenu")
        tryCompare(menu, "visible", true)
        var visibleTexts = []
        for (var i = 0; i < menu.count; ++i)
            if (menu.itemAt(i).visible) visibleTexts.push(menu.itemAt(i).text)
        compare(visibleTexts.join(","), "断开,重命名")
        menu.close()
    }

    function test_triggerGuards() {
        home.sessionStates = { "a": "远程桌面已打开" }
        verify(!home.trigger("a", "remove"))
        compare(removeSpy.count, 0)
        verify(home.trigger("a", "disconnect"))
        compare(disconnectSpy.count, 1)
        verify(!home.trigger("d", "wake"))
        verify(!home.trigger("a", "pair"))
        verify(home.trigger("b", "remove"))
        compare(removeSpy.count, 1)
        verify(!home.trigger("missing", "rename"))
    }

    function test_cardPrimary() {
        mouseClick(findChild(card("a"), "cardPrimary"))
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "a")
        mouseClick(findChild(card("b"), "cardPrimary"))
        compare(wakeSpy.count, 1)
        mouseClick(findChild(card("c"), "cardPrimary"))
        compare(pairSpy.count, 1)
        var offline = findChild(card("d"), "cardPrimary")
        verify(!offline.enabled)
        compare(offline.text, "离线")
        mouseDoubleClickSequence(card("a"), 30, 30)
        compare(openSpy.count, 2)
    }

    function test_approvalWaitingCanBeCancelled() {
        home.sessionStates = { "a": "正在等待被控端确认…" }
        wait(10)
        compare(findChild(card("a"), "deviceState").text, "正在等待被控端确认…")
        mouseClick(findChild(card("a"), "cardMenuButton"))
        var menu = findChild(home, "deviceMenu")
        tryCompare(menu, "visible", true)
        menu.itemAt(0).triggered()
        compare(disconnectSpy.count, 1)
        compare(openSpy.count, 0)
        menu.close()
    }

    function test_activeSessionCanFocusWhenOffline() {
        home.sessionStates = { "d": "正在连接" }
        wait(10)
        var button = findChild(card("d"), "cardPrimary")
        verify(button.enabled)
        mouseClick(button)
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "d")
    }

    function test_topBar() {
        mouseClick(findChild(home, "settingsButton"))
        compare(settingsSpy.count, 1)
        mouseClick(findChild(home, "quitButton"))
        compare(quitSpy.count, 1)
    }
}
