QT = core
CONFIG += console c++17
CONFIG -= app_bundle
TEMPLATE = app
TARGET = office-connectconfirm-test
INCLUDEPATH += ../../../app
SOURCES += connectconfirm_test.cpp ../../../app/office/connectconfirm.cpp
