QT = core
CONFIG += console c++17
CONFIG -= app_bundle
TEMPLATE = app
TARGET = office-clipboard-test
INCLUDEPATH += ../../../app
HEADERS += ../../../app/office/clipboardsync.h ../../../app/office/clipboardresponse.h
SOURCES += clipboard_test.cpp ../../../app/office/clipboardsync.cpp ../../../app/office/clipboardresponse.cpp
