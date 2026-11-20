.pragma library

// Pure helpers for the Desk workbench. Kept free of QML types so tests can
// exercise them with plain objects.

var DEFAULT_PORT = 47989

// RFC 5952 text form of an IPv6 literal (lower case, longest zero run
// compressed, embedded IPv4 as hex), so different spellings of one address
// match. "" when invalid. A zone suffix ("%en0") is kept as is.
function canonicalIPv6(text) {
    var s = String(text), zone = "", pct = s.indexOf("%")
    if (pct >= 0) { zone = s.slice(pct); s = s.slice(0, pct) }
    var halves = s.split("::")
    if (halves.length > 2) return ""
    function groups(part, allowV4) {
        if (part === "") return []
        var list = part.split(":"), out = []
        for (var i = 0; i < list.length; ++i) {
            var g = list[i], m
            if (allowV4 && i === list.length - 1 && g.indexOf(".") >= 0) {
                m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(g)
                if (!m) return null
                var b = [+m[1], +m[2], +m[3], +m[4]]
                if (b[0] > 255 || b[1] > 255 || b[2] > 255 || b[3] > 255) return null
                out.push(b[0] * 256 + b[1], b[2] * 256 + b[3])
            } else {
                if (!/^[0-9a-f]{1,4}$/.test(g)) return null
                out.push(parseInt(g, 16))
            }
        }
        return out
    }
    var head = groups(halves[0], halves.length === 1)
    var tail = halves.length === 2 ? groups(halves[1], true) : []
    if (!head || !tail) return ""
    var all = head
    if (halves.length === 2) {
        var fill = 8 - head.length - tail.length
        if (fill < 1) return ""
        all = head.slice()
        for (var k = 0; k < fill; ++k) all.push(0)
        all = all.concat(tail)
    } else if (head.length !== 8) {
        return ""
    }
    var bestStart = -1, bestLen = 1
    for (var i = 0; i < 8;) {
        if (all[i] !== 0) { ++i; continue }
        var j = i
        while (j < 8 && all[j] === 0) ++j
        if (j - i > bestLen) { bestStart = i; bestLen = j - i }
        i = j
    }
    var hex = all.map(function(v) { return v.toString(16) })
    var out = bestStart < 0 ? hex.join(":")
                            : hex.slice(0, bestStart).join(":") + "::" + hex.slice(bestStart + bestLen).join(":")
    return out + zone
}

// Returns "host:port" (lower case) or "[v6]:port"; "" when the text is not a
// usable address. Mirrors ComputerManager::addNewHostManually closely enough
// to find an existing device before adding it again.
function normalizeAddress(text) {
    var s = String(text === undefined || text === null ? "" : text).trim().toLowerCase()
    s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//, "").replace(/\/+$/, "")
    if (!s || /\s/.test(s)) return ""
    var host = "", port = DEFAULT_PORT, m
    if ((m = /^\[([0-9a-f:.]+(%[a-z0-9_.-]+)?)\](?::(\d+))?$/.exec(s))) {
        host = canonicalIPv6(m[1])
        if (!host) return ""
        host = "[" + host + "]"
        if (m[3] !== undefined) port = parseInt(m[3], 10)
    } else if (s.indexOf(":") !== s.lastIndexOf(":")) {
        if (!/^[0-9a-f:.]+(%[a-z0-9_.-]+)?$/.test(s)) return ""
        host = canonicalIPv6(s)
        if (!host) return ""
        host = "[" + host + "]"
    } else {
        m = /^([a-z0-9_\u0080-\uffff](?:[a-z0-9_.\-\u0080-\uffff]*[a-z0-9_\u0080-\uffff])?)(?::(\d+))?$/.exec(s)
        if (!m || m[1].indexOf("..") >= 0) return ""
        host = m[1]
        if (m[2] !== undefined) port = parseInt(m[2], 10)
    }
    if (!(port >= 1 && port <= 65535)) return ""
    return host + ":" + port
}

// Address shown on a card: default port hidden.
function displayAddress(address) {
    if (!address || address === "<NULL>") return ""
    var suffix = ":" + DEFAULT_PORT
    var s = String(address)
    return s.length > suffix.length && s.slice(-suffix.length) === suffix ? s.slice(0, -suffix.length) : s
}

function findDeviceByAddress(devices, text) {
    var wanted = normalizeAddress(text)
    if (!wanted || !devices) return null
    for (var i = 0; i < devices.length; ++i) {
        var list = devices[i].addresses || []
        for (var j = 0; j < list.length; ++j) {
            if (normalizeAddress(list[j]) === wanted) return devices[i]
        }
        if (devices[i].address && normalizeAddress(devices[i].address) === wanted) return devices[i]
    }
    return null
}

function findDevice(devices, uuid) {
    if (!devices || !uuid) return null
    for (var i = 0; i < devices.length; ++i) if (devices[i].uuid === uuid) return devices[i]
    return null
}

function canConnect(d) {
    return !!d && d.online && d.paired && !d.statusUnknown && d.serverSupported !== false
}

// Connection-independent device state, plus the session status when one is open.
function stateText(d, sessionStatus) {
    if (sessionStatus) return sessionStatus
    if (!d) return ""
    if (d.statusUnknown) return "正在检测"
    if (!d.online) return "离线"
    if (d.serverSupported === false) return "版本不受支持"
    if (!d.paired) return "未配对"
    return "在线"
}

// "online" / "pending" / "offline" / "session"
function stateKind(d, sessionStatus) {
    if (sessionStatus) return "session"
    if (!d || d.statusUnknown) return "pending"
    if (!d.online) return "offline"
    if (!d.paired || d.serverSupported === false) return "pending"
    return "online"
}

// Main card button: {action, text, enabled}
function primaryAction(d, sessionActive) {
    if (sessionActive) return { action: "open", text: "显示桌面", enabled: true }
    if (!d) return { action: "", text: "连接", enabled: false }
    if (d.statusUnknown) return { action: "", text: "检测中", enabled: false }
    if (!d.online) {
        if (d.wakeable) return { action: "wake", text: "唤醒", enabled: true }
        return { action: "", text: "离线", enabled: false }
    }
    if (d.serverSupported === false) return { action: "", text: "不可用", enabled: false }
    if (!d.paired) return { action: "pair", text: "配对", enabled: true }
    return { action: "open", text: "连接", enabled: true }
}

// Items of the card "⋯" menu, in display order.
function menuActions(d, sessionActive) {
    var items = []
    if (!d) return items
    if (sessionActive) items.push({ action: "disconnect", text: "断开" })
    if (!sessionActive && !d.statusUnknown && d.online && !d.paired && d.serverSupported !== false)
        items.push({ action: "pair", text: "配对" })
    if (!sessionActive && !d.statusUnknown && !d.online && d.wakeable)
        items.push({ action: "wake", text: "唤醒" })
    items.push({ action: "rename", text: "重命名" })
    if (!sessionActive) items.push({ action: "remove", text: "移除" })
    return items
}

function hasAction(items, action) {
    for (var i = 0; i < items.length; ++i) if (items[i].action === action) return true
    return false
}

function addFailedText(detectedPortBlocking) {
    return detectedPortBlocking ? "无法连接这台电脑，网络可能阻止了连接。请检查地址与网络。"
                                : "无法连接这台电脑。请检查地址，并确认被控端已开机、串流服务已开启。"
}

function offlineText(d) {
    var name = d && d.name ? "“" + d.name + "”" : "这台电脑"
    return d && d.wakeable ? name + "当前离线。可在设备菜单中选择“唤醒”，开机后再连接。"
                           : name + "当前离线。请确认它已开机并联网。"
}

// Progress page title: keep Chinese stage texts, replace upstream English ones.
function progressTitle(text, fallback) {
    var s = String(text || "")
    return /[\u4e00-\u9fff]/.test(s) ? s : (fallback || "正在连接远程桌面…")
}

// Settings helpers ------------------------------------------------------------

var WM_FULLSCREEN = 0
var WM_FULLSCREEN_DESKTOP = 1
var WM_WINDOWED = 2
var VCC_AUTO = 0
var VCC_FORCE_H264 = 1
var VCC_FORCE_HEVC = 2
var VCC_FORCE_HEVC_HDR_DEPRECATED = 3
var VCC_FORCE_AV1 = 4
var CSK_OFF = 0
var CSK_FULLSCREEN = 1
var CSK_ALWAYS = 2

var FIXED_RESOLUTIONS = [
    { width: 1280, height: 720, text: "1280 × 720" },
    { width: 1920, height: 1080, text: "1920 × 1080" },
    { width: 2560, height: 1440, text: "2560 × 1440" },
    { width: 3840, height: 2160, text: "3840 × 2160（4K）" }
]

// Options for the resolution box. "native" follows this Mac's screen; an
// unmatched saved value is kept as a read-only "current" entry.
function resolutionOptions(nativeWidth, nativeHeight, width, height) {
    var options = []
    if (nativeWidth > 0 && nativeHeight > 0)
        options.push({ key: "native", width: nativeWidth, height: nativeHeight,
                       text: "跟随本机屏幕（" + nativeWidth + " × " + nativeHeight + "）" })
    for (var i = 0; i < FIXED_RESOLUTIONS.length; ++i) {
        var r = FIXED_RESOLUTIONS[i]
        options.push({ key: r.width + "x" + r.height, width: r.width, height: r.height, text: r.text })
    }
    if (resolutionIndex(options, width, height) < 0)
        options.push({ key: "current", width: width, height: height,
                       text: "当前：" + width + " × " + height })
    return options
}

function resolutionIndex(options, width, height) {
    for (var i = 0; i < options.length; ++i)
        if (options[i].width === width && options[i].height === height) return i
    return -1
}

var FPS_VALUES = [30, 60, 90, 120]

function fpsOptions(fps) {
    var options = []
    for (var i = 0; i < FPS_VALUES.length; ++i) options.push({ value: FPS_VALUES[i], text: FPS_VALUES[i] + " 帧/秒" })
    if (FPS_VALUES.indexOf(fps) < 0) options.push({ value: fps, text: "当前：" + fps + " 帧/秒" })
    return options
}

var CODEC_OPTIONS = [
    { value: VCC_AUTO, text: "自动（推荐）" },
    { value: VCC_FORCE_H264, text: "兼容优先（H.264）" },
    { value: VCC_FORCE_HEVC, text: "画质优先（HEVC）" },
    { value: VCC_FORCE_AV1, text: "更省流量（AV1，需新硬件）" }
]

function codecIndex(value) {
    if (value === VCC_FORCE_HEVC_HDR_DEPRECATED) value = VCC_FORCE_HEVC
    for (var i = 0; i < CODEC_OPTIONS.length; ++i) if (CODEC_OPTIONS[i].value === value) return i
    return 0
}

function isWindowed(windowMode) {
    return windowMode === WM_WINDOWED
}

function formatMbps(kbps) {
    var mbps = kbps / 1000
    return (Math.round(mbps * 10) / 10) + " Mbps"
}
