#include "settings/streamingpreferences.h"
#include <QMetaProperty>

StreamingPreferences* StreamingPreferences::cloneForSession(QObject* parent) const {
    auto* copy = new StreamingPreferences(nullptr);
    copy->setParent(parent);
    // Copy all writable preference properties, including future upstream ones.
    // Do not copy QObject identity, connections, engine ownership or QSettings.
    for (int i = staticMetaObject.propertyOffset(); i < staticMetaObject.propertyCount(); ++i) {
        const auto property = staticMetaObject.property(i);
        if (property.isWritable()) property.write(copy, property.read(this));
    }
    copy->packetSize = packetSize; // non-QML preference
    copy->recommendedFullScreenMode = recommendedFullScreenMode; // CONSTANT property
    return copy;
}
