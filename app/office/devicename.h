#pragma once

#include <QByteArray>
#include <QString>

namespace office {
// Name shown to the host owner when this Mac asks to pair (CONNECTION.md §1).
// Removes control/format characters, trims whitespace and truncates on a code
// point boundary to at most 64 UTF-8 bytes. Empty results use "Moonlight Desk".
QByteArray sanitizePairingDeviceName(const QString& name);

// User-visible computer name (macOS "Computer Name"), else the host name.
QString localComputerName();

// Percent-encoded value for the GameStream `devicename` pairing query field.
QByteArray pairingDeviceNameQuery(const QString& name = localComputerName());
}
