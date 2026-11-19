#pragma once

#include <QString>
#include <vector>

namespace office {
struct DisplayScaleResult {
    int status = 0;
    int current = 0;
    int recommended = 0;
    std::vector<int> supported;
    QString token;
    bool valid() const { return status == 200; }
};

// Strictly validates the complete response before returning any host data.
// Known host failures preserve only status; malformed responses return defaults.
DisplayScaleResult parseDisplayScaleResponse(const QString& response);
}
