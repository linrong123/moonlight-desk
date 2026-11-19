#include "settings/streamingpreferences.h"
#include <QCoreApplication>
#include <QMetaProperty>
#include <QPointer>
#include <QSettings>
#include <QTemporaryDir>
#include <cstdio>
#include <cstdlib>

static void require(bool condition) { if (!condition) std::abort(); }
// This target is macOS-only; preference tests do not initialize SDL/windowing.
namespace WMUtils { bool isRunningWayland() { return false; } }

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    QTemporaryDir temp;
    require(temp.isValid());
    QCoreApplication::setOrganizationName("Office tests");
    QCoreApplication::setApplicationName("preferences");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, temp.path());
    auto original = StreamingPreferences::get();
    original->width = 2560;
    original->height = 1440;
    original->packetSize = 1024;
    original->videoCodecConfig = StreamingPreferences::VCC_FORCE_H264;
    original->save();
    QPointer<StreamingPreferences> copy;
    {
        QObject owner;
        copy = original->cloneForSession(&owner);
        require(copy->parent() == &owner && copy != original);
        const auto& meta = StreamingPreferences::staticMetaObject;
        for (int i = meta.propertyOffset(); i < meta.propertyCount(); ++i) {
            const auto property = meta.property(i);
            require(property.read(original) == property.read(copy));
        }
        require(copy->packetSize == 1024);
        copy->width = 1920;
        copy->height = 1080;
        copy->absoluteMouseMode = !original->absoluteMouseMode;
        require(original->width == 2560 && original->height == 1440);
        require(copy->absoluteMouseMode != original->absoluteMouseMode);
        QSettings persisted;
        require(persisted.value("width").toInt() == 2560);
        require(persisted.value("height").toInt() == 1440);
        QObject nextOwner;
        auto next = copy->cloneForSession(&nextOwner);
        require(next->width == 1920 && next->height == 1080);
    }
    require(copy.isNull());
    std::puts("PASS: session preference snapshot, isolation, persistence and lifetime");
}
