QT -= core gui
CONFIG += console c++17
CONFIG -= app_bundle
TEMPLATE = app
TARGET = OfficeToolbarHiddenCheck
INCLUDEPATH += ../../../app ../../../libs/mac/include ../../../libs/mac/include/SDL2
LIBS += -L$$PWD/../../../libs/mac/lib -lSDL2 -framework AppKit
QMAKE_RPATHDIR += $$PWD/../../../libs/mac/lib
# The production implementation is included by the test to inspect its native
# delegate. Only this binary replaces NSAlert's presentation method; no window is shown.
OBJECTIVE_SOURCES += check.mm
