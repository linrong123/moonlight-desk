HEADERS += $$PWD/recoverypolicy.h $$PWD/officestate.h $$PWD/toolbar.h $$PWD/types.h
SOURCES += $$PWD/officestate.cpp $$PWD/sessionhooks.cpp $$PWD/sessionpreferences.cpp \
    $$PWD/desksessions.cpp $$PWD/sessionbridge.cpp
HEADERS += $$PWD/desksessions.h $$PWD/sessionbridge.h
HEADERS += $$PWD/displayscale.h
SOURCES += $$PWD/displayscale.cpp
macx {
    SOURCES += $$PWD/toolbar_mac.mm
} else {
    SOURCES += $$PWD/toolbar_stub.cpp
}
