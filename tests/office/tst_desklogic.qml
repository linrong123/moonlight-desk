import QtQuick 2.9
import QtTest 1.2
import "../../app/office/desklogic.js" as Logic

TestCase {
    name: "DeskLogic"

    function test_normalizeAddress() {
        compare(Logic.normalizeAddress("192.168.1.20"), "192.168.1.20:47989")
        compare(Logic.normalizeAddress("  Office-PC.Local "), "office-pc.local:47989")
        compare(Logic.normalizeAddress("10.0.0.5:48000"), "10.0.0.5:48000")
        compare(Logic.normalizeAddress("http://10.0.0.5/"), "10.0.0.5:47989")
        compare(Logic.normalizeAddress("fe80::1"), "[fe80::1]:47989")
        compare(Logic.normalizeAddress("[fe80::1]:48000"), "[fe80::1]:48000")
        compare(Logic.normalizeAddress(""), "")
        compare(Logic.normalizeAddress("a b"), "")
        compare(Logic.normalizeAddress("host:0"), "")
        compare(Logic.normalizeAddress("host:70000"), "")
        compare(Logic.normalizeAddress("bad..name"), "")
    }

    function test_findDeviceByAddress() {
        var devices = [
            { uuid: "a", address: "10.0.0.5:47989", addresses: ["10.0.0.5:47989", "pc.lan:47989"] },
            { uuid: "b", address: "10.0.0.6:48000", addresses: [] }
        ]
        compare(Logic.findDeviceByAddress(devices, "10.0.0.5").uuid, "a")
        compare(Logic.findDeviceByAddress(devices, "PC.lan").uuid, "a")
        compare(Logic.findDeviceByAddress(devices, "10.0.0.6:48000").uuid, "b")
        compare(Logic.findDeviceByAddress(devices, "10.0.0.6"), null)
        compare(Logic.findDeviceByAddress(devices, ""), null)
        compare(Logic.findDevice(devices, "b").uuid, "b")
        compare(Logic.findDevice(devices, "x"), null)
    }

    function test_displayAddress() {
        compare(Logic.displayAddress("10.0.0.5:47989"), "10.0.0.5")
        compare(Logic.displayAddress("10.0.0.5:48000"), "10.0.0.5:48000")
        compare(Logic.displayAddress("<NULL>"), "")
    }

    function test_states() {
        var paired = { online: true, paired: true, statusUnknown: false }
        compare(Logic.stateText(paired, ""), "在线")
        compare(Logic.stateText(paired, "远程桌面已打开"), "远程桌面已打开")
        compare(Logic.stateText({ online: true, paired: false }, ""), "未配对")
        compare(Logic.stateText({ online: false, paired: true }, ""), "离线")
        compare(Logic.stateText({ statusUnknown: true }, ""), "正在检测")
        compare(Logic.stateText({ online: true, paired: true, serverSupported: false }, ""), "版本不受支持")
        compare(Logic.stateKind(paired, "x"), "session")
        compare(Logic.stateKind(paired, ""), "online")
    }

    function test_messages() {
        verify(Logic.addFailedText(true).indexOf("网络") >= 0)
        verify(Logic.offlineText({ name: "A", wakeable: true }).indexOf("唤醒") >= 0)
        verify(Logic.offlineText({ name: "A", wakeable: false }).indexOf("唤醒") < 0)
        compare(Logic.progressTitle("Establishing connection to PC...", ""), "正在连接远程桌面…")
        compare(Logic.progressTitle("Quitting App...", "正在退出…"), "正在退出…")
        compare(Logic.progressTitle("等待被控端确认…", "x"), "等待被控端确认…")
    }

    function test_resolutionOptions() {
        var options = Logic.resolutionOptions(2560, 1600, 1920, 1080)
        compare(options[0].key, "native")
        compare(options.length, 1 + Logic.FIXED_RESOLUTIONS.length)
        compare(Logic.resolutionIndex(options, 1920, 1080), 2)
        options = Logic.resolutionOptions(0, 0, 1000, 700)
        compare(options[options.length - 1].key, "current")
        compare(Logic.resolutionIndex(options, 1000, 700), options.length - 1)
    }

    function test_fpsAndCodec() {
        compare(Logic.fpsOptions(60).length, Logic.FPS_VALUES.length)
        var custom = Logic.fpsOptions(75)
        compare(custom[custom.length - 1].value, 75)
        compare(Logic.codecIndex(Logic.VCC_FORCE_HEVC_HDR_DEPRECATED), Logic.codecIndex(Logic.VCC_FORCE_HEVC))
        compare(Logic.CODEC_OPTIONS[Logic.codecIndex(Logic.VCC_FORCE_AV1)].value, Logic.VCC_FORCE_AV1)
        compare(Logic.codecIndex(99), 0)
        compare(Logic.formatMbps(20000), "20 Mbps")
        compare(Logic.formatMbps(12500), "12.5 Mbps")
        verify(Logic.isWindowed(Logic.WM_WINDOWED))
        verify(!Logic.isWindowed(Logic.WM_FULLSCREEN_DESKTOP))
    }
}
