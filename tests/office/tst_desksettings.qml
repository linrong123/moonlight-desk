import QtQuick 2.9
import QtTest 1.2
import "../../app/office"
import "../../app/office/desklogic.js" as Logic

TestCase {
    name: "DeskSettings"
    visible: true
    width: 900; height: 2200
    when: windowShown

    // Stand-in for StreamingPreferences: same property names, no storage.
    QtObject {
        id: fakePrefs
        property int width: 1920
        property int height: 1080
        property int fps: 60
        property int bitrateKbps: 20000
        property bool unlockBitrate: false
        property bool autoAdjustBitrate: true
        property bool playAudioOnHost: false
        property bool muteOnFocusLoss: false
        property int videoCodecConfig: 0
        property bool enableYUV444: false
        property int windowMode: 1
        property int recommendedFullScreenMode: 1
        property bool swapMouseButtons: false
        property bool reverseScrollDirection: false
        property int scrollSpeed: 67
        property int captureSysKeysMode: 0
        property int saves: 0
        function getDefaultBitrate(w, h, f, yuv444) {
            return Math.round(w * h * f / 6220.8) * (yuv444 ? 2 : 1)
        }
        function save() { saves++ }
    }

    DeskSettings {
        id: settings
        anchors.fill: parent
        prefs: fakePrefs
        nativeWidth: 2560
        nativeHeight: 1600
        versionString: "6.1.0"
    }
    SignalSpy { id: advancedSpy; target: settings; signalName: "advancedRequested" }
    SignalSpy { id: backSpy; target: settings; signalName: "backRequested" }

    function init() {
        fakePrefs.width = 1920; fakePrefs.height = 1080; fakePrefs.fps = 60
        fakePrefs.bitrateKbps = 20000; fakePrefs.unlockBitrate = false; fakePrefs.autoAdjustBitrate = true
        fakePrefs.playAudioOnHost = false; fakePrefs.muteOnFocusLoss = false
        fakePrefs.videoCodecConfig = 0; fakePrefs.enableYUV444 = false
        fakePrefs.windowMode = 1; fakePrefs.recommendedFullScreenMode = 1
        fakePrefs.swapMouseButtons = false; fakePrefs.reverseScrollDirection = false
        fakePrefs.scrollSpeed = 67
        fakePrefs.captureSysKeysMode = 0
        fakePrefs.saves = 0
        advancedSpy.clear(); backSpy.clear()
    }

    function control(name) {
        var item = findChild(settings, name)
        verify(item !== null, name)
        return item
    }
    function toggle(name) {
        var item = control(name)
        item.toggle()
        item.toggled()
    }

    function test_prefsToControls() {
        compare(control("resolutionBox").currentIndex, 2) // native first, then 1280x720
        compare(control("fpsBox").currentText, "60 帧/秒")
        verify(control("autoBitrateSwitch").checked)
        verify(!control("bitrateRow").visible)
        verify(control("fullscreenRadio").checked)
        compare(control("versionText").text, "6.1.0")

        fakePrefs.width = 2560; fakePrefs.height = 1600
        compare(control("resolutionBox").currentIndex, 0)
        fakePrefs.width = 1000; fakePrefs.height = 700
        compare(control("resolutionBox").currentText, "当前：1000 × 700")
        fakePrefs.fps = 120
        compare(control("fpsBox").currentText, "120 帧/秒")
        fakePrefs.videoCodecConfig = Logic.VCC_FORCE_HEVC_HDR_DEPRECATED
        compare(control("codecBox").currentIndex, Logic.codecIndex(Logic.VCC_FORCE_HEVC))
        fakePrefs.windowMode = Logic.WM_WINDOWED
        verify(control("windowedRadio").checked)
        verify(!control("fullscreenRadio").checked)
        fakePrefs.playAudioOnHost = true
        verify(control("audioHostRadio").checked)
        fakePrefs.swapMouseButtons = true
        verify(control("swapButtonsSwitch").checked)
        fakePrefs.captureSysKeysMode = Logic.CSK_ALWAYS
        verify(control("sysKeysSwitch").checked)
        verify(control("sysKeysModeBox").visible)
        compare(control("sysKeysModeBox").currentIndex, 1)
        fakePrefs.autoAdjustBitrate = false
        verify(control("bitrateRow").visible)
        compare(control("bitrateLabel").text, "20 Mbps")
        compare(fakePrefs.saves, 0) // reading never writes
    }

    function test_resolutionAndFpsFollowAutoBitrate() {
        var box = control("resolutionBox")
        box.activated(1) // 1280 x 720
        compare(fakePrefs.width, 1280)
        compare(fakePrefs.height, 720)
        compare(fakePrefs.bitrateKbps, fakePrefs.getDefaultBitrate(1280, 720, 60, false))
        compare(fakePrefs.saves, 1)
        box.activated(1) // unchanged: no write
        compare(fakePrefs.saves, 1)
        control("fpsBox").activated(3) // 120
        compare(fakePrefs.fps, 120)
        compare(fakePrefs.bitrateKbps, fakePrefs.getDefaultBitrate(1280, 720, 120, false))
        toggle("sharpTextSwitch")
        verify(fakePrefs.enableYUV444)
        compare(fakePrefs.bitrateKbps, fakePrefs.getDefaultBitrate(1280, 720, 120, true))
        compare(fakePrefs.saves, 3)
    }

    function test_manualBitrate() {
        toggle("autoBitrateSwitch")
        verify(!fakePrefs.autoAdjustBitrate)
        compare(fakePrefs.saves, 1)
        settings.setBitrate(12345)
        compare(fakePrefs.bitrateKbps, 12500)
        settings.setBitrate(999999)
        compare(fakePrefs.bitrateKbps, 150000)
        fakePrefs.unlockBitrate = true
        settings.setBitrate(999999)
        compare(fakePrefs.bitrateKbps, 500000)
        settings.setBitrate(10)
        compare(fakePrefs.bitrateKbps, 500)
        // A manual value is not overwritten by resolution changes.
        control("resolutionBox").activated(1)
        compare(fakePrefs.bitrateKbps, 500)
        toggle("autoBitrateSwitch")
        verify(fakePrefs.autoAdjustBitrate)
        compare(fakePrefs.bitrateKbps, fakePrefs.getDefaultBitrate(1280, 720, 60, false))
    }

    function test_controlsWritePrefs() {
        control("codecBox").activated(1)
        compare(fakePrefs.videoCodecConfig, Logic.VCC_FORCE_H264)
        fakePrefs.recommendedFullScreenMode = Logic.WM_FULLSCREEN
        settings.setWindowed(true)
        compare(fakePrefs.windowMode, Logic.WM_WINDOWED)
        settings.setWindowed(false)
        compare(fakePrefs.windowMode, Logic.WM_FULLSCREEN)
        settings.setPlayOnHost(true)
        verify(fakePrefs.playAudioOnHost)
        toggle("muteOnFocusLossSwitch")
        verify(fakePrefs.muteOnFocusLoss)
        toggle("sysKeysSwitch")
        compare(fakePrefs.captureSysKeysMode, Logic.CSK_FULLSCREEN)
        control("sysKeysModeBox").activated(1)
        compare(fakePrefs.captureSysKeysMode, Logic.CSK_ALWAYS)
        toggle("sysKeysSwitch")
        compare(fakePrefs.captureSysKeysMode, Logic.CSK_OFF)
        toggle("swapButtonsSwitch")
        verify(fakePrefs.swapMouseButtons)
        toggle("reverseScrollSwitch")
        verify(fakePrefs.reverseScrollDirection)
        compare(fakePrefs.saves, 10)
    }

    function test_scrollSpeed() {
        var box = control("scrollSpeedBox")
        compare(box.currentIndex, 1)
        box.activated(0) // slow
        compare(fakePrefs.scrollSpeed, 33)
        compare(fakePrefs.saves, 1)
        box.activated(2) // standard
        compare(fakePrefs.scrollSpeed, 100)
        compare(fakePrefs.saves, 2)
        box.activated(1) // medium
        compare(fakePrefs.scrollSpeed, 67)
    }

    function test_advancedAndBack() {
        mouseClick(control("advancedButton"))
        compare(advancedSpy.count, 1)
        mouseClick(control("backButton"))
        compare(backSpy.count, 1)
    }

    function test_versionFallback() {
        settings.versionString = ""
        compare(control("versionText").text, "—")
        settings.versionString = "6.1.0"
    }
}
