QT += core qml gui
CONFIG += console c++17
CONFIG -= app_bundle
TEMPLATE = app
TARGET = office-preferences-test
INCLUDEPATH += ../../../app
HEADERS += ../../../app/settings/streamingpreferences.h
SOURCES += preferences.cpp ../../../app/settings/streamingpreferences.cpp ../../../app/office/sessionpreferences.cpp
