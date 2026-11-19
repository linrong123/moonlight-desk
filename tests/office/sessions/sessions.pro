QT += core network testlib
CONFIG += console c++17 testcase
CONFIG -= app_bundle
TEMPLATE = app
TARGET = office-sessions-test
INCLUDEPATH += ../../../app
HEADERS += ../../../app/office/desksessions.h ../../../app/office/sessionbridge.h
SOURCES += sessions.cpp ../../../app/office/desksessions.cpp ../../../app/office/sessionbridge.cpp
