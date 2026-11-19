QT = core
CONFIG += console c++17
CONFIG -= app_bundle
TEMPLATE = app
TARGET = office-displayscale-test
INCLUDEPATH += ../../../app
SOURCES += response_test.cpp ../../../app/office/displayscale.cpp
