import QtQuick 2.0
import QtQuick.Controls 2.2

import SystemProperties 1.0

NavigableMessageDialog {
    // Office: no upstream troubleshooting link in the Desk UI.
    standardButtons: Dialog.Ok | ((SystemProperties.hasBrowser && !deskUi) ? Dialog.Help : 0)
}
