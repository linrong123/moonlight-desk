import QtQuick 2.9
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.2
import "deskstyle.js" as Style
import "desklogic.js" as Logic

// Simple settings page for the Desk workbench. It edits the global defaults
// in the injected StreamingPreferences object (no storage of its own); every
// device still keeps its own resolution and mouse mode chosen in the session
// toolbar. "高级设置" opens the original SettingsView.
Rectangle {
    id: page
    objectName: "设置"
    Material.accent: Style.accent
    // main.qml finds an open settings page by this marker.
    readonly property bool deskSettingsPage: true
    color: Style.background

    // Injected by main.qml (StreamingPreferences); a plain object in tests.
    property var prefs: null
    property int nativeWidth: 0
    property int nativeHeight: 0
    property string versionString: ""
    property bool showWindowMode: true
    property bool windowModeEnabled: true
    property int recommendedFullScreenMode: prefs ? prefs.recommendedFullScreenMode : Logic.WM_FULLSCREEN

    signal advancedRequested()
    signal backRequested()

    readonly property int maxBitrate: prefs && prefs.unlockBitrate ? 500000 : 150000
    readonly property var resolutionOptions: prefs ? Logic.resolutionOptions(nativeWidth, nativeHeight, prefs.width, prefs.height) : []
    readonly property var fpsOptions: prefs ? Logic.fpsOptions(prefs.fps) : []

    function save() { if (prefs) prefs.save() }
    function defaultBitrate() {
        return prefs.getDefaultBitrate(prefs.width, prefs.height, prefs.fps, prefs.enableYUV444)
    }
    // Upstream rule: while bitrate is automatic it follows resolution/fps/444.
    function refreshAutoBitrate() {
        if (prefs.autoAdjustBitrate) prefs.bitrateKbps = defaultBitrate()
    }

    function setResolution(index) {
        var option = resolutionOptions[index]
        if (!option || (option.width === prefs.width && option.height === prefs.height)) return
        prefs.width = option.width
        prefs.height = option.height
        refreshAutoBitrate()
        save()
    }
    function setFps(index) {
        var option = fpsOptions[index]
        if (!option || option.value === prefs.fps) return
        prefs.fps = option.value
        refreshAutoBitrate()
        save()
    }
    function setAutoBitrate(on) {
        prefs.autoAdjustBitrate = on
        refreshAutoBitrate()
        save()
    }
    function setBitrate(kbps) {
        prefs.autoAdjustBitrate = false
        prefs.bitrateKbps = Math.max(500, Math.min(maxBitrate, Math.round(kbps / 500) * 500))
    }
    function setCodec(index) {
        prefs.videoCodecConfig = Logic.CODEC_OPTIONS[index].value
        save()
    }
    function setSharpText(on) {
        prefs.enableYUV444 = on
        refreshAutoBitrate()
        save()
    }
    function setWindowed(windowed) {
        prefs.windowMode = windowed ? Logic.WM_WINDOWED : recommendedFullScreenMode
        save()
    }
    function setPlayOnHost(onHost) { prefs.playAudioOnHost = onHost; save() }
    function setMuteOnFocusLoss(on) { prefs.muteOnFocusLoss = on; save() }
    function setSysKeys(mode) { prefs.captureSysKeysMode = mode; save() }
    function setSwapButtons(on) { prefs.swapMouseButtons = on; save() }
    function setReverseScroll(on) { prefs.reverseScrollDirection = on; save() }
    function setScrollSpeed(index) { prefs.scrollSpeed = [33, 67, 100][index]; save() }

    function goBack() {
        backRequested()
        if (StackView.view) StackView.view.pop()
    }

    StackView.onDeactivating: save()
    Component.onDestruction: save()

    // Controls stay bound to prefs: a click asks the page to write the pref
    // and the binding (not the click) moves the control, so changes made in
    // 高级设置 still show when coming back here.
    component PrefSwitch: Switch {
        property bool value: false
        signal userToggled(bool on)
        checked: value
        onToggled: {
            var on = checked
            checked = Qt.binding(function() { return value })
            userToggled(on)
        }
    }
    component PrefRadio: RadioButton {
        property bool value: false
        signal chosen()
        autoExclusive: false
        checked: value
        onToggled: {
            var on = checked
            checked = Qt.binding(function() { return value })
            if (on) chosen()
        }
    }
    component SectionTitle: Text {
        font.pixelSize: Style.fontBody
        font.bold: true
        color: Style.textMuted
        topPadding: Style.spacing
    }
    component Card: Rectangle {
        default property alias rows: cardColumn.data
        width: parent.width
        height: cardColumn.height
        radius: Style.radiusLarge
        color: Style.surface
        border.color: Style.border
        Column { id: cardColumn; width: parent.width }
    }
    // One labelled row; the control goes on the right.
    component SettingRow: Item {
        id: row
        property string label: ""
        property string hint: ""
        property bool divider: true
        default property alias control: slot.data
        width: parent ? parent.width : 0
        height: Math.max(56, texts.height + 24)
        Column {
            id: texts
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.right: slot.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { width: parent.width; text: row.label; font.pixelSize: Style.fontBody; color: Style.text; wrapMode: Text.Wrap }
            Text { width: parent.width; text: row.hint; visible: text !== ""; font.pixelSize: Style.fontSmall; color: Style.textFaint; wrapMode: Text.Wrap }
        }
        Item {
            id: slot
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
        Rectangle {
            visible: row.divider
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Style.border
        }
    }
    component Note: Text {
        x: 20
        width: parent.width - 40
        topPadding: 12
        bottomPadding: 14
        font.pixelSize: Style.fontSmall
        color: Style.textFaint
        wrapMode: Text.Wrap
    }

    // Header -------------------------------------------------------------------
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 64
        DeskButton {
            objectName: "backButton"
            anchors.left: parent.left
            anchors.leftMargin: Style.pageMargin - 12
            anchors.verticalCenter: parent.verticalCenter
            kind: "ghost"
            text: "‹  返回"
            onClicked: page.goBack()
        }
        Text {
            anchors.centerIn: parent
            text: "设置"
            font.pixelSize: Style.fontTitle
            font.bold: true
            color: Style.text
        }
    }

    Flickable {
        id: scroller
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: content.height + Style.pageMargin
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: content
            width: Math.min(720, scroller.width - 2 * Style.pageMargin)
            x: (scroller.width - width) / 2
            spacing: Style.spacingSmall
            enabled: page.prefs !== null

            // 画面 ----------------------------------------------------------------
            SectionTitle { text: "画面" }
            Card {
                SettingRow {
                    label: "分辨率"
                    hint: "新设备的默认值；在桌面窗口工具栏里改的分辨率会按设备记住。"
                    ComboBox {
                        id: resolutionBox
                        objectName: "resolutionBox"
                        width: 260
                        model: page.resolutionOptions
                        textRole: "text"
                        currentIndex: page.prefs ? Logic.resolutionIndex(page.resolutionOptions, page.prefs.width, page.prefs.height) : -1
                        onActivated: function(index) { page.setResolution(index) }
                    }
                }
                SettingRow {
                    label: "帧率"
                    hint: "越高越流畅，也更占带宽。"
                    ComboBox {
                        id: fpsBox
                        objectName: "fpsBox"
                        width: 260
                        model: page.fpsOptions
                        textRole: "text"
                        currentIndex: {
                            if (!page.prefs) return -1
                            for (var i = 0; i < page.fpsOptions.length; ++i)
                                if (page.fpsOptions[i].value === page.prefs.fps) return i
                            return -1
                        }
                        onActivated: function(index) { page.setFps(index) }
                    }
                }
                SettingRow {
                    label: "自动码率"
                    hint: page.prefs && page.prefs.autoAdjustBitrate
                          ? "按分辨率和帧率自动选择（当前 " + Logic.formatMbps(page.prefs.bitrateKbps) + "）"
                          : "关闭后可手动调整，网络较差时调低更稳定。"
                    PrefSwitch {
                        id: autoBitrateSwitch
                        objectName: "autoBitrateSwitch"
                        value: page.prefs ? page.prefs.autoAdjustBitrate : true
                        onUserToggled: function(on) { page.setAutoBitrate(on) }
                    }
                }
                Item {
                    objectName: "bitrateRow"
                    width: parent.width
                    height: visible ? 60 : 0
                    visible: page.prefs !== null && !page.prefs.autoAdjustBitrate
                    Slider {
                        id: bitrateSlider
                        objectName: "bitrateSlider"
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: bitrateLabel.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        from: 500
                        to: page.maxBitrate
                        stepSize: 500
                        snapMode: Slider.SnapAlways
                        value: page.prefs ? page.prefs.bitrateKbps : 500
                        onMoved: page.setBitrate(value)
                        onPressedChanged: if (!pressed) page.save()
                    }
                    Text {
                        id: bitrateLabel
                        objectName: "bitrateLabel"
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        width: 90
                        horizontalAlignment: Text.AlignRight
                        text: page.prefs ? Logic.formatMbps(page.prefs.bitrateKbps) : ""
                        font.pixelSize: Style.fontBody
                        color: Style.text
                    }
                    Rectangle { anchors.left: parent.left; anchors.leftMargin: 20; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Style.border }
                }
                SettingRow {
                    label: "画质偏好"
                    hint: "不确定就选“自动”。"
                    ComboBox {
                        id: codecBox
                        objectName: "codecBox"
                        width: 260
                        model: Logic.CODEC_OPTIONS
                        textRole: "text"
                        currentIndex: page.prefs ? Logic.codecIndex(page.prefs.videoCodecConfig) : 0
                        onActivated: function(index) { page.setCodec(index) }
                    }
                }
                SettingRow {
                    label: "文字更清晰"
                    hint: "办公、看代码时文字边缘更锐利；需要被控端和本机都支持，会多占带宽。"
                    PrefSwitch {
                        id: sharpTextSwitch
                        objectName: "sharpTextSwitch"
                        value: page.prefs ? page.prefs.enableYUV444 : false
                        onUserToggled: function(on) { page.setSharpText(on) }
                    }
                }
                SettingRow {
                    label: "显示方式"
                    hint: page.windowModeEnabled ? "进入桌面时使用全屏或窗口。" : "当前显示设备只支持全屏。"
                    divider: false
                    visible: page.showWindowMode
                    Row {
                        spacing: 4
                        enabled: page.windowModeEnabled
                        PrefRadio {
                            objectName: "fullscreenRadio"
                            text: "全屏"
                            value: page.prefs ? !Logic.isWindowed(page.prefs.windowMode) : true
                            onChosen: page.setWindowed(false)
                        }
                        PrefRadio {
                            objectName: "windowedRadio"
                            text: "窗口"
                            value: page.prefs ? Logic.isWindowed(page.prefs.windowMode) : false
                            onChosen: page.setWindowed(true)
                        }
                    }
                }
            }

            // 声音 ----------------------------------------------------------------
            SectionTitle { text: "声音" }
            Card {
                SettingRow {
                    label: "声音在哪里播放"
                    Row {
                        spacing: 4
                        PrefRadio {
                            objectName: "audioLocalRadio"
                            text: "本机"
                            value: page.prefs ? !page.prefs.playAudioOnHost : true
                            onChosen: page.setPlayOnHost(false)
                        }
                        PrefRadio {
                            objectName: "audioHostRadio"
                            text: "被控电脑"
                            value: page.prefs ? page.prefs.playAudioOnHost : false
                            onChosen: page.setPlayOnHost(true)
                        }
                    }
                }
                SettingRow {
                    label: "切到其他窗口时静音"
                    divider: false
                    PrefSwitch {
                        objectName: "muteOnFocusLossSwitch"
                        value: page.prefs ? page.prefs.muteOnFocusLoss : false
                        onUserToggled: function(on) { page.setMuteOnFocusLoss(on) }
                    }
                }
            }

            // 键鼠 ----------------------------------------------------------------
            SectionTitle { text: "键鼠" }
            Card {
                SettingRow {
                    label: "系统快捷键发给被控电脑"
                    hint: "如 ⌘Tab、⌘空格。开启后这些按键不再由本机处理。"
                    Row {
                        spacing: Style.spacingSmall
                        ComboBox {
                            objectName: "sysKeysModeBox"
                            width: 140
                            visible: sysKeysSwitch.checked
                            model: ["仅全屏时", "始终"]
                            currentIndex: page.prefs && page.prefs.captureSysKeysMode === Logic.CSK_ALWAYS ? 1 : 0
                            onActivated: function(index) { page.setSysKeys(index === 1 ? Logic.CSK_ALWAYS : Logic.CSK_FULLSCREEN) }
                        }
                        PrefSwitch {
                            id: sysKeysSwitch
                            objectName: "sysKeysSwitch"
                            anchors.verticalCenter: parent.verticalCenter
                            value: page.prefs ? page.prefs.captureSysKeysMode !== Logic.CSK_OFF : false
                            onUserToggled: function(on) { page.setSysKeys(on ? Logic.CSK_FULLSCREEN : Logic.CSK_OFF) }
                        }
                    }
                }
                SettingRow {
                    label: "交换鼠标左右键"
                    PrefSwitch {
                        objectName: "swapButtonsSwitch"
                        value: page.prefs ? page.prefs.swapMouseButtons : false
                        onUserToggled: function(on) { page.setSwapButtons(on) }
                    }
                }
                SettingRow {
                    label: "滚轮速度"
                    ComboBox {
                        objectName: "scrollSpeedBox"
                        width: 140
                        model: ["慢", "中", "快"]
                        currentIndex: page.prefs ? (page.prefs.scrollSpeed <= 50 ? 0 : (page.prefs.scrollSpeed <= 83 ? 1 : 2)) : 1
                        onActivated: function(index) { page.setScrollSpeed(index) }
                    }
                }
                SettingRow {
                    label: "反转滚轮方向"
                    divider: false
                    PrefSwitch {
                        objectName: "reverseScrollSwitch"
                        value: page.prefs ? page.prefs.reverseScrollDirection : false
                        onUserToggled: function(on) { page.setReverseScroll(on) }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Style.border }
                Note { text: "鼠标模式（本地指针 / 远端指针 / 相对）在桌面窗口工具栏切换，每台设备分别记住。滚轮速度“快”与 Windows 默认相同，每格约 3 行；“中”约 2 行，“慢”约 1 行。" }
            }

            // 关于 ----------------------------------------------------------------
            SectionTitle { text: "关于" }
            Card {
                SettingRow {
                    label: "版本"
                    Text {
                        objectName: "versionText"
                        text: page.versionString || "—"
                        font.pixelSize: Style.fontBody
                        color: Style.textMuted
                    }
                }
                SettingRow {
                    label: "开源许可"
                    hint: "Moonlight Desk 基于开源项目 Moonlight 修改，按 GNU GPL v3 许可发布。"
                    divider: false
                }
            }

            Item { width: 1; height: Style.spacing }
            Item {
                width: parent.width
                height: advancedButton.height
                DeskButton {
                    id: advancedButton
                    objectName: "advancedButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "高级设置"
                    onClicked: page.advancedRequested()
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "高级设置包含解码器、垂直同步、手柄等全部选项。"
                font.pixelSize: Style.fontSmall
                color: Style.textFaint
                wrapMode: Text.Wrap
            }
        }
    }
}
