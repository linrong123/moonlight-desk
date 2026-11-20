.pragma library

// Shared look of the Desk UI. Plain constants (no qmldir singleton) so the
// office directory keeps working as an implicit import for tests.

var background = "#f4f6fa"
var surface = "#ffffff"
var surfaceAlt = "#f7f9fc"
var border = "#e3e8f0"
var borderStrong = "#cfd7e3"

var text = "#1f2a3d"
var textMuted = "#6b778a"
var textFaint = "#98a2b3"

var accent = "#3b6ef5"
var accentPressed = "#2d59cf"
var accentSoft = "#e9effe"

var danger = "#d64545"
var dangerSoft = "#fdeeee"

var online = "#22a06b"
var pending = "#e0962b"
var offline = "#a3acba"
var session = accent

var radiusSmall = 6
var radius = 10
var radiusLarge = 14

var spacingSmall = 8
var spacing = 12
var spacingLarge = 20
var pageMargin = 32

var fontSmall = 12
var fontBody = 14
var fontTitle = 18
var fontHeadline = 24

var controlHeight = 36
var inputHeight = 44

function stateColor(kind) {
    if (kind === "online") return online
    if (kind === "session") return session
    if (kind === "pending") return pending
    return offline
}
