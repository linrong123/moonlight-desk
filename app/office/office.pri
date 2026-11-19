HEADERS += $$PWD/recoverypolicy.h $$PWD/officestate.h $$PWD/toolbar.h $$PWD/types.h
SOURCES += $$PWD/officestate.cpp $$PWD/sessionhooks.cpp $$PWD/sessionpreferences.cpp \
    $$PWD/desksessions.cpp $$PWD/sessionbridge.cpp
HEADERS += $$PWD/desksessions.h $$PWD/sessionbridge.h
HEADERS += $$PWD/displayscale.h $$PWD/devicename.h $$PWD/connectconfirm.h
SOURCES += $$PWD/displayscale.cpp $$PWD/devicename.cpp $$PWD/connectconfirm.cpp
macx {
    SOURCES += $$PWD/toolbar_mac.mm
    # devicename.cpp reads the user-visible Computer Name.
    LIBS += -framework SystemConfiguration -framework CoreFoundation
} else {
    SOURCES += $$PWD/toolbar_stub.cpp
}
