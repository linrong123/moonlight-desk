import QtQuick 2.9
import QtTest 1.2
import "../../app/office"

TestCase {
    id: testCase
    name: "DeskHome"
    visible: true
    width: 1100; height: 720
    when: windowShown
    ListModel {
        id: hosts
        ListElement { name: "设计工作站"; online: true; paired: true; statusUnknown: false; serverSupported: true; wakeable: true }
        ListElement { name: "办公室电脑"; online: false; paired: true; statusUnknown: false; serverSupported: true; wakeable: true }
        ListElement { name: "新电脑"; online: true; paired: false; statusUnknown: false; serverSupported: true; wakeable: true }
    }
    DeskHome { id: home; anchors.fill: parent; devices: hosts; selectedIndex: 0; selectedDevice: hosts.get(0) }
    SignalSpy { id: selectSpy; target: home; signalName: "selectDevice" }
    SignalSpy { id: enterSpy; target: home; signalName: "enterDesktop" }
    function init() {
        home.selectedIndex = 0
        home.selectedDevice = hosts.get(0)
        home.sessionActive = false
        home.sessionStatus = ""
        findChild(home, "deviceSearch").text = ""
        enterSpy.clear(); selectSpy.clear()
        wait(30)
    }
    function test_states() {
        compare(home.stateText(hosts.get(0)), "在线")
        compare(home.stateText(hosts.get(1)), "离线")
        compare(home.stateText(hosts.get(2)), "待配对")
        compare(home.stateText({name: "测试", statusUnknown: true}), "正在检测")
    }
    function test_selectionDoesNotLaunch() {
        mouseClick(findChild(home, "deviceList"), 80, 100)
        compare(selectSpy.count, 1)
        compare(selectSpy.signalArguments[0][0], 1)
        compare(enterSpy.count, 0)
    }
    function test_launchAndOffline() {
        var button = findChild(home, "enterDesktopButton")
        verify(button.enabled)
        mouseClick(button)
        compare(enterSpy.count, 1)
        home.selectedDevice = hosts.get(1)
        verify(!button.enabled)
    }
    function test_activeCanFocusWhenOffline() {
        home.selectedDevice = hosts.get(1)
        home.sessionActive = true
        home.sessionStatus = "正在连接"
        var button = findChild(home, "enterDesktopButton")
        verify(button.enabled)
        compare(button.text, "显示桌面窗口")
    }
    function test_emptyAndSearch() {
        home.selectedDevice = ({})
        verify(!findChild(home, "enterDesktopButton").visible)
        findChild(home, "deviceSearch").text = "办公室"
        compare(home.searchText, "办公室")
        wait(50)
    }
}
